package com.ausearch.aubackup.transport.aoa

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.charset.StandardCharsets

class AoaFrameCodecTest {
    @Test
    fun `encode and decode round trip`() {
        val requestId = "12345678-1234-1234-1234-123456789012"
        val payload = "hello".toByteArray(Charsets.UTF_8)
        val frame = AoaFrameCodec.encodeFrame(requestId, payload)
        assertEquals(1 + 36 + 4 + 1 + payload.size, frame.size)
        val decoded = AoaFrameCodec.decodeFrame(frame)
        assertEquals(requestId, decoded.requestId)
        assertEquals(AoaFrameCodec.FRAME_FLAG_TEXT, decoded.flags)
        assertEquals("hello", decoded.payload.toString(Charsets.UTF_8))

        val binaryFrame = AoaFrameCodec.encodeFrame(
            requestId,
            payload,
            flags = AoaFrameCodec.FRAME_FLAG_BINARY,
        )
        val decodedBinary = AoaFrameCodec.decodeFrame(binaryFrame)
        assertEquals(AoaFrameCodec.FRAME_FLAG_BINARY, decodedBinary.flags)
    }

    @Test
    fun `decoder accumulates partial reads`() {
        val decoder = AoaFrameCodec.StreamDecoder()
        val requestId = "12345678-1234-1234-1234-123456789012"
        val frame = AoaFrameCodec.encodeFrame(requestId, "payload".toByteArray(Charsets.UTF_8))
        val first = decoder.feed(frame.copyOfRange(0, 10))
        assertEquals(0, first.size)
        val second = decoder.feed(frame.copyOfRange(10, frame.size))
        assertEquals(1, second.size)
        assertEquals(requestId, second[0].requestId)
        assertEquals(AoaFrameCodec.FRAME_FLAG_TEXT, second[0].flags)
    }

    @Test
    fun `decode preserves raw requestId without trimming`() {
        val paddedRequestId = "12345678-1234-1234-1234-1234567890  "
        assertEquals(36, paddedRequestId.length)
        val frame = AoaFrameCodec.encodeFrame(paddedRequestId, "hello".toByteArray(Charsets.UTF_8))
        val decoded = AoaFrameCodec.decodeFrame(frame)
        assertEquals(paddedRequestId, decoded.requestId)
    }

    @Test(expected = AoaFrameCodecException::class)
    fun `encode rejects non-ASCII requestId`() {
        val requestId = "12345678-1234-1234-1234-1234567890éé"
        assertEquals(36, requestId.length)
        AoaFrameCodec.encodeFrame(requestId, "hello".toByteArray(Charsets.UTF_8))
    }

    @Test
    fun `decode throws on payload length mismatch`() {
        val requestId = "12345678-1234-1234-1234-123456789012"
        val header = ByteArray(AoaFrameCodec.HEADER_LENGTH)
        val buffer = ByteBuffer.wrap(header)
        buffer.put(AoaFrameCodec.FRAME_VERSION)
        buffer.put(requestId.toByteArray(StandardCharsets.US_ASCII))
        buffer.putInt(100)
        buffer.put(AoaFrameCodec.FRAME_FLAG_TEXT)
        val frame = header + "hello".toByteArray(Charsets.UTF_8)
        try {
            AoaFrameCodec.decodeFrame(frame)
            throw AssertionError("Expected AoaFrameCodecException")
        } catch (e: AoaFrameCodecException) {
            assertTrue(
                "Expected payload length mismatch message, got: ${e.message}",
                e.message!!.contains("payload length mismatch")
            )
        }
    }

    @Test
    fun `decoder rejects payload length exceeding maximum`() {
        val decoder = AoaFrameCodec.StreamDecoder()
        val requestId = "12345678-1234-1234-1234-123456789012"
        val header = ByteArray(AoaFrameCodec.HEADER_LENGTH)
        val buffer = ByteBuffer.wrap(header)
        buffer.put(AoaFrameCodec.FRAME_VERSION)
        buffer.put(requestId.toByteArray(StandardCharsets.US_ASCII))
        buffer.putInt(AoaFrameCodec.MAX_PAYLOAD_LENGTH + 1)
        buffer.put(AoaFrameCodec.FRAME_FLAG_TEXT)
        try {
            decoder.feed(header)
            throw AssertionError("Expected AoaFrameCodecException")
        } catch (e: AoaFrameCodecException) {
            assertTrue(
                "Expected payload length validation message, got: ${e.message}",
                e.message!!.contains("payload length")
            )
        }
    }
}
