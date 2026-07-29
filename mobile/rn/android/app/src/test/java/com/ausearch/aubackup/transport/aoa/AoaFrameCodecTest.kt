package com.ausearch.aubackup.transport.aoa

import org.junit.Assert.assertEquals
import org.junit.Test

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
}
