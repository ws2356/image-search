package com.ausearch.aubackup.transport.aoa

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.charset.StandardCharsets

data class AoaFrame(
    val requestId: String,
    val flags: Byte,
    val payload: ByteArray,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is AoaFrame) return false
        return requestId == other.requestId && flags == other.flags && payload.contentEquals(other.payload)
    }

    override fun hashCode(): Int {
        var result = requestId.hashCode()
        result = 31 * result + flags
        result = 31 * result + payload.contentHashCode()
        return result
    }
}

object AoaFrameCodec {
    const val FRAME_VERSION: Byte = 1
    const val REQUEST_ID_LENGTH: Int = 36
    const val HEADER_LENGTH: Int = 1 + REQUEST_ID_LENGTH + 4 + 1
    const val FRAME_FLAG_TEXT: Byte = 0x00
    const val FRAME_FLAG_BINARY: Byte = 0x01

    fun encodeFrame(requestId: String, payload: ByteArray, flags: Byte = FRAME_FLAG_TEXT): ByteArray {
        val requestIdBytes = requestId.toByteArray(StandardCharsets.US_ASCII)
        if (requestIdBytes.size != REQUEST_ID_LENGTH) {
            throw AoaFrameCodecException(
                "requestId must be exactly $REQUEST_ID_LENGTH ASCII bytes, got ${requestIdBytes.size}"
            )
        }
        if (requestId.any { it.code > 0x7F }) {
            throw AoaFrameCodecException("requestId must contain only ASCII characters")
        }
        if (flags != FRAME_FLAG_TEXT && flags != FRAME_FLAG_BINARY) {
            throw AoaFrameCodecException("Unsupported AOA frame flags: $flags")
        }
        val buffer = ByteBuffer.allocate(HEADER_LENGTH + payload.size)
        buffer.put(FRAME_VERSION)
        buffer.put(requestIdBytes)
        buffer.putInt(payload.size)
        buffer.put(flags)
        buffer.put(payload)
        return buffer.array()
    }

    fun decodeFrame(frame: ByteArray): AoaFrame {
        if (frame.size < HEADER_LENGTH) {
            throw AoaFrameCodecException(
                "AOA frame is too short for header (${frame.size} < $HEADER_LENGTH)"
            )
        }
        val buffer = ByteBuffer.wrap(frame)
        val version = buffer.get()
        if (version != FRAME_VERSION) {
            throw AoaFrameCodecException("Unsupported AOA frame version: $version")
        }
        val requestIdBytes = ByteArray(REQUEST_ID_LENGTH)
        buffer.get(requestIdBytes)
        val requestId = String(requestIdBytes, StandardCharsets.US_ASCII)
        if (requestId.isEmpty()) {
            throw AoaFrameCodecException("AOA frame requestId is empty")
        }
        val payloadLength = buffer.int
        val flags = buffer.get()
        if (flags != FRAME_FLAG_TEXT && flags != FRAME_FLAG_BINARY) {
            throw AoaFrameCodecException("Unsupported AOA frame flags: $flags")
        }
        if (buffer.remaining() < payloadLength) {
            throw AoaFrameCodecException(
                "AOA frame payload length mismatch: declared $payloadLength, " +
                    "remaining ${buffer.remaining()}"
            )
        }
        val payload = ByteArray(payloadLength)
        buffer.get(payload)
        return AoaFrame(requestId, flags, payload)
    }

    class StreamDecoder {
        private val buffer = ByteArrayOutputStream()

        fun feed(data: ByteArray): List<AoaFrame> {
            if (data.isEmpty()) return emptyList()
            buffer.write(data)
            val bytes = buffer.toByteArray()
            val frames = mutableListOf<AoaFrame>()
            var offset = 0
            while (true) {
                if (bytes.size - offset < HEADER_LENGTH) break
                val version = bytes[offset]
                if (version != FRAME_VERSION) {
                    throw AoaFrameCodecException("Unsupported AOA frame version: $version")
                }
                val flags = bytes[offset + REQUEST_ID_LENGTH + 4 + 1]
                if (flags != FRAME_FLAG_TEXT && flags != FRAME_FLAG_BINARY) {
                    throw AoaFrameCodecException("Unsupported AOA frame flags: $flags")
                }
                val payloadLength = readPayloadLength(bytes, offset)
                val frameLength = HEADER_LENGTH + payloadLength
                if (bytes.size - offset < frameLength) break
                val frame = bytes.copyOfRange(offset, offset + frameLength)
                offset += frameLength
                frames.add(decodeFrame(frame))
            }
            buffer.reset()
            buffer.write(bytes, offset, bytes.size - offset)
            return frames
        }

        private fun readPayloadLength(buffer: ByteArray, offset: Int): Int {
            val base = offset + 1 + REQUEST_ID_LENGTH
            return (
                ((buffer[base].toInt() and 0xFF) shl 24) or
                    ((buffer[base + 1].toInt() and 0xFF) shl 16) or
                    ((buffer[base + 2].toInt() and 0xFF) shl 8) or
                    (buffer[base + 3].toInt() and 0xFF)
            )
        }
    }
}
