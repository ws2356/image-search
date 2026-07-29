package com.ausearch.aubackup.transport.aoa

import android.app.Application
import android.content.Context
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.io.PipedInputStream
import java.io.PipedOutputStream
import java.nio.ByteBuffer
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class)
class AoaClientTest {

    private val executor = Executors.newSingleThreadExecutor()

    private lateinit var context: Context
    private lateinit var client: AoaClient
    private lateinit var testToClientInput: PipedInputStream
    private lateinit var testToClientOutput: PipedOutputStream
    private lateinit var clientToTestInput: PipedInputStream
    private lateinit var clientToTestOutput: PipedOutputStream
    private lateinit var testInputStream: InputStream
    private lateinit var testOutputStream: OutputStream

    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
        client = AoaClient.createForTest(context)
    }

    @After
    fun tearDown() {
        client.stop()
        executor.shutdownNow()
        if (::testInputStream.isInitialized) {
            closeQuietly(testInputStream)
        }
        if (::testOutputStream.isInitialized) {
            closeQuietly(testOutputStream)
        }
    }

    private fun openTestPipes() {
        testToClientInput = PipedInputStream()
        testToClientOutput = PipedOutputStream(testToClientInput)
        clientToTestInput = PipedInputStream()
        clientToTestOutput = PipedOutputStream(clientToTestInput)
        testInputStream = clientToTestInput
        testOutputStream = testToClientOutput
        client.openStreamsForTest(testToClientInput, clientToTestOutput)
    }

    @Test
    fun `prepareBootstrap stores sessionId oneTimePasscode and suggestedPort`() {
        client.prepareBootstrap("sid-001", "123456", 8080)
        assertEquals(AoaTransportState.PREPARING, client.currentState)
        assertEquals("sid-001", client.getPreparedSessionIdForTest())
        assertEquals(8080, client.getPreparedSuggestedPortForTest())
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
        client.prepareBootstrap("sid-001", "123456", 8080)
        openTestPipes()

        assertEquals(AoaTransportState.AUTHENTICATING, client.currentState)

        val rand = "aabbccddeeff00112233445566778899"
        val challengeEnvelope = buildAuthChallengeEnvelope(rand)
        writeFrame(AUTH_CHALLENGE_REQUEST_ID, challengeEnvelope.toByteArray(Charsets.UTF_8))

        val responseFrame = readFrame()
        assertEquals(AoaFrameCodec.FRAME_FLAG_TEXT, responseFrame.flags)
        assertEquals(AUTH_CHALLENGE_REQUEST_ID, responseFrame.requestId.trim())

        val responseEnvelope = JSONObject(String(responseFrame.payload, Charsets.UTF_8))
        assertEquals(AoaAuthResponder.MOBILE_TRANSPORT_ENVELOPE_SCHEMA, responseEnvelope.getString("schema"))
        assertEquals(AoaAuthResponder.AUTH_REQUEST_ID, responseEnvelope.getString("request_id"))
        assertEquals(200, responseEnvelope.getInt("status_code"))

        val responseBody = responseEnvelope.getJSONObject("body")
        assertEquals(AoaAuthResponder.MOBILE_PAIRING_SCHEMA, responseBody.getString("schema"))
        assertEquals(AoaAuthResponder.AUTH_STATUS_ACCEPTED, responseBody.getString("status"))

        val expectedProof = sha256Hex("123456$rand")
        assertEquals(expectedProof, responseBody.getString("proof"))

        assertEquals(AoaTransportState.CONNECTED, client.currentState)
        assertTrue(client.isConnected())
    }

    @Test
    fun `request response round trip correlates by request_id`() {
        client.prepareBootstrap("sid-001", "123456", 8080)
        openTestPipes()
        performAuthHandshake()

        val requestId = UUID.randomUUID().toString()
        val requestEnvelope = """
            {"operation":"test.echo","request_id":"$requestId","body":{"message":"hello"}}
        """.trimIndent().trim()

        val future = executor.submit<String> { client.sendRequest(requestEnvelope) }

        val outgoingFrame = readFrame()
        assertEquals(AoaFrameCodec.FRAME_FLAG_TEXT, outgoingFrame.flags)
        assertEquals(requestId, outgoingFrame.requestId.trim())
        assertEquals(requestEnvelope, String(outgoingFrame.payload, Charsets.UTF_8))

        val responseEnvelope = """
            {"request_id":"$requestId","body":{"echo":"hello"}}
        """.trimIndent().trim()
        writeFrame(requestId, responseEnvelope.toByteArray(Charsets.UTF_8))

        val result = future.get(5, TimeUnit.SECONDS)
        assertEquals(responseEnvelope, result)
    }

    @Test
    fun `streaming request lifecycle sends chunks and returns final response`() {
        client.prepareBootstrap("sid-001", "123456", 8080)
        openTestPipes()
        performAuthHandshake()

        val requestId = UUID.randomUUID().toString()
        val requestEnvelope = """
            {"operation":"asset.upload","request_id":"$requestId","body":{"total_bytes":1024}}
        """.trimIndent().trim()

        val streamingId = client.beginStreamingRequest(requestEnvelope)
        assertEquals(requestId, streamingId)

        val outgoingRequest = readFrame()
        assertEquals(AoaFrameCodec.FRAME_FLAG_TEXT, outgoingRequest.flags)
        assertEquals(requestId, outgoingRequest.requestId.trim())
        assertEquals(requestEnvelope, String(outgoingRequest.payload, Charsets.UTF_8))

        val chunk1 = byteArrayOf(0x01, 0x02, 0x03)
        client.sendBinaryChunk(requestId, chunk1)
        val outgoingChunk1 = readFrame()
        assertEquals(AoaFrameCodec.FRAME_FLAG_BINARY, outgoingChunk1.flags)
        assertEquals(requestId, outgoingChunk1.requestId.trim())
        assertArrayEquals(chunk1, outgoingChunk1.payload)

        val chunk2 = byteArrayOf(0x04, 0x05)
        client.sendBinaryChunk(requestId, chunk2)
        val outgoingChunk2 = readFrame()
        assertEquals(AoaFrameCodec.FRAME_FLAG_BINARY, outgoingChunk2.flags)
        assertArrayEquals(chunk2, outgoingChunk2.payload)

        val finalResponse = """
            {"request_id":"$requestId","body":{"status":"ok","received":5}}
        """.trimIndent().trim()

        val future = executor.submit<String> { client.finishStreamingRequest(requestId) }
        writeFrame(requestId, finalResponse.toByteArray(Charsets.UTF_8))

        val result = future.get(5, TimeUnit.SECONDS)
        assertEquals(finalResponse, result)
    }

    @Test
    fun `state listeners are notified on state changes`() {
        val observedStates = mutableListOf<AoaTransportState>()
        val listener = object : AoaClientListener {
            override fun onStateChanged(state: AoaTransportState) {
                observedStates.add(state)
            }
        }
        client.addStateListener(listener)

        client.prepareBootstrap("sid-001", "123456", 8080)
        openTestPipes()
        performAuthHandshake()

        assertTrue(observedStates.contains(AoaTransportState.PREPARING))
        assertTrue(observedStates.contains(AoaTransportState.AUTHENTICATING))
        assertTrue(observedStates.contains(AoaTransportState.CONNECTED))

        client.removeStateListener(listener)
    }

    @Test
    fun `reset stops client and clears bootstrap state`() {
        client.prepareBootstrap("sid-001", "123456", 8080)
        openTestPipes()
        performAuthHandshake()

        client.reset()

        assertEquals(AoaTransportState.IDLE, client.currentState)
        assertFalse(client.isConnected())
        assertEquals(null, client.getPreparedSessionIdForTest())
        assertEquals(-1, client.getPreparedSuggestedPortForTest())
    }

    private fun performAuthHandshake() {
        val rand = "aabbccddeeff00112233445566778899"
        val challengeEnvelope = buildAuthChallengeEnvelope(rand)
        writeFrame(AUTH_CHALLENGE_REQUEST_ID, challengeEnvelope.toByteArray(Charsets.UTF_8))
        readFrame()
    }

    private fun buildAuthChallengeEnvelope(rand: String): String {
        return """
            {"body":{"schema":"${AoaAuthResponder.MOBILE_PAIRING_SCHEMA}","sid":"sid-001","rand":"$rand"},"body_schema":"${AoaAuthResponder.MOBILE_PAIRING_SCHEMA}","operation":"${AoaAuthResponder.AUTH_OPERATION}","request_id":"${AoaAuthResponder.AUTH_REQUEST_ID}","schema":"${AoaAuthResponder.MOBILE_TRANSPORT_ENVELOPE_SCHEMA}"}
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
    }
}
