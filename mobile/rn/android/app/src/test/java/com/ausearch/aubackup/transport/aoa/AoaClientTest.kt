package com.ausearch.aubackup.transport.aoa

import android.app.Application
import android.content.Context
import android.hardware.usb.UsbAccessory
import android.hardware.usb.UsbManager
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors
import java.util.concurrent.FutureTask
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class)
class AoaClientTest {

    private val executor = Executors.newCachedThreadPool()

    private lateinit var context: Context
    private lateinit var client: AoaClient
    private lateinit var streamOpener: AoaStreamOpener
    private lateinit var testInputStream: InputStream
    private lateinit var testOutputStream: OutputStream

    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
        streamOpener = mockk()
        client = AoaClient(context, streamOpener, RESPONSE_TIMEOUT_MS_FOR_TESTS)
    }

    @After
    fun tearDown() {
        client.reset()
        executor.shutdownNow()
        if (::testInputStream.isInitialized) {
            closeQuietly(testInputStream)
        }
        if (::testOutputStream.isInitialized) {
            closeQuietly(testOutputStream)
        }
    }

    private fun stateObserver(): StateObserver = StateObserver(client)

    private class StateObserver(private val client: AoaClient) {
        private val states = mutableListOf<AoaTransportState>()
        private val latches = ConcurrentHashMap<AoaTransportState, CountDownLatch>()
        private val listener = object : AoaClientListener {
            override fun onStateChanged(state: AoaTransportState, errorMessage: String?) {
                synchronized(states) {
                    states.add(state)
                }
                latches[state]?.countDown()
            }
        }

        init {
            client.addListener(listener)
        }

        fun hasSeen(state: AoaTransportState): Boolean {
            synchronized(states) { return states.contains(state) }
        }

        fun countSeen(state: AoaTransportState): Int {
            synchronized(states) { return states.count { it == state } }
        }

        fun waitFor(state: AoaTransportState, timeoutMs: Long = 5000): Boolean {
            if (hasSeen(state)) {
                return true
            }
            val latch = latches.getOrPut(state) { CountDownLatch(1) }
            return latch.await(timeoutMs, TimeUnit.MILLISECONDS)
        }
    }

    private fun waitUntil(timeoutMs: Long, condition: () -> Boolean): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (condition()) {
                return true
            }
            Thread.sleep(50)
        }
        return condition()
    }

    /**
     * Simulates an attached, permission-granted matching accessory and stubs the
     * stream opener with deterministic test streams. Must be called before
     * [AoaClient.prepareBootstrap] so the attach probe finds the accessory.
     */
    private fun openTestPipes() {
        val clientToTestQueue = FrameQueue()
        val testToClientQueue = FrameQueue()

        testInputStream = FrameQueueInputStream(clientToTestQueue)
        testOutputStream = FrameQueueOutputStream(testToClientQueue)

        every { streamOpener.open(any()) } returns OpenedStreams(
            descriptor = null,
            inputStream = FrameQueueInputStream(testToClientQueue),
            outputStream = FrameQueueOutputStream(clientToTestQueue),
        )

        attachMatchingAccessory()
    }

    private fun attachMatchingAccessory() {
        val accessory = mockk<UsbAccessory>().apply {
            every { manufacturer } returns AoaClient.AOA_MANUFACTURER
            every { model } returns AoaClient.AOA_MODEL
            every { version } returns AoaClient.AOA_VERSION
        }
        val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
        shadowOf(usbManager).setAttachedUsbAccessory(accessory)
        shadowOf(usbManager).grantPermission(accessory)
    }

    /**
     * Thread-safe queue of byte chunks used to build deterministic test streams.
     */
    private class FrameQueue {
        private val chunks = LinkedBlockingQueue<ByteArray>()

        fun offer(chunk: ByteArray) {
            chunks.offer(chunk)
        }

        fun poll(timeoutMs: Long): ByteArray? = chunks.poll(timeoutMs, TimeUnit.MILLISECONDS)
    }

    /**
     * OutputStream that queues each write as a discrete chunk.
     */
    private class FrameQueueOutputStream(private val queue: FrameQueue) : OutputStream() {
        override fun write(b: Int) {
            queue.offer(byteArrayOf(b.toByte()))
        }

        override fun write(b: ByteArray, off: Int, len: Int) {
            queue.offer(b.copyOfRange(off, off + len))
        }
    }

    /**
     * InputStream fed by discrete byte chunks queued by the test peer.
     */
    private class FrameQueueInputStream(private val queue: FrameQueue) : InputStream() {
        private var current: ByteArray? = null
        private var offset = 0

        override fun read(): Int {
            val buffer = ByteArray(1)
            val read = read(buffer)
            return if (read < 0) -1 else buffer[0].toInt() and 0xFF
        }

        override fun read(b: ByteArray, off: Int, len: Int): Int {
            while (current == null || offset >= current!!.size) {
                current = try {
                    queue.poll(100)
                } catch (e: InterruptedException) {
                    Thread.currentThread().interrupt()
                    return -1
                } ?: return -1
                offset = 0
            }
            val available = current!!.size - offset
            val toRead = minOf(len, available)
            System.arraycopy(current!!, offset, b, off, toRead)
            offset += toRead
            return toRead
        }
    }

    @Test
    fun `prepareBootstrap transitions to preparing`() {
        val observer = stateObserver()
        client.prepareBootstrap("sid-001", "123456", 8080)
        assertTrue(observer.hasSeen(AoaTransportState.PREPARING))
    }

    @Test(expected = AoaTransportError.InvalidBootstrap::class)
    fun `prepareBootstrap rejects port zero`() {
        client.prepareBootstrap("sid-001", "123456", 0)
    }

    @Test(expected = AoaTransportError.InvalidBootstrap::class)
    fun `prepareBootstrap rejects port above 65535`() {
        client.prepareBootstrap("sid-001", "123456", 65536)
    }

    @Test
    fun `auth challenge handshake transitions to connected and echoes proof`() {
        val observer = stateObserver()
        openTestPipes()
        client.prepareBootstrap("sid-001", "123456", 8080)

        assertTrue(observer.hasSeen(AoaTransportState.AUTHENTICATING))

        val rand = "aabbccddeeff00112233445566778899"
        val challengeEnvelope = buildAuthChallengeEnvelope(rand)
        writeFrame(AUTH_CHALLENGE_REQUEST_ID, challengeEnvelope.toByteArray(Charsets.UTF_8))

        val responseFrame = readFrame()
        assertEquals(AoaFrameCodec.FRAME_FLAG_TEXT, responseFrame.flags)
        assertEquals(
            AUTH_CHALLENGE_REQUEST_ID.padEnd(AoaFrameCodec.REQUEST_ID_LENGTH, ' '),
            responseFrame.requestId,
        )

        val responseEnvelope = JSONObject(String(responseFrame.payload, Charsets.UTF_8))
        assertEquals(AoaAuthResponder.MOBILE_TRANSPORT_ENVELOPE_SCHEMA, responseEnvelope.getString("schema"))
        assertEquals(AoaAuthResponder.AUTH_REQUEST_ID, responseEnvelope.getString("request_id"))
        assertEquals(200, responseEnvelope.getInt("status_code"))

        val responseBody = responseEnvelope.getJSONObject("body")
        assertEquals(AoaAuthResponder.MOBILE_PAIRING_SCHEMA, responseBody.getString("schema"))
        assertEquals(AoaAuthResponder.AUTH_STATUS_ACCEPTED, responseBody.getString("status"))

        val expectedProof = sha256Hex("123456$rand")
        assertEquals(expectedProof, responseBody.getString("proof"))

        // The real attach flow (probe → permission → open) must have gone through the opener.
        verify { streamOpener.open(any()) }

        assertTrue(observer.waitFor(AoaTransportState.CONNECTED))
        assertTrue(client.isConnected())
    }

    @Test
    fun `request response round trip correlates by request_id`() {
        openTestPipes()
        client.prepareBootstrap("sid-001", "123456", 8080)
        performAuthHandshake()

        val requestId = UUID.randomUUID().toString()
        val requestEnvelope = """
            {"operation":"test.echo","request_id":"$requestId","body":{"message":"hello"}}
        """.trimIndent().trim()

        val responseEnvelope = """
            {"request_id":"$requestId","body":{"echo":"hello"}}
        """.trimIndent().trim()

        val peer = FutureTask<Unit> {
            val outgoingFrame = readFrame()
            assertEquals(AoaFrameCodec.FRAME_FLAG_TEXT, outgoingFrame.flags)
            assertEquals(requestId.padEnd(AoaFrameCodec.REQUEST_ID_LENGTH, ' '), outgoingFrame.requestId)
            assertEquals(requestEnvelope, String(outgoingFrame.payload, Charsets.UTF_8))
            writeFrame(requestId, responseEnvelope.toByteArray(Charsets.UTF_8))
        }
        executor.execute(peer)

        val result = client.sendRequest(requestEnvelope)

        peer.get(2, TimeUnit.SECONDS)
        assertEquals(responseEnvelope, result)
    }

    @Test
    fun `streaming request lifecycle sends chunks and returns final response`() {
        openTestPipes()
        client.prepareBootstrap("sid-001", "123456", 8080)
        performAuthHandshake()

        val requestId = UUID.randomUUID().toString()
        val requestEnvelope = """
            {"operation":"asset.upload","request_id":"$requestId","body":{"total_bytes":1024}}
        """.trimIndent().trim()

        val streamingId = client.beginStreamingRequest(requestEnvelope)
        assertEquals(requestId, streamingId)

        val outgoingRequest = readFrame()
        assertEquals(AoaFrameCodec.FRAME_FLAG_TEXT, outgoingRequest.flags)
        assertEquals(requestId.padEnd(AoaFrameCodec.REQUEST_ID_LENGTH, ' '), outgoingRequest.requestId)
        assertEquals(requestEnvelope, String(outgoingRequest.payload, Charsets.UTF_8))

        val chunk1 = byteArrayOf(0x01, 0x02, 0x03)
        client.sendBinaryChunk(requestId, chunk1)
        val outgoingChunk1 = readFrame()
        assertEquals(AoaFrameCodec.FRAME_FLAG_BINARY, outgoingChunk1.flags)
        assertEquals(requestId.padEnd(AoaFrameCodec.REQUEST_ID_LENGTH, ' '), outgoingChunk1.requestId)
        assertArrayEquals(chunk1, outgoingChunk1.payload)

        val chunk2 = byteArrayOf(0x04, 0x05)
        client.sendBinaryChunk(requestId, chunk2)
        val outgoingChunk2 = readFrame()
        assertEquals(AoaFrameCodec.FRAME_FLAG_BINARY, outgoingChunk2.flags)
        assertArrayEquals(chunk2, outgoingChunk2.payload)

        val future = executor.submit<String> { client.finishStreamingRequest(requestId) }

        val completionFrame = readFrame()
        assertEquals(AoaFrameCodec.FRAME_FLAG_TEXT, completionFrame.flags)
        assertEquals(requestId.padEnd(AoaFrameCodec.REQUEST_ID_LENGTH, ' '), completionFrame.requestId)
        val completionEnvelope = JSONObject(String(completionFrame.payload, Charsets.UTF_8))
        assertEquals(requestId, completionEnvelope.getString("request_id"))
        assertEquals(AoaAuthResponder.MOBILE_TRANSPORT_ENVELOPE_SCHEMA, completionEnvelope.getString("schema"))
        val completionBody = completionEnvelope.getJSONObject("body")
        assertEquals("complete", completionBody.getString("stream_state"))

        val finalResponse = """
            {"request_id":"$requestId","body":{"status":"ok","received":5}}
        """.trimIndent().trim()
        writeFrame(requestId, finalResponse.toByteArray(Charsets.UTF_8))

        val result = future.get(5, TimeUnit.SECONDS)
        assertEquals(finalResponse, result)
    }

    @Test
    fun `state listeners are notified on state changes`() {
        val observedStates = mutableListOf<AoaTransportState>()
        val listener = object : AoaClientListener {
            override fun onStateChanged(state: AoaTransportState, errorMessage: String?) {
                observedStates.add(state)
            }
        }
        client.addListener(listener)

        openTestPipes()
        client.prepareBootstrap("sid-001", "123456", 8080)
        performAuthHandshake()

        assertTrue(observedStates.contains(AoaTransportState.PREPARING))
        assertTrue(observedStates.contains(AoaTransportState.AUTHENTICATING))
        assertTrue(observedStates.contains(AoaTransportState.CONNECTED))

        client.removeListener(listener)
    }

    @Test
    fun `connection drop wakes blocked sendRequest with ConnectionLost`() {
        openTestPipes()
        client.prepareBootstrap("sid-001", "123456", 8080)
        performAuthHandshake()

        val requestId = UUID.randomUUID().toString()
        val requestEnvelope = """
            {"operation":"test.echo","request_id":"$requestId","body":{}}
        """.trimIndent().trim()

        val future = executor.submit<String> { client.sendRequest(requestEnvelope) }

        // Wait for the outgoing request frame; once it is on the wire the caller is blocked on the response.
        val outgoingFrame = readFrame()
        assertEquals(requestId.padEnd(AoaFrameCodec.REQUEST_ID_LENGTH, ' '), outgoingFrame.requestId)

        // Closing the pipe the client reads from triggers reader EOF → closeConnection → signal queues.
        closeQuietly(testOutputStream)

        try {
            future.get(2, TimeUnit.SECONDS)
            fail("Expected ConnectionLost")
        } catch (e: ExecutionException) {
            assertTrue(e.cause is AoaTransportError.ConnectionLost)
        }
    }

    @Test
    fun `reset stops client and clears bootstrap state`() {
        val observer = stateObserver()
        openTestPipes()
        client.prepareBootstrap("sid-001", "123456", 8080)
        performAuthHandshake()

        client.reset()

        assertTrue(observer.waitFor(AoaTransportState.IDLE))
        assertFalse(client.isConnected())

        // A fresh pairing after reset must not reuse the previous bootstrap values:
        // the auth challenge for the new session must be answered with the new proof.
        openTestPipes()
        client.prepareBootstrap("sid-002", "654321", 9090)

        val rand = "00112233445566778899aabbccddeeff"
        writeFrame(
            AUTH_CHALLENGE_REQUEST_ID,
            buildAuthChallengeEnvelope(rand, sid = "sid-002").toByteArray(Charsets.UTF_8),
        )
        val responseEnvelope = JSONObject(String(readFrame().payload, Charsets.UTF_8))
        assertEquals(sha256Hex("654321$rand"), responseEnvelope.getJSONObject("body").getString("proof"))

        assertTrue(observer.waitFor(AoaTransportState.CONNECTED))
    }

    @Test
    fun `prepareBootstrap with same material keeps an established connection`() {
        val observer = stateObserver()
        openTestPipes()
        client.prepareBootstrap("sid-001", "123456", 8080)
        performAuthHandshake()
        assertTrue(observer.waitFor(AoaTransportState.CONNECTED))

        client.prepareBootstrap("sid-001", "123456", 8080)

        assertTrue(client.isConnected())
        // The accessory was opened exactly once; the redundant prepare did not reopen it.
        verify(exactly = 1) { streamOpener.open(any()) }
    }

    @Test
    fun `prepareBootstrap with a different session reopens and re-authenticates`() {
        val observer = stateObserver()
        openTestPipes()
        client.prepareBootstrap("sid-001", "123456", 8080)
        performAuthHandshake()
        assertTrue(observer.waitFor(AoaTransportState.CONNECTED))

        openTestPipes()
        client.prepareBootstrap("sid-002", "654321", 9090)

        val rand = "00112233445566778899aabbccddeeff"
        writeFrame(
            AUTH_CHALLENGE_REQUEST_ID,
            buildAuthChallengeEnvelope(rand, sid = "sid-002").toByteArray(Charsets.UTF_8),
        )
        val responseEnvelope = JSONObject(String(readFrame().payload, Charsets.UTF_8))
        assertEquals(sha256Hex("654321$rand"), responseEnvelope.getJSONObject("body").getString("proof"))
        assertTrue(observer.waitFor(AoaTransportState.CONNECTED))
        verify(exactly = 2) { streamOpener.open(any()) }
    }

    @Test
    fun `auth challenge while connected triggers resync and reopens accessory`() {
        val observer = stateObserver()
        openTestPipes()
        client.prepareBootstrap("sid-001", "123456", 8080)
        performAuthHandshake()
        assertTrue(observer.waitFor(AoaTransportState.CONNECTED))

        // The desktop detected a desynced stream (e.g. after the OS froze the
        // process) and restarts its session with a fresh auth challenge. The
        // already-connected client must tear down the stale streams instead of
        // answering on a corrupted connection.
        writeFrame(
            AUTH_CHALLENGE_REQUEST_ID,
            buildAuthChallengeEnvelope("aabbccddeeff00112233445566778899").toByteArray(Charsets.UTF_8),
        )

        // The resync re-opens the accessory so the desktop's next probe can
        // re-authenticate on clean streams.
        verify(timeout = 5000, atLeast = 2) { streamOpener.open(any()) }

        // The client went through DISCONNECTED (stale teardown) and is now
        // waiting to re-authenticate; it must not report itself connected until
        // the new handshake completes.
        assertTrue(waitUntil(5000) { observer.countSeen(AoaTransportState.DISCONNECTED) >= 2 })
        assertTrue(observer.countSeen(AoaTransportState.AUTHENTICATING) >= 2)
        assertFalse(client.isConnected())
    }

    @Test
    fun `non matching accessory is ignored and not opened`() {
        val observer = stateObserver()
        val foreignAccessory = mockk<UsbAccessory>().apply {
            every { manufacturer } returns "OtherVendor"
            every { model } returns "OtherModel"
            every { version } returns "2.0"
        }
        val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
        shadowOf(usbManager).setAttachedUsbAccessory(foreignAccessory)

        client.prepareBootstrap("sid-001", "123456", 8080)

        assertTrue(observer.hasSeen(AoaTransportState.PREPARING))
        assertFalse(observer.hasSeen(AoaTransportState.AUTHENTICATING))
        verify(exactly = 0) { streamOpener.open(any()) }
    }

    private fun performAuthHandshake() {
        val rand = "aabbccddeeff00112233445566778899"
        val challengeEnvelope = buildAuthChallengeEnvelope(rand)
        writeFrame(AUTH_CHALLENGE_REQUEST_ID, challengeEnvelope.toByteArray(Charsets.UTF_8))
        readFrame()
    }

    private fun buildAuthChallengeEnvelope(rand: String, sid: String = "sid-001"): String {
        return """
            {"body":{"schema":"${AoaAuthResponder.MOBILE_PAIRING_SCHEMA}","sid":"$sid","rand":"$rand"},"body_schema":"${AoaAuthResponder.MOBILE_PAIRING_SCHEMA}","operation":"${AoaAuthResponder.AUTH_OPERATION}","request_id":"${AoaAuthResponder.AUTH_REQUEST_ID}","schema":"${AoaAuthResponder.MOBILE_TRANSPORT_ENVELOPE_SCHEMA}"}
        """.trimIndent().trim()
    }

    private fun writeFrame(requestId: String, payload: ByteArray) {
        val frame = AoaFrameCodec.encodeFrame(
            requestId.padEnd(AoaFrameCodec.REQUEST_ID_LENGTH, ' '),
            payload,
            AoaFrameCodec.FRAME_FLAG_TEXT,
        )
        testOutputStream.write(frame)
        testOutputStream.flush()
    }

    private fun readFrame(): AoaFrame {
        val header = ByteArray(AoaFrameCodec.HEADER_LENGTH)
        readFully(testInputStream, header)
        val buffer = ByteBuffer.wrap(header)
        buffer.get() // version
        val requestIdBytes = ByteArray(AoaFrameCodec.REQUEST_ID_LENGTH)
        buffer.get(requestIdBytes)
        val payloadLength = buffer.int
        buffer.get() // flags
        val payload = ByteArray(payloadLength)
        readFully(testInputStream, payload)
        val fullFrame = header + payload
        return AoaFrameCodec.decodeFrame(fullFrame)
    }

    private fun readFully(input: InputStream, buffer: ByteArray) {
        var offset = 0
        while (offset < buffer.size) {
            val read = input.read(buffer, offset, buffer.size - offset)
            if (read < 0) {
                throw IOException("Unexpected end of stream while reading ${buffer.size} bytes")
            }
            offset += read
        }
    }

    private fun sha256Hex(input: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
        return digest.digest(input.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
    }

    private fun closeQuietly(descriptor: java.io.Closeable?) {
        try {
            descriptor?.close()
        } catch (_: IOException) {
            // Ignore close errors in tests.
        }
    }

    companion object {
        private const val AUTH_CHALLENGE_REQUEST_ID = "auth-challenge"
        private const val RESPONSE_TIMEOUT_MS_FOR_TESTS = 500L
    }
}
