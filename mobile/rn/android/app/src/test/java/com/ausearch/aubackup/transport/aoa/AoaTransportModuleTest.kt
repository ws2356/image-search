@file:Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")

package com.ausearch.aubackup.transport.aoa

import android.app.Application
import android.content.Context
import com.facebook.react.bridge.Callback
import com.facebook.react.bridge.CatalystInstance
import com.facebook.react.bridge.Dynamic
import com.facebook.react.bridge.JavaScriptModule
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReadableArray
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.bridge.ReadableType
import com.facebook.react.bridge.UIManager
import com.facebook.react.bridge.WritableMap
import com.facebook.react.modules.core.DeviceEventManagerModule
import com.facebook.react.turbomodule.core.interfaces.CallInvokerHolder
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
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
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class)
class AoaTransportModuleTest {

    private lateinit var reactContext: TestReactApplicationContext
    private lateinit var module: AoaTransportModule
    private val testExecutor = Executors.newSingleThreadExecutor()
    private var testInputStream: InputStream? = null
    private var testOutputStream: OutputStream? = null

    @Before
    fun setUp() {
        AoaClient.resetInstance()
        reactContext = TestReactApplicationContext(RuntimeEnvironment.getApplication())
        module = AoaTransportModule(reactContext)
    }

    @After
    fun tearDown() {
        closeQuietly(testInputStream)
        closeQuietly(testOutputStream)
        testExecutor.shutdownNow()
        AoaClient.resetInstance()
    }

    @Test
    fun `module name is AoaTransportModule`() {
        assertEquals("AoaTransportModule", module.name)
    }

    @Test
    fun `prepareBootstrap resolves promise with valid session and port`() {
        val promise = TestPromise()
        module.prepareBootstrap("sid-001", "123456", 8080, promise)
        assertTrue("prepareBootstrap should resolve", promise.isResolved)
        assertNull(promise.resolvedValue)
    }

    @Test
    fun `isConnected reflects client state`() {
        assertFalse(module.isConnected())
        client().prepareBootstrap("sid-001", "123456", 8080)
        openTestPipes()
        performAuthHandshake()
        assertTrue(module.isConnected())
        client().reset()
        assertFalse(module.isConnected())
    }

    @Test
    fun `reset resolves promise and clears client to idle state`() {
        val idleLatch = CountDownLatch(1)
        client().addListener(object : AoaClientListener {
            override fun onStateChanged(state: AoaTransportState, errorMessage: String?) {
                if (state == AoaTransportState.IDLE) {
                    idleLatch.countDown()
                }
            }
        })

        client().prepareBootstrap("sid-001", "123456", 8080)
        openTestPipes()
        performAuthHandshake()
        assertTrue(module.isConnected())

        val promise = TestPromise()
        module.reset(promise)

        assertTrue("reset should resolve", promise.await())
        assertTrue(promise.isResolved)
        assertTrue("client should transition to IDLE", idleLatch.await(5, TimeUnit.SECONDS))
        assertFalse(module.isConnected())
        assertNull(client().getPreparedSessionIdForTest())
        assertEquals(-1, client().getPreparedSuggestedPortForTest())
    }

    @Test
    fun `sendRequest resolves with response envelope`() {
        client().prepareBootstrap("sid-001", "123456", 8080)
        openTestPipes()
        performAuthHandshake()

        val requestId = UUID.randomUUID().toString()
        val requestEnvelope = """
            {"operation":"test.echo","request_id":"$requestId","body":{"message":"hello"}}
        """.trimIndent().trim()
        val promise = TestPromise()
        module.sendRequest(requestEnvelope, promise)

        val outgoingFrame = readFrame()
        assertEquals(requestEnvelope, String(outgoingFrame.payload, Charsets.UTF_8))

        val responseEnvelope = """
            {"request_id":"$requestId","body":{"echo":"hello"}}
        """.trimIndent().trim()
        writeFrame(requestId, responseEnvelope.toByteArray(Charsets.UTF_8))

        assertTrue("sendRequest should resolve", promise.await())
        assertTrue(promise.isResolved)
        assertEquals(responseEnvelope, promise.resolvedValue)
    }

    @Test
    fun `beginStreamingRequest returns the request id`() {
        client().prepareBootstrap("sid-001", "123456", 8080)
        openTestPipes()
        performAuthHandshake()

        val requestId = UUID.randomUUID().toString()
        val requestEnvelope = """
            {"operation":"asset.upload","request_id":"$requestId","body":{"total_bytes":1024}}
        """.trimIndent().trim()
        val promise = TestPromise()
        module.beginStreamingRequest(requestEnvelope, promise)

        assertTrue("beginStreamingRequest should resolve", promise.await())
        assertTrue(promise.isResolved)
        assertEquals(requestId, promise.resolvedValue)
    }

    @Test
    fun `sendBinaryChunk resolves when chunk is queued`() {
        client().prepareBootstrap("sid-001", "123456", 8080)
        openTestPipes()
        performAuthHandshake()

        val requestId = UUID.randomUUID().toString()
        val requestEnvelope = """
            {"operation":"asset.upload","request_id":"$requestId","body":{"total_bytes":1024}}
        """.trimIndent().trim()
        val beginPromise = TestPromise()
        module.beginStreamingRequest(requestEnvelope, beginPromise)
        assertTrue(beginPromise.await())
        assertEquals(requestId, beginPromise.resolvedValue)

        val outgoingRequest = readFrame()
        assertEquals(AoaFrameCodec.FRAME_FLAG_TEXT, outgoingRequest.flags)
        assertEquals(requestEnvelope, String(outgoingRequest.payload, Charsets.UTF_8))

        val chunk = byteArrayOf(0x01, 0x02, 0x03)
        val chunkPromise = TestPromise()
        module.sendBinaryChunk(requestId, TestReadableArray(chunk.map { it.toInt() }), chunkPromise)

        assertTrue("sendBinaryChunk should resolve", chunkPromise.await())
        assertTrue(chunkPromise.isResolved)

        val outgoingChunk = readFrame()
        assertEquals(AoaFrameCodec.FRAME_FLAG_BINARY, outgoingChunk.flags)
        assertArrayEquals(chunk, outgoingChunk.payload)
    }

    @Test
    fun `finishStreamingRequest resolves with final response`() {
        client().prepareBootstrap("sid-001", "123456", 8080)
        openTestPipes()
        performAuthHandshake()

        val requestId = UUID.randomUUID().toString()
        val requestEnvelope = """
            {"operation":"asset.upload","request_id":"$requestId","body":{"total_bytes":1024}}
        """.trimIndent().trim()
        val beginPromise = TestPromise()
        module.beginStreamingRequest(requestEnvelope, beginPromise)
        assertTrue(beginPromise.await())
        assertEquals(requestId, beginPromise.resolvedValue)

        val finalResponse = """
            {"request_id":"$requestId","body":{"status":"ok","received":5}}
        """.trimIndent().trim()
        val finishPromise = TestPromise()
        module.finishStreamingRequest(requestId, finishPromise)

        writeFrame(requestId, finalResponse.toByteArray(Charsets.UTF_8))

        assertTrue("finishStreamingRequest should resolve", finishPromise.await())
        assertTrue(finishPromise.isResolved)
        assertEquals(finalResponse, finishPromise.resolvedValue)
    }

    @Test
    fun `AoaTransportStateChanged event is emitted with pascal case state`() {
        module.invalidate()
        val observingModule = TestAoaTransportModule(reactContext)

        client().prepareBootstrap("sid-001", "123456", 8080)

        assertEquals("PREPARING", observingModule.lastEmittedState)
        assertNull(observingModule.lastEmittedError)
    }

    @Test
    fun `invalidate removes listener and prevents further state events`() {
        val observingModule = TestAoaTransportModule(reactContext)

        observingModule.invalidate()
        client().prepareBootstrap("sid-001", "123456", 8080)

        assertNull(observingModule.lastEmittedState)
    }

    private fun client(): AoaClient = AoaClient.getInstance(reactContext.applicationContext)

    private fun openTestPipes() {
        val peerToClientOutput = PipedOutputStream()
        val peerToClientInput = PipedInputStream(peerToClientOutput, PIPE_BUFFER_SIZE)

        val clientToPeerOutput = PipedOutputStream()
        val clientToPeerInput = PipedInputStream(clientToPeerOutput, PIPE_BUFFER_SIZE)

        testInputStream = clientToPeerInput
        testOutputStream = peerToClientOutput
        client().openStreamsForTest(peerToClientInput, clientToPeerOutput)
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
        testOutputStream!!.write(frame)
        testOutputStream!!.flush()
    }

    private fun readFrame(): AoaFrame {
        val input = testInputStream!!
        val header = ByteArray(AoaFrameCodec.HEADER_LENGTH)
        readFully(input, header)
        val buffer = ByteBuffer.wrap(header)
        buffer.get() // version
        val requestIdBytes = ByteArray(AoaFrameCodec.REQUEST_ID_LENGTH)
        buffer.get(requestIdBytes)
        val payloadLength = buffer.int
        buffer.get() // flags
        val payload = ByteArray(payloadLength)
        readFully(input, payload)
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

    private fun closeQuietly(closeable: java.io.Closeable?) {
        try {
            closeable?.close()
        } catch (_: IOException) {
            // Ignore close errors in tests.
        }
    }

    /**
     * Minimal concrete [ReactApplicationContext] for unit tests.
     *
     * [AoaTransportModule] only needs lifecycle state checks and the device event
     * emitter; the rest of the ReactContext surface is intentionally stubbed out.
     */
    @Suppress("DEPRECATION")
    private class TestReactApplicationContext(context: Context) : ReactApplicationContext(context) {
        private var activeReactInstance = false
        private var deviceEventEmitter: DeviceEventManagerModule.RCTDeviceEventEmitter? = null

        fun setActiveReactInstance(active: Boolean) {
            activeReactInstance = active
        }

        fun setDeviceEventEmitter(emitter: DeviceEventManagerModule.RCTDeviceEventEmitter?) {
            deviceEventEmitter = emitter
        }

        override fun <T : JavaScriptModule> getJSModule(jsInterface: Class<T>): T {
            if (jsInterface == DeviceEventManagerModule.RCTDeviceEventEmitter::class.java) {
                @Suppress("UNCHECKED_CAST")
                return deviceEventEmitter as T
            }
            throw UnsupportedOperationException()
        }

        override fun <T : NativeModule> hasNativeModule(nativeModuleInterface: Class<T>): Boolean = false

        override fun getNativeModules(): MutableCollection<NativeModule> = mutableListOf()

        override fun <T : NativeModule> getNativeModule(nativeModuleInterface: Class<T>): T? = null

        override fun getNativeModule(name: String): NativeModule? = null

        override fun getCatalystInstance(): CatalystInstance {
            throw UnsupportedOperationException()
        }

        override fun hasActiveCatalystInstance(): Boolean = false
        override fun hasActiveReactInstance(): Boolean = activeReactInstance
        override fun hasCatalystInstance(): Boolean = false
        override fun hasReactInstance(): Boolean = false

        override fun destroy() {}
        override fun handleException(e: Exception) {}
        override fun isBridgeless(): Boolean = false
        override fun getJavaScriptContextHolder(): com.facebook.react.bridge.JavaScriptContextHolder? = null
        override fun getJSCallInvokerHolder(): CallInvokerHolder? = null
        override fun getFabricUIManager(): UIManager? = null
        override fun getSourceURL(): String? = null
        override fun registerSegment(segmentId: Int, path: String, callback: Callback) {}
    }

    private class TestAoaTransportModule(context: ReactApplicationContext) : AoaTransportModule(context) {
        var lastEmittedState: String? = null
            private set
        var lastEmittedError: String? = null
            private set

        override fun emitStateChanged(state: String, errorMessage: String?) {
            lastEmittedState = state
            lastEmittedError = errorMessage
        }
    }

    private class TestReadableArray(private val items: List<Int>) : ReadableArray {
        override fun size(): Int = items.size
        override fun getInt(index: Int): Int = items[index]
        override fun toArrayList(): ArrayList<Any?> = ArrayList(items)
        override fun getArray(index: Int): ReadableArray = throw UnsupportedOperationException()
        override fun getBoolean(index: Int): Boolean = throw UnsupportedOperationException()
        override fun getDouble(index: Int): Double = throw UnsupportedOperationException()
        override fun getDynamic(index: Int): Dynamic = throw UnsupportedOperationException()
        override fun getLong(index: Int): Long = throw UnsupportedOperationException()
        override fun getMap(index: Int): ReadableMap = throw UnsupportedOperationException()
        override fun getString(index: Int): String = throw UnsupportedOperationException()
        override fun getType(index: Int): ReadableType = throw UnsupportedOperationException()
        override fun isNull(index: Int): Boolean = false
    }

    private class TestPromise : Promise {
        var isResolved = false
            private set
        var isRejected = false
            private set
        var resolvedValue: Any? = null
            private set
        var rejectedCode: String? = null
            private set
        var rejectedMessage: String? = null
            private set
        var rejectedThrowable: Throwable? = null
            private set

        private val finishedLatch = CountDownLatch(1)

        fun await(timeoutMs: Long = 5000): Boolean = finishedLatch.await(timeoutMs, TimeUnit.MILLISECONDS)

        override fun resolve(value: Any?) {
            isResolved = true
            resolvedValue = value
            finishedLatch.countDown()
        }

        override fun reject(code: String?, message: String?) {
            reject(code, message, null)
        }

        override fun reject(code: String?, throwable: Throwable?) {
            reject(code, throwable?.message, throwable)
        }

        override fun reject(code: String?, message: String?, throwable: Throwable?) {
            isRejected = true
            rejectedCode = code
            rejectedMessage = message
            rejectedThrowable = throwable
            finishedLatch.countDown()
        }

        override fun reject(throwable: Throwable) {
            reject(null, throwable.message, throwable)
        }

        override fun reject(throwable: Throwable, userInfo: WritableMap) {
            reject(null, throwable.message, throwable)
        }

        override fun reject(code: String?, userInfo: WritableMap) {
            reject(code, null, null)
        }

        override fun reject(code: String?, throwable: Throwable?, userInfo: WritableMap) {
            reject(code, throwable?.message, throwable)
        }

        override fun reject(code: String?, message: String?, userInfo: WritableMap) {
            reject(code, message, null)
        }

        override fun reject(code: String?, message: String?, throwable: Throwable?, userInfo: WritableMap?) {
            isRejected = true
            rejectedCode = code
            rejectedMessage = message
            rejectedThrowable = throwable
            finishedLatch.countDown()
        }

        override fun reject(message: String) {
            reject(null, message, null)
        }
    }

    companion object {
        private const val AUTH_CHALLENGE_REQUEST_ID = "auth-challenge"
        private const val PIPE_BUFFER_SIZE = 64 * 1024
    }
}
