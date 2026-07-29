package com.ausearch.aubackup.transport.aoa

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
        require(requestIdBytes.size == REQUEST_ID_LENGTH) {
            "requestId must be exactly $REQUEST_ID_LENGTH ASCII bytes"
        }
        require(flags == FRAME_FLAG_TEXT || flags == FRAME_FLAG_BINARY) {
            "Unsupported AOA frame flags: $flags"
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
        require(frame.size >= HEADER_LENGTH) { "AOA frame is too short" }
        val buffer = ByteBuffer.wrap(frame)
        val version = buffer.get()
        require(version == FRAME_VERSION) { "Unsupported AOA frame version: $version" }
        val requestIdBytes = ByteArray(REQUEST_ID_LENGTH)
        buffer.get(requestIdBytes)
        val requestId = String(requestIdBytes, StandardCharsets.US_ASCII).trim()
        require(requestId.isNotEmpty()) { "AOA frame requestId is empty" }
        val payloadLength = buffer.int
        val flags = buffer.get()
        require(flags == FRAME_FLAG_TEXT || flags == FRAME_FLAG_BINARY) {
            "Unsupported AOA frame flags: $flags"
        }
        val payload = ByteArray(payloadLength)
        buffer.get(payload)
        require(payload.size == payloadLength) { "AOA frame payload length mismatch" }
        return AoaFrame(requestId, flags, payload)
    }

    class StreamDecoder {
        private val buffer = mutableListOf<Byte>()

        fun feed(data: ByteArray): List<AoaFrame> {
            data.forEach { buffer.add(it) }
            val frames = mutableListOf<AoaFrame>()
            while (true) {
                if (buffer.size < HEADER_LENGTH) break
                val version = buffer[0]
                if (version != FRAME_VERSION) {
                    throw IllegalStateException("Unsupported AOA frame version: $version")
                }
                val flags = buffer[1 + REQUEST_ID_LENGTH + 4]
                if (flags != FRAME_FLAG_TEXT && flags != FRAME_FLAG_BINARY) {
                    throw IllegalStateException("Unsupported AOA frame flags: $flags")
                }
                val payloadLength = ByteBuffer.wrap(
                    buffer.toByteArray(),
                    1 + REQUEST_ID_LENGTH,
                    4
                ).int
                val frameLength = HEADER_LENGTH + payloadLength
                if (buffer.size < frameLength) break
                val frame = buffer.subList(0, frameLength).toByteArray()
                buffer.subList(0, frameLength).clear()
                frames.add(decodeFrame(frame))
            }
            return frames
        }

        private fun List<Byte>.toByteArray(): ByteArray =
            ByteArray(size) { this[it] }
    }
}
