# Native Android AOA Runtime + RN Bridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the native Android AOA runtime (`AoaClient`), a React Native bridge module (`AoaTransportModule`), and register them so the TypeScript layer can prepare a bootstrap, send requests, stream asset chunks, and observe connection state.

**Architecture:** A Kotlin `AoaClient` singleton registers for USB accessory attach/detach events, opens the accessory, and runs reader/writer threads over a length-prefixed frame protocol. The RN bridge converts JS calls to Kotlin coroutines/callbacks and emits state-change events. The AOA auth challenge is handled natively using the `opt` passed to `prepareBootstrap`.

**Tech Stack:** Kotlin, Android SDK, React Native TurboModules, JUnit 4, Robolectric where applicable.

## Global Constraints

- Target Android API 24+ (use `ContextCompat` for receiver registration).
- Use the same AOA frame header as the desktop side: version 1, request_id 36 ASCII bytes, length big-endian, 1 reserved flags byte.
- The native runtime must reuse the existing `dtis.mobile-transport.v1` envelope schema and auth handshake from the iOS USB implementation.
- `opt` is stored in native memory only after `prepareBootstrap`; it is not logged or exposed to JavaScript.
- Tests must run without a physical device using fake `ParcelFileDescriptor` pipes.

---

## Task 1: AOA frame codec and constants

**Files:**
- Create: `android/app/src/main/java/com/ausearch/aubackup/transport/aoa/AoaFrameCodec.kt`
- Create: `android/app/src/main/java/com/ausearch/aubackup/transport/aoa/AoaTransportError.kt`
- Create: `android/app/src/main/java/com/ausearch/aubackup/transport/aoa/AoaTransportState.kt`
- Test: `android/app/src/test/java/com/ausearch/aubackup/transport/aoa/AoaFrameCodecTest.kt`

**Interfaces:**
- Consumes: nothing.
- Produces: `AoaFrameCodec.encodeFrame(requestId: String, payload: ByteArray): ByteArray`, `AoaFrameCodec.decodeFrame(frame: ByteArray): Pair<String, ByteArray>`, `AoaFrameStreamDecoder`, `AoaTransportError`, `AoaTransportState`.

- [ ] **Step 1: Write the failing test**

```kotlin
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
        val (decodedId, decodedPayload) = AoaFrameCodec.decodeFrame(frame)
        assertEquals(requestId, decodedId)
        assertEquals("hello", decodedPayload.toString(Charsets.UTF_8))
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
        assertEquals(requestId, second[0].first)
    }
}
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `./gradlew :app:testDebugUnitTest --tests "com.ausearch.aubackup.transport.aoa.AoaFrameCodecTest"`
Expected: `ClassNotFoundException` or `Unresolved reference` for `AoaFrameCodec`.

- [ ] **Step 3: Implement `AoaTransportState.kt` and `AoaTransportError.kt`**

```kotlin
package com.ausearch.aubackup.transport.aoa

enum class AoaTransportState {
    IDLE,
    PREPARING,
    AUTHENTICATING,
    CONNECTED,
    DISCONNECTED,
    FAILED,
}
```

```kotlin
package com.ausearch.aubackup.transport.aoa

sealed class AoaTransportError(message: String) : Exception(message) {
    class InvalidBootstrap(message: String) : AoaTransportError(message)
    class ConnectionUnavailable(message: String) : AoaTransportError(message)
    class SendFailed(message: String) : AoaTransportError(message)
    class ResponseTimedOut(message: String) : AoaTransportError(message)
    class InvalidEnvelope(message: String) : AoaTransportError(message)
    class AuthRejected(message: String) : AoaTransportError(message)
}
```

- [ ] **Step 4: Implement `AoaFrameCodec.kt`**

```kotlin
package com.ausearch.aubackup.transport.aoa

import java.nio.ByteBuffer
import java.nio.charset.StandardCharsets

object AoaFrameCodec {
    const val FRAME_VERSION: Byte = 1
    const val REQUEST_ID_LENGTH: Int = 36
    const val HEADER_LENGTH: Int = 1 + REQUEST_ID_LENGTH + 4 + 1

    fun encodeFrame(requestId: String, payload: ByteArray): ByteArray {
        val requestIdBytes = requestId.toByteArray(StandardCharsets.US_ASCII)
        require(requestIdBytes.size == REQUEST_ID_LENGTH) {
            "requestId must be exactly $REQUEST_ID_LENGTH ASCII bytes"
        }
        val buffer = ByteBuffer.allocate(HEADER_LENGTH + payload.size)
        buffer.put(FRAME_VERSION)
        buffer.put(requestIdBytes)
        buffer.putInt(payload.size)
        buffer.put(0)
        buffer.put(payload)
        return buffer.array()
    }

    fun decodeFrame(frame: ByteArray): Pair<String, ByteArray> {
        require(frame.size >= HEADER_LENGTH) { "AOA frame is too short" }
        val buffer = ByteBuffer.wrap(frame)
        val version = buffer.get()
        require(version == FRAME_VERSION) { "Unsupported AOA frame version: $version" }
        val requestIdBytes = ByteArray(REQUEST_ID_LENGTH)
        buffer.get(requestIdBytes)
        val requestId = String(requestIdBytes, StandardCharsets.US_ASCII).trim()
        require(requestId.isNotEmpty()) { "AOA frame requestId is empty" }
        val payloadLength = buffer.int
        val payload = ByteArray(payloadLength)
        buffer.get(payload)
        require(payload.size == payloadLength) { "AOA frame payload length mismatch" }
        return requestId to payload
    }

    class StreamDecoder {
        private val buffer = mutableListOf<Byte>()

        fun feed(data: ByteArray): List<Pair<String, ByteArray>> {
            data.forEach { buffer.add(it) }
            val frames = mutableListOf<Pair<String, ByteArray>>()
            while (true) {
                if (buffer.size < HEADER_LENGTH) break
                val version = buffer[0]
                if (version != FRAME_VERSION) {
                    throw IllegalStateException("Unsupported AOA frame version: $version")
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
```

- [ ] **Step 5: Run tests and confirm they pass**

Run: `./gradlew :app:testDebugUnitTest --tests "com.ausearch.aubackup.transport.aoa.AoaFrameCodecTest"`
Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add android/app/src/main/java/com/ausearch/aubackup/transport/aoa/AoaFrameCodec.kt \
        android/app/src/main/java/com/ausearch/aubackup/transport/aoa/AoaTransportError.kt \
        android/app/src/main/java/com/ausearch/aubackup/transport/aoa/AoaTransportState.kt \
        android/app/src/test/java/com/ausearch/aubackup/transport/aoa/AoaFrameCodecTest.kt
git commit -m "[LLM: opencode-go/kimi-k2.7-code] feat: Android AOA frame codec and state"
```

---

## Task 2: `AoaClient` core implementation

**Files:**
- Create: `android/app/src/main/java/com/ausearch/aubackup/transport/aoa/AoaClient.kt`
- Test: `android/app/src/test/java/com/ausearch/aubackup/transport/aoa/AoaClientTest.kt`

**Interfaces:**
- Consumes: `AoaFrameCodec`, `AoaTransportError`, `AoaTransportState`.
- Produces: `AoaClient` with `prepareBootstrap(sessionId, opt, suggestedPort)`, `reset()`, `isConnected()`, `sendRequest(envelopeJson)`, `beginStreamingRequest(envelopeJson)`, `sendBinaryChunk(requestId, chunk)`, `finishStreamingRequest(requestId)`, and an `AoaClientListener` interface.

- [ ] **Step 1: Write a failing test for request/response correlation**

```kotlin
package com.ausearch.aubackup.transport.aoa

import android.os.ParcelFileDescriptor
import com.facebook.react.bridge.Promise
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
class AoaClientTest {
    @Test
    fun `prepareBootstrap stores opt and sid`() {
        val client = AoaClient(RuntimeEnvironment.getApplication())
        val latch = CountDownLatch(1)
        var error: Throwable? = null
        client.prepareBootstrap("sid-001", "123456", 45000, object : Promise {
            override fun resolve(value: Any?) { latch.countDown() }
            override fun reject(code: String?, message: String?, throwable: Throwable?) {
                error = throwable
                latch.countDown()
            }
            override fun reject(throwable: Throwable?) { reject(null, null, throwable) }
        })
        latch.await(1, TimeUnit.SECONDS)
        assertEquals(null, error)
        assertEquals(true, client.hasPreparedBootstrap("sid-001", 45000))
    }
}
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `./gradlew :app:testDebugUnitTest --tests "com.ausearch.aubackup.transport.aoa.AoaClientTest"`
Expected: `ClassNotFoundException`.

- [ ] **Step 3: Implement `AoaClient.kt`**

```kotlin
package com.ausearch.aubackup.transport.aoa

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbAccessory
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import org.json.JSONObject
import java.util.concurrent.LinkedBlockingQueue

interface AoaClientListener {
    fun onStateChanged(state: AoaTransportState, errorMessage: String?)
}

class AoaClient(private val context: Context) {
    private val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                ACTION_USB_PERMISSION -> {
                    val accessory = extractAccessory(intent) ?: return
                    val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                    if (granted) {
                        openAccessory(accessory)
                    } else {
                        setState(AoaTransportState.FAILED, "USB accessory permission denied")
                    }
                }
                UsbManager.ACTION_USB_ACCESSORY_ATTACHED -> {
                    val accessory = extractAccessory(intent)
                    if (accessory != null) {
                        requestPermissionOrOpen(accessory)
                    } else {
                        probeAttachedAccessories()
                    }
                }
                UsbManager.ACTION_USB_ACCESSORY_DETACHED -> {
                    val accessory = extractAccessory(intent)
                    if (accessory == null || isSameAccessory(accessory, currentAccessory())) {
                        closeConnection()
                    }
                }
            }
        }
    }

    private val sessionId = AtomicReference<String?>(null)
    private val oneTimePasscode = AtomicReference<String?>(null)
    private val suggestedPort = AtomicReference<Int?>(null)
    private val isPrepared = AtomicBoolean(false)
    private val isAuthenticated = AtomicBoolean(false)
    private val currentAccessory = AtomicReference<UsbAccessory?>(null)
    private val descriptor = AtomicReference<ParcelFileDescriptor?>(null)
    private val readerThread = AtomicReference<Thread?>(null)
    private val writerThread = AtomicReference<Thread?>(null)
    private val inputStream = AtomicReference<FileInputStream?>(null)
    private val outputStream = AtomicReference<FileOutputStream?>(null)
    private val writeQueue = LinkedBlockingQueue<WriteTask>()
    private val pendingResponses = ConcurrentHashMap<String, ResponseLatch>()
    private val activeStreamingRequestIds = ConcurrentHashMap<String, Boolean>()
    private val listeners = mutableListOf<AoaClientListener>()
    private val decoder = AoaFrameCodec.StreamDecoder()
    private val running = AtomicBoolean(false)

    private data class WriteTask(val requestId: String, val payload: ByteArray)
    private class ResponseLatch {
        val latch = CountDownLatch(1)
        var response: String? = null
        var error: Throwable? = null
    }

    init {
        registerReceiver()
    }

    fun addListener(listener: AoaClientListener) {
        synchronized(listeners) { listeners.add(listener) }
    }

    fun removeListener(listener: AoaClientListener) {
        synchronized(listeners) { listeners.remove(listener) }
    }

    fun prepareBootstrap(sessionId: String, oneTimePasscode: String, suggestedPort: Int) {
        if (suggestedPort < 1 || suggestedPort > 65535) {
            throw AoaTransportError.InvalidBootstrap("Invalid suggested port: $suggestedPort")
        }
        this.sessionId.set(sessionId)
        this.oneTimePasscode.set(oneTimePasscode)
        this.suggestedPort.set(suggestedPort)
        this.isPrepared.set(true)
        this.isAuthenticated.set(false)
        setState(AoaTransportState.PREPARING)
        probeAttachedAccessories()
    }

    fun hasPreparedBootstrap(sessionId: String, suggestedPort: Int): Boolean {
        return this.sessionId.get() == sessionId &&
                this.suggestedPort.get() == suggestedPort &&
                this.isPrepared.get()
    }

    fun reset() {
        closeConnection()
        isPrepared.set(false)
        isAuthenticated.set(false)
        sessionId.set(null)
        oneTimePasscode.set(null)
        suggestedPort.set(null)
        pendingResponses.clear()
        activeStreamingRequestIds.clear()
        setState(AoaTransportState.IDLE)
    }

    fun isConnected(): Boolean {
        return isPrepared.get() && isAuthenticated.get() && descriptor.get() != null
    }

    fun sendRequest(envelopeJson: String): String {
        val requestId = extractRequestId(envelopeJson)
        val latch = ResponseLatch()
        pendingResponses[requestId] = latch
        writeFrame(requestId, envelopeJson.toByteArray(Charsets.UTF_8))
        if (!latch.latch.await(RESPONSE_TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
            pendingResponses.remove(requestId)
            throw AoaTransportError.ResponseTimedOut("Request $requestId timed out")
        }
        latch.error?.let { throw it }
        return latch.response ?: throw AoaTransportError.InvalidEnvelope("Empty response")
    }

    fun beginStreamingRequest(envelopeJson: String): String {
        val requestId = extractRequestId(envelopeJson)
        activeStreamingRequestIds[requestId] = true
        writeFrame(requestId, envelopeJson.toByteArray(Charsets.UTF_8))
        return requestId
    }

    fun sendBinaryChunk(requestId: String, chunk: ByteArray) {
        if (!activeStreamingRequestIds.containsKey(requestId)) {
            throw AoaTransportError.InvalidEnvelope("No active streaming request for $requestId")
        }
        writeFrame(requestId, chunk)
    }

    fun finishStreamingRequest(requestId: String): String {
        val latch = ResponseLatch()
        pendingResponses[requestId] = latch
        activeStreamingRequestIds.remove(requestId)
        if (!latch.latch.await(RESPONSE_TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
            pendingResponses.remove(requestId)
            throw AoaTransportError.ResponseTimedOut("Streaming request $requestId timed out")
        }
        latch.error?.let { throw it }
        return latch.response ?: throw AoaTransportError.InvalidEnvelope("Empty response")
    }

    private fun writeFrame(requestId: String, payload: ByteArray) {
        val frame = AoaFrameCodec.encodeFrame(requestId, payload)
        writeQueue.put(WriteTask(requestId, frame))
    }

    private fun extractRequestId(envelopeJson: String): String {
        val obj = JSONObject(envelopeJson)
        return obj.getString("request_id")
    }

    private fun registerReceiver() {
        val filter = IntentFilter().apply {
            addAction(ACTION_USB_PERMISSION)
            addAction(UsbManager.ACTION_USB_ACCESSORY_ATTACHED)
            addAction(UsbManager.ACTION_USB_ACCESSORY_DETACHED)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            context.registerReceiver(receiver, filter)
        }
    }

    private fun probeAttachedAccessories() {
        val accessories = usbManager.accessoryList ?: return
        accessories.firstOrNull()?.let { requestPermissionOrOpen(it) }
    }

    private fun requestPermissionOrOpen(accessory: UsbAccessory) {
        if (usbManager.hasPermission(accessory)) {
            openAccessory(accessory)
        } else {
            val permissionIntent = PendingIntent.getBroadcast(
                context,
                0,
                Intent(ACTION_USB_PERMISSION),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
            )
            usbManager.requestPermission(accessory, permissionIntent)
        }
    }

    @Synchronized
    private fun openAccessory(accessory: UsbAccessory) {
        closeConnection()
        val descriptor = usbManager.openAccessory(accessory) ?: return
        currentAccessory.set(accessory)
        this.descriptor.set(descriptor)
        inputStream.set(FileInputStream(descriptor.fileDescriptor))
        outputStream.set(FileOutputStream(descriptor.fileDescriptor))
        running.set(true)
        setState(AoaTransportState.AUTHENTICATING)
        readerThread.set(Thread({ readLoop() }, "AoaReader").apply { isDaemon = true; start() })
        writerThread.set(Thread({ writeLoop() }, "AoaWriter").apply { isDaemon = true; start() })
    }

    private fun readLoop() {
        val buffer = ByteArray(16 * 1024)
        try {
            while (running.get()) {
                val input = inputStream.get() ?: break
                val read = input.read(buffer)
                if (read < 0) break
                if (read > 0) {
                    processReadData(buffer.copyOfRange(0, read))
                }
            }
        } catch (e: IOException) {
            Log.w(TAG, "AOA read loop ended: ${e.message}")
        } finally {
            closeConnection()
        }
    }

    private fun processReadData(data: ByteArray) {
        val frames = decoder.feed(data)
        for ((requestId, payload) in frames) {
            if (payload.isEmpty()) continue
            if (payload[0] != '{'.code.toByte()) {
                // binary chunk
                continue
            }
            val json = payload.toString(Charsets.UTF_8)
            if (isAuthChallenge(json)) {
                handleAuthChallenge(json)
            } else {
                pendingResponses[requestId]?.let { latch ->
                    latch.response = json
                    latch.latch.countDown()
                }
            }
        }
    }

    private fun isAuthChallenge(json: String): Boolean {
        return try {
            val obj = JSONObject(json)
            obj.getString("operation") == "transport.auth.challenge"
        } catch (e: Exception) {
            false
        }
    }

    private fun handleAuthChallenge(json: String) {
        val challenge = JSONObject(json)
        val body = challenge.getJSONObject("body")
        val sid = body.getString("sid")
        val rand = body.getString("rand")
        val expectedSid = sessionId.get()
        val opt = oneTimePasscode.get()
        if (sid != expectedSid || opt == null) {
            setState(AoaTransportState.FAILED, "AOA auth challenge rejected: invalid session")
            return
        }
        val proof = sha256(opt + rand)
        val response = JSONObject().apply {
            put("schema", "dtis.mobile-transport.v1")
            put("request_id", "auth-challenge")
            put("status_code", 200)
            putJSONObject("body").apply {
                put("schema", "dtis.mobile-pairing.v1")
                put("status", "accepted")
                put("proof", proof)
            }
        }
        writeFrame("auth-challenge", response.toString().toByteArray(Charsets.UTF_8))
        isAuthenticated.set(true)
        setState(AoaTransportState.CONNECTED)
    }

    private fun writeLoop() {
        try {
            while (running.get()) {
                val task = writeQueue.poll(1, TimeUnit.SECONDS) ?: continue
                val output = outputStream.get() ?: break
                output.write(task.payload)
                output.flush()
            }
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
        } catch (e: IOException) {
            Log.w(TAG, "AOA write loop ended: ${e.message}")
        }
    }

    @Synchronized
    private fun closeConnection() {
        running.set(false)
        isAuthenticated.set(false)
        readerThread.get()?.interrupt()
        readerThread.set(null)
        writerThread.get()?.interrupt()
        writerThread.set(null)
        try { inputStream.get()?.close() } catch (_: IOException) {}
        inputStream.set(null)
        try { outputStream.get()?.close() } catch (_: IOException) {}
        outputStream.set(null)
        try { descriptor.get()?.close() } catch (_: IOException) {}
        descriptor.set(null)
        currentAccessory.set(null)
        if (isPrepared.get()) {
            setState(AoaTransportState.DISCONNECTED)
        }
        pendingResponses.values.forEach { it.error = AoaTransportError.ConnectionUnavailable("USB disconnected"); it.latch.countDown() }
        pendingResponses.clear()
    }

    private fun setState(state: AoaTransportState, errorMessage: String? = null) {
        synchronized(listeners) {
            listeners.forEach { it.onStateChanged(state, errorMessage) }
        }
    }

    private fun currentAccessory(): UsbAccessory? {
        return usbManager.accessoryList?.firstOrNull()
    }

    private fun extractAccessory(intent: Intent): UsbAccessory? {
        @Suppress("DEPRECATION")
        return intent.getParcelableExtra(UsbManager.EXTRA_ACCESSORY)
    }

    private fun isSameAccessory(first: UsbAccessory?, second: UsbAccessory?): Boolean {
        if (first == null || second == null) return false
        return first.manufacturer == second.manufacturer &&
                first.model == second.model &&
                first.version == second.version
    }

    private fun sha256(input: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
        return digest.digest(input.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
    }

    companion object {
        private const val TAG = "AoaClient"
        private const val ACTION_USB_PERMISSION = "com.ausearch.aubackup.USB_ACCESSORY_PERMISSION"
        private const val RESPONSE_TIMEOUT_SECONDS = 10L
    }
}
```

- [ ] **Step 4: Run tests and confirm they pass**

Run: `./gradlew :app:testDebugUnitTest --tests "com.ausearch.aubackup.transport.aoa.AoaClientTest"`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/com/ausearch/aubackup/transport/aoa/AoaClient.kt \
        android/app/src/test/java/com/ausearch/aubackup/transport/aoa/AoaClientTest.kt
git commit -m "[LLM: opencode-go/kimi-k2.7-code] feat: Android AOA client runtime"
```

---

## Task 3: React Native bridge module

**Files:**
- Create: `android/app/src/main/java/com/ausearch/aubackup/transport/aoa/AoaTransportModule.kt`
- Create: `android/app/src/main/java/com/ausearch/aubackup/transport/aoa/AoaTransportPackage.kt`
- Modify: `android/app/src/main/java/com/ausearch/aubackup/MainApplication.kt`
- Test: `android/app/src/test/java/com/ausearch/aubackup/transport/aoa/AoaTransportModuleTest.kt`

**Interfaces:**
- Consumes: `AoaClient`.
- Produces: `NativeModules.AoaTransportModule` with methods `prepareBootstrap`, `reset`, `isConnected`, `sendRequest`, `beginStreamingRequest`, `sendBinaryChunk`, `finishStreamingRequest`, and event `AoaTransportStateChanged`.

- [ ] **Step 1: Implement `AoaTransportModule.kt`**

```kotlin
package com.ausearch.aubackup.transport.aoa

import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.ReadableArray
import com.facebook.react.modules.core.DeviceEventManagerModule

class AoaTransportModule(
    private val reactContext: ReactApplicationContext,
    private val aoaClient: AoaClient = AoaClient(reactContext),
) : ReactContextBaseJavaModule(reactContext) {

    init {
        aoaClient.addListener(object : AoaClientListener {
            override fun onStateChanged(state: AoaTransportState, errorMessage: String?) {
                emitStateChanged(state.name, errorMessage)
            }
        })
    }

    override fun getName(): String = "AoaTransportModule"

    @ReactMethod
    fun prepareBootstrap(sessionId: String, oneTimePasscode: String, suggestedPort: Int, promise: Promise) {
        try {
            aoaClient.prepareBootstrap(sessionId, oneTimePasscode, suggestedPort)
            promise.resolve(null)
        } catch (e: Throwable) {
            promise.reject("AOA_PREPARE_FAILED", e.message, e)
        }
    }

    @ReactMethod
    fun reset(promise: Promise) {
        aoaClient.reset()
        promise.resolve(null)
    }

    @ReactMethod(isBlockingSynchronousMethod = true)
    fun isConnected(): Boolean = aoaClient.isConnected()

    @ReactMethod
    fun sendRequest(envelopeJson: String, promise: Promise) {
        try {
            val response = aoaClient.sendRequest(envelopeJson)
            promise.resolve(response)
        } catch (e: Throwable) {
            promise.reject("AOA_SEND_REQUEST_FAILED", e.message, e)
        }
    }

    @ReactMethod
    fun beginStreamingRequest(envelopeJson: String, promise: Promise) {
        try {
            val requestId = aoaClient.beginStreamingRequest(envelopeJson)
            promise.resolve(requestId)
        } catch (e: Throwable) {
            promise.reject("AOA_BEGIN_STREAM_FAILED", e.message, e)
        }
    }

    @ReactMethod
    fun sendBinaryChunk(requestId: String, chunk: ReadableArray, promise: Promise) {
        try {
            val bytes = ByteArray(chunk.size()) { chunk.getInt(it).toByte() }
            aoaClient.sendBinaryChunk(requestId, bytes)
            promise.resolve(null)
        } catch (e: Throwable) {
            promise.reject("AOA_SEND_CHUNK_FAILED", e.message, e)
        }
    }

    @ReactMethod
    fun finishStreamingRequest(requestId: String, promise: Promise) {
        try {
            val response = aoaClient.finishStreamingRequest(requestId)
            promise.resolve(response)
        } catch (e: Throwable) {
            promise.reject("AOA_FINISH_STREAM_FAILED", e.message, e)
        }
    }

    @ReactMethod
    fun addListener(eventName: String) {
        // Required for RN EventEmitter.
    }

    @ReactMethod
    fun removeListeners(count: Int) {
        // Required for RN EventEmitter.
    }

    private fun emitStateChanged(state: String, errorMessage: String?) {
        val params = Arguments.createMap().apply {
            putString("state", state)
            if (errorMessage != null) putString("errorMessage", errorMessage) else putNull("errorMessage")
        }
        reactContext
            .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
            .emit("AoaTransportStateChanged", params)
    }
}
```

- [ ] **Step 2: Implement `AoaTransportPackage.kt`**

```kotlin
package com.ausearch.aubackup.transport.aoa

import com.facebook.react.ReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.uimanager.ViewManager

class AoaTransportPackage : ReactPackage {
    override fun createNativeModules(reactContext: ReactApplicationContext): List<NativeModule> {
        return listOf(AoaTransportModule(reactContext))
    }

    override fun createViewManagers(reactContext: ReactApplicationContext): List<ViewManager<*, *>> {
        return emptyList()
    }
}
```

- [ ] **Step 3: Register package in `MainApplication.kt`**

Modify the `PackageList` block:

```kotlin
override val reactHost: ReactHost by lazy {
    ExpoReactHostFactory.getDefaultReactHost(
        context = applicationContext,
        packageList =
            PackageList(this).packages.apply {
                add(BackupTransferServicePackage())
                add(AoaTransportPackage())
            }
    )
}
```

Also replace `AoaPocAccessoryRuntime` with `AoaClient` initialization:

```kotlin
override fun onCreate() {
    super.onCreate()
    ...
    AoaClient(this)
}

override fun onTerminate() {
    super.onTerminate()
}
```

- [ ] **Step 4: Write a bridge test**

```kotlin
package com.ausearch.aubackup.transport.aoa

import com.facebook.react.bridge.ReactApplicationContext
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

@RunWith(RobolectricTestRunner::class)
class AoaTransportModuleTest {
    @Test
    fun `module name is AoaTransportModule`() {
        val module = AoaTransportModule(RuntimeEnvironment.getApplication() as ReactApplicationContext)
        assertEquals("AoaTransportModule", module.name)
    }
}
```

- [ ] **Step 5: Run tests**

Run: `./gradlew :app:testDebugUnitTest --tests "com.ausearch.aubackup.transport.aoa.*"`
Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add android/app/src/main/java/com/ausearch/aubackup/transport/aoa/AoaTransportModule.kt \
        android/app/src/main/java/com/ausearch/aubackup/transport/aoa/AoaTransportPackage.kt \
        android/app/src/main/java/com/ausearch/aubackup/MainApplication.kt \
        android/app/src/test/java/com/ausearch/aubackup/transport/aoa/AoaTransportModuleTest.kt
git commit -m "[LLM: opencode-go/kimi-k2.7-code] feat: RN AOA transport bridge module"
```

---

## Task 4: Self-review

- [ ] Confirm every method in the spec's native bridge API is implemented.
- [ ] Confirm `opt` is never logged or returned to JS.
- [ ] Confirm the AOA frame header constants match the spec (version 1, request_id 36 bytes, header 42 bytes).
- [ ] Confirm auth proof uses `SHA256(opt + rand)`.
- [ ] Search for `TODO`, `TBD`, or `implement later` in the new files and tests.
- [ ] Confirm Robolectric test dependencies are present in `android/app/build.gradle`.

If any gaps are found, fix them before marking the plan complete.
