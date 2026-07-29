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
import androidx.annotation.VisibleForTesting
import org.json.JSONObject
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.BlockingQueue
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * Listener interface for AOA transport state changes.
 *
 * Implementations are invoked on the thread that triggered the state change.
 */
interface AoaClientListener {
    fun onStateChanged(state: AoaTransportState, errorMessage: String?)
}

/**
 * Internal result type for correlated request/response queues.
 * Allows a dropped connection to wake blocked callers with an error instead of a timeout.
 */
private sealed class ResponseResult {
    data class Success(val payload: String) : ResponseResult()
    data class Error(val error: AoaTransportError) : ResponseResult()
}

/**
 * Native Android AOA transport client.
 *
 * Owns the AOA state machine, registers for USB accessory events, and opens the
 * accessory bulk stream when a matching accessory is attached. The auth challenge
 * is handled locally using the one-time passcode supplied via [prepareBootstrap];
 * the opt never leaves the device.
 *
 * Use [getInstance] to obtain the production singleton.
 */
class AoaClient private constructor(private val context: Context) {

    private val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
    private val state = AtomicReference(AoaTransportState.IDLE)
    private val authResponder = AoaAuthResponder()
    private val outgoingQueue: BlockingQueue<ByteArray> = LinkedBlockingQueue()
    private val listeners = mutableListOf<AoaClientListener>()

    private val pendingResponses = ConcurrentHashMap<String, BlockingQueue<ResponseResult>>()
    private val pendingStreamingResponses = ConcurrentHashMap<String, BlockingQueue<ResponseResult>>()

    @Volatile
    private var preparedSessionId: String? = null
    @Volatile
    private var preparedOneTimePasscode: String? = null
    @Volatile
    private var preparedSuggestedPort: Int = -1
    @Volatile
    private var bootstrapPrepared = false
    private var permissionPendingIntent: PendingIntent? = null
    private var openedDescriptor: ParcelFileDescriptor? = null
    private var readerThread: Thread? = null
    private var writerThread: Thread? = null
    private val stopped = AtomicBoolean(true)
    private var currentInputStream: InputStream? = null
    private var currentOutputStream: OutputStream? = null

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                UsbManager.ACTION_USB_ACCESSORY_ATTACHED -> {
                    if (!bootstrapPrepared) {
                        return
                    }
                    val accessory = extractAccessory(intent) ?: return probeAttachedAccessories()
                    requestAccessoryPermission(accessory)
                }
                UsbManager.ACTION_USB_ACCESSORY_DETACHED -> {
                    val detached = extractAccessory(intent)
                    if (detached == null || isSameAccessory(detached, currentAccessory())) {
                        closeConnection()
                    }
                }
                ACTION_USB_PERMISSION -> {
                    val accessory = extractAccessory(intent) ?: return
                    val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                    if (!granted) {
                        Log.w(LOG_TAG, "USB accessory permission denied.")
                        return
                    }
                    openAccessory(accessory)
                }
            }
        }
    }

    /**
     * Prepares the client with the pairing material from the scanned QR code.
     * If an accessory is already attached, this attempts to open it immediately.
     *
     * @throws AoaTransportError.InvalidBootstrap if [suggestedPort] is not in 1..65535.
     */
    @Synchronized
    fun prepareBootstrap(sessionId: String, oneTimePasscode: String, suggestedPort: Int) {
        if (suggestedPort !in 1..65535) {
            throw AoaTransportError.InvalidBootstrap(
                "suggestedPort must be in 1..65535, got $suggestedPort"
            )
        }
        preparedSessionId = sessionId
        preparedOneTimePasscode = oneTimePasscode
        preparedSuggestedPort = suggestedPort
        bootstrapPrepared = true
        transitionTo(AoaTransportState.PREPARING)
        startInternal()
        probeAttachedAccessories()
    }

    /**
     * Stops the client and clears bootstrap state, returning it to [AoaTransportState.IDLE].
     */
    @Synchronized
    fun reset() {
        stopInternal()
        clearBootstrapState()
        transitionTo(AoaTransportState.IDLE)
    }

    /**
     * Returns true only when the client is in the [AoaTransportState.CONNECTED] state.
     */
    fun isConnected(): Boolean = state.get() == AoaTransportState.CONNECTED

    /**
     * Sends a request envelope and blocks until the correlated response arrives.
     *
     * The [envelopeJson] must contain a `request_id` field. The returned string is the
     * JSON payload of the matching response envelope.
     *
     * @throws AoaTransportError.ConnectionUnavailable if the client is not connected.
     * @throws AoaTransportError.InvalidEnvelope if the envelope is not valid JSON or lacks a request_id.
     * @throws AoaTransportError.ResponseTimedOut if the response does not arrive in time.
     */
    fun sendRequest(envelopeJson: String): String {
        val requestId = extractRequestId(envelopeJson)
        val responseQueue = synchronized(this) {
            if (state.get() != AoaTransportState.CONNECTED) {
                throw AoaTransportError.ConnectionUnavailable(
                    "AOA client is not connected (state=${state.get()})"
                )
            }
            registerPendingResponse(requestId)
        }
        try {
            val frame = AoaFrameCodec.encodeFrame(
                padRequestId(requestId),
                envelopeJson.toByteArray(Charsets.UTF_8),
                AoaFrameCodec.FRAME_FLAG_TEXT,
            )
            outgoingQueue.put(frame)
            val result = responseQueue.poll(RESPONSE_TIMEOUT_MS, TimeUnit.MILLISECONDS)
                ?: throw AoaTransportError.ResponseTimedOut(
                    "No response received for request $requestId within ${RESPONSE_TIMEOUT_MS}ms"
                )
            return when (result) {
                is ResponseResult.Success -> result.payload
                is ResponseResult.Error -> throw result.error
            }
        } finally {
            pendingResponses.remove(requestId)
        }
    }

    /**
     * Begins a streaming request and returns its request_id.
     *
     * The request_id is taken from [envelopeJson] if present; otherwise a new UUID is
     * generated and the envelope is not rewritten. Callers that rely on a known
     * request_id should include it in the envelope.
     *
     * @throws AoaTransportError.ConnectionUnavailable if the client is not connected.
     * @throws AoaTransportError.InvalidEnvelope if the envelope is not valid JSON.
     */
    fun beginStreamingRequest(envelopeJson: String): String {
        ensureConnected()
        val requestId = extractRequestIdOrGenerate(envelopeJson)
        registerPendingStreamingResponse(requestId)
        val frame = AoaFrameCodec.encodeFrame(
            padRequestId(requestId),
            envelopeJson.toByteArray(Charsets.UTF_8),
            AoaFrameCodec.FRAME_FLAG_TEXT,
        )
        outgoingQueue.put(frame)
        return requestId
    }

    /**
     * Sends a binary chunk for an active streaming request.
     *
     * @throws AoaTransportError.ConnectionUnavailable if the client is not connected.
     * @throws AoaTransportError.SendFailed if [requestId] is not an active streaming request.
     */
    fun sendBinaryChunk(requestId: String, chunk: ByteArray) {
        ensureConnected()
        if (!pendingStreamingResponses.containsKey(requestId)) {
            throw AoaTransportError.SendFailed(
                "Cannot send binary chunk for inactive streaming request $requestId"
            )
        }
        val frame = AoaFrameCodec.encodeFrame(
            padRequestId(requestId),
            chunk,
            AoaFrameCodec.FRAME_FLAG_BINARY,
        )
        outgoingQueue.put(frame)
    }

    /**
     * Finishes a streaming request and waits for the final response.
     *
     * @throws AoaTransportError.ConnectionUnavailable if the client is not connected when this method is called.
     * @throws AoaTransportError.ConnectionLost if the connection drops while acquiring the response queue.
     * @throws AoaTransportError.SendFailed if [requestId] is not an active streaming request.
     * @throws AoaTransportError.ResponseTimedOut if the final response does not arrive in time.
     */
    fun finishStreamingRequest(requestId: String): String {
        ensureConnected()
        val responseQueue = synchronized(this) {
            if (state.get() != AoaTransportState.CONNECTED) {
                throw AoaTransportError.ConnectionLost("AOA connection lost")
            }
            pendingStreamingResponses[requestId]
                ?: throw AoaTransportError.SendFailed(
                    "Cannot finish inactive streaming request $requestId"
                )
        }
        try {
            val result = responseQueue.poll(RESPONSE_TIMEOUT_MS, TimeUnit.MILLISECONDS)
                ?: throw AoaTransportError.ResponseTimedOut(
                    "No final response received for streaming request $requestId within ${RESPONSE_TIMEOUT_MS}ms"
                )
            return when (result) {
                is ResponseResult.Success -> result.payload
                is ResponseResult.Error -> throw result.error
            }
        } finally {
            pendingStreamingResponses.remove(requestId)
        }
    }

    /**
     * Starts listening for USB accessory attach/detach events.
     * Safe to call multiple times; subsequent calls are ignored.
     *
     * This is an internal lifecycle step automatically invoked by [prepareBootstrap].
     * The client does not open an accessory until [prepareBootstrap] has been called,
     * matching the pairing flow where the QR code supplies the one-time passcode.
     */
    @Synchronized
    private fun startInternal() {
        if (!stopped.getAndSet(false)) {
            return
        }
        permissionPendingIntent = PendingIntent.getBroadcast(
            context,
            0,
            Intent(ACTION_USB_PERMISSION),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )
        registerReceiver()
    }

    /**
     * Registers a listener that will be invoked on every AOA transport state change.
     */
    fun addListener(listener: AoaClientListener) {
        synchronized(listeners) {
            listeners.add(listener)
        }
    }

    /**
     * Unregisters a previously added listener.
     */
    fun removeListener(listener: AoaClientListener) {
        synchronized(listeners) {
            listeners.remove(listener)
        }
    }

    @VisibleForTesting
    internal fun getPreparedSessionIdForTest(): String? = preparedSessionId

    @VisibleForTesting
    internal fun getPreparedSuggestedPortForTest(): Int = preparedSuggestedPort

    private fun ensureConnected() {
        if (state.get() != AoaTransportState.CONNECTED) {
            throw AoaTransportError.ConnectionUnavailable(
                "AOA client is not connected (state=${state.get()})"
            )
        }
    }

    private fun extractRequestId(envelopeJson: String): String {
        val requestId = parseRequestId(envelopeJson)
            ?: throw AoaTransportError.InvalidEnvelope("Envelope is missing request_id")
        return requestId
    }

    private fun extractRequestIdOrGenerate(envelopeJson: String): String {
        return parseRequestId(envelopeJson) ?: UUID.randomUUID().toString()
    }

    private fun parseRequestId(envelopeJson: String): String? {
        return try {
            val envelope = JSONObject(envelopeJson)
            if (envelope.has("request_id")) {
                envelope.optString("request_id")
            } else {
                null
            }
        } catch (e: Exception) {
            throw AoaTransportError.InvalidEnvelope("Envelope is not valid JSON")
        }
    }

    private fun padRequestId(requestId: String): String {
        return requestId.padEnd(AoaFrameCodec.REQUEST_ID_LENGTH, ' ')
    }

    private fun registerPendingResponse(requestId: String): BlockingQueue<ResponseResult> {
        val queue = LinkedBlockingQueue<ResponseResult>(1)
        pendingResponses[requestId] = queue
        return queue
    }

    private fun registerPendingStreamingResponse(requestId: String): BlockingQueue<ResponseResult> {
        val queue = LinkedBlockingQueue<ResponseResult>(1)
        pendingStreamingResponses[requestId] = queue
        return queue
    }

    private fun stopInternal() {
        if (stopped.getAndSet(true)) {
            return
        }
        closeConnection()
        try {
            context.unregisterReceiver(receiver)
        } catch (_: IllegalArgumentException) {
            // Receiver may already be unregistered.
        }
        permissionPendingIntent?.let {
            try {
                it.cancel()
            } catch (_: Exception) {
                // Ignore cancellation errors during cleanup.
            }
        }
        permissionPendingIntent = null
    }

    private fun clearBootstrapState() {
        preparedSessionId = null
        preparedOneTimePasscode = null
        preparedSuggestedPort = -1
        bootstrapPrepared = false
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
        val accessory = accessories.firstOrNull() ?: return
        requestAccessoryPermission(accessory)
    }

    private fun requestAccessoryPermission(accessory: UsbAccessory) {
        val intent = permissionPendingIntent ?: return
        if (usbManager.hasPermission(accessory)) {
            openAccessory(accessory)
            return
        }
        usbManager.requestPermission(accessory, intent)
    }

    @Synchronized
    private fun openAccessory(accessory: UsbAccessory) {
        closeConnection()
        val descriptor = try {
            usbManager.openAccessory(accessory)
        } catch (e: SecurityException) {
            Log.w(LOG_TAG, "openAccessory failed with security exception: ${e.message}")
            transitionTo(AoaTransportState.FAILED)
            return
        }
        if (descriptor == null) {
            Log.w(LOG_TAG, "openAccessory returned null.")
            return
        }
        openedDescriptor = descriptor
        transitionTo(AoaTransportState.AUTHENTICATING)
        startReaderWriter(
            ParcelFileDescriptor.AutoCloseInputStream(descriptor),
            ParcelFileDescriptor.AutoCloseOutputStream(descriptor),
        )
        Log.i(LOG_TAG, "Accessory stream opened; authenticating.")
    }

    @VisibleForTesting
    internal fun openStreamsForTest(
        inputStream: InputStream,
        outputStream: OutputStream,
    ) {
        synchronized(this) {
            closeConnection()
            openedDescriptor = null
            stopped.set(false)
            startReaderWriter(inputStream, outputStream)
            transitionTo(AoaTransportState.AUTHENTICATING)
        }
    }

    @Synchronized
    private fun startReaderWriter(inputStream: InputStream, outputStream: OutputStream) {
        currentInputStream = inputStream
        currentOutputStream = outputStream
        readerThread = Thread({ runReader(inputStream) }, "AoaClientReader").apply {
            isDaemon = true
            start()
        }
        writerThread = Thread({ runWriter(outputStream) }, "AoaClientWriter").apply {
            isDaemon = true
            start()
        }
    }

    @Synchronized
    private fun closeConnection() {
        readerThread?.interrupt()
        writerThread?.interrupt()
        readerThread = null
        writerThread = null
        try {
            currentInputStream?.close()
        } catch (_: IOException) {
            // Ignore close errors during cleanup.
        }
        currentInputStream = null
        try {
            currentOutputStream?.close()
        } catch (_: IOException) {
            // Ignore close errors during cleanup.
        }
        currentOutputStream = null
        try {
            openedDescriptor?.close()
        } catch (_: IOException) {
            // Ignore close errors during cleanup.
        }
        openedDescriptor = null
        outgoingQueue.clear()
        val connectionLostError = AoaTransportError.ConnectionLost("AOA connection lost")
        pendingResponses.values.forEach { queue ->
            queue.offer(ResponseResult.Error(connectionLostError))
        }
        pendingStreamingResponses.values.forEach { queue ->
            queue.offer(ResponseResult.Error(connectionLostError))
        }
        pendingResponses.clear()
        pendingStreamingResponses.clear()
        if (!stopped.get()) {
            transitionTo(AoaTransportState.DISCONNECTED)
        }
    }

    private fun runReader(inputStream: InputStream) {
        val buffer = ByteArray(READ_BUFFER_SIZE)
        val decoder = AoaFrameCodec.StreamDecoder()
        try {
            while (!stopped.get() && !Thread.currentThread().isInterrupted) {
                val readBytes = inputStream.read(buffer)
                if (readBytes < 0) {
                    break
                }
                if (readBytes == 0) {
                    continue
                }
                val frames = decoder.feed(buffer.copyOfRange(0, readBytes))
                for (frame in frames) {
                    handleFrame(frame)
                }
            }
        } catch (e: IOException) {
            Log.w(LOG_TAG, "Reader stopped with I/O error: ${e.message}")
        } finally {
            closeConnection()
        }
    }

    private fun handleFrame(frame: AoaFrame) {
        if (frame.flags == AoaFrameCodec.FRAME_FLAG_BINARY) {
            // Incoming binary asset chunks are not surfaced through the current public API.
            // They are intentionally ignored here; streaming is driven from the mobile side.
            return
        }
        val payload = try {
            String(frame.payload, Charsets.UTF_8)
        } catch (e: Exception) {
            Log.w(LOG_TAG, "Ignored non-UTF8 AOA text frame.")
            return
        }
        val envelope = try {
            JSONObject(payload)
        } catch (e: Exception) {
            Log.w(LOG_TAG, "Ignored malformed AOA JSON envelope.")
            return
        }
        val operation = envelope.optString("operation")
        if (operation == AoaAuthResponder.AUTH_OPERATION) {
            handleAuthChallenge(frame.requestId, envelope)
        } else {
            handleResponse(payload, envelope)
        }
    }

    private fun handleAuthChallenge(frameRequestId: String, envelope: JSONObject) {
        val sessionId = preparedSessionId
        val oneTimePasscode = preparedOneTimePasscode
        if (sessionId == null || oneTimePasscode == null) {
            Log.w(LOG_TAG, "Received auth challenge before bootstrap was prepared.")
            return
        }
        val body = try {
            envelope.getJSONObject("body")
        } catch (e: Exception) {
            Log.w(LOG_TAG, "Auth challenge envelope missing body.")
            return
        }
        val input = AuthChallengeInput(
            frameRequestId = frameRequestId,
            envelopeSchema = envelope.optString("schema"),
            operation = envelope.optString("operation"),
            bodySchema = envelope.optString("body_schema"),
            sid = body.optString("sid"),
            rand = body.optString("rand"),
        )
        val response = try {
            authResponder.respond(
                input = input,
                expectedSessionId = sessionId,
                oneTimePasscode = oneTimePasscode,
            )
        } catch (e: AoaTransportError) {
            Log.w(LOG_TAG, "Auth challenge rejected: ${e.message}")
            transitionTo(AoaTransportState.FAILED, e.message)
            return
        }
        val responseFrame = AoaFrameCodec.encodeFrame(
            response.responseFrameRequestId,
            response.responseEnvelopeJson.toByteArray(Charsets.UTF_8),
            AoaFrameCodec.FRAME_FLAG_TEXT,
        )
        outgoingQueue.put(responseFrame)
        transitionTo(AoaTransportState.CONNECTED)
    }

    private fun handleResponse(payload: String, envelope: JSONObject) {
        if (!envelope.has("request_id")) {
            return
        }
        val requestId = envelope.optString("request_id")
        val queue = pendingResponses[requestId] ?: pendingStreamingResponses[requestId]
        if (queue != null) {
            queue.offer(ResponseResult.Success(payload))
        } else {
            Log.w(LOG_TAG, "Received response for unknown request_id: $requestId")
        }
    }

    private fun runWriter(outputStream: OutputStream) {
        try {
            while (!stopped.get() && !Thread.currentThread().isInterrupted) {
                val frame = outgoingQueue.take()
                outputStream.write(frame)
                outputStream.flush()
            }
        } catch (e: IOException) {
            Log.w(LOG_TAG, "Writer stopped with I/O error: ${e.message}")
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
        } finally {
            closeConnection()
        }
    }

    private fun transitionTo(newState: AoaTransportState, errorMessage: String? = null) {
        val previous = state.getAndSet(newState)
        if (previous != newState) {
            Log.d(LOG_TAG, "State $previous -> $newState")
            notifyStateListeners(newState, errorMessage)
        }
    }

    private fun notifyStateListeners(newState: AoaTransportState, errorMessage: String?) {
        val snapshot = synchronized(listeners) { listeners.toList() }
        snapshot.forEach { listener ->
            try {
                listener.onStateChanged(newState, errorMessage)
            } catch (e: Exception) {
                Log.w(LOG_TAG, "State listener threw: ${e.message}")
            }
        }
    }

    private fun extractAccessory(intent: Intent): UsbAccessory? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(UsbManager.EXTRA_ACCESSORY, UsbAccessory::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(UsbManager.EXTRA_ACCESSORY)
        }
    }

    private fun currentAccessory(): UsbAccessory? {
        val accessories = usbManager.accessoryList ?: return null
        return accessories.firstOrNull()
    }

    private fun isSameAccessory(first: UsbAccessory?, second: UsbAccessory?): Boolean {
        if (first == null || second == null) {
            return false
        }
        return first.manufacturer == second.manufacturer
            && first.model == second.model
            && first.version == second.version
    }

    companion object {
        private const val LOG_TAG = "AoaClient"
        private const val READ_BUFFER_SIZE = 16 * 1024
        private const val RESPONSE_TIMEOUT_MS = 10_000L
        private const val ACTION_USB_PERMISSION = "com.ausearch.aubackup.USB_ACCESSORY_PERMISSION"

        @Volatile
        private var instance: AoaClient? = null

        /**
         * Returns the production singleton for the AOA transport client.
         */
        @JvmStatic
        fun getInstance(context: Context): AoaClient {
            return instance ?: synchronized(this) {
                instance ?: AoaClient(context.applicationContext).also { instance = it }
            }
        }

        /**
         * Resets the production singleton. Intended for tests.
         */
        @VisibleForTesting
        @JvmStatic
        fun resetInstance() {
            instance?.reset()
            instance = null
        }

        /**
         * Creates a fresh client instance for tests. The caller owns its lifecycle.
         */
        @VisibleForTesting
        @JvmStatic
        fun createForTest(context: Context): AoaClient = AoaClient(context)
    }
}
