package com.ausearch.aubackup.transport.aoa

import android.util.Log
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.ReadableArray
import com.facebook.react.modules.core.DeviceEventManagerModule
import java.util.concurrent.Executors

/**
 * React Native bridge for the AOA transport client.
 *
 * Exposes the production [AoaClient] singleton to JavaScript so the same native
 * instance survives React Native reloads and is shared between the application
 * and the module. Blocking request methods are executed on a background thread
 * so the JS/UI thread is never blocked.
 */
class AoaTransportModule(
    private val reactContext: ReactApplicationContext,
    private val aoaClient: AoaClient = AoaClient.getInstance(reactContext.applicationContext),
) : ReactContextBaseJavaModule(reactContext) {

    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "AoaTransportModule-Worker").apply { isDaemon = true }
    }

    init {
        aoaClient.addListener(object : AoaClientListener {
            override fun onStateChanged(state: AoaTransportState, errorMessage: String?) {
                emitStateChanged(state.name.lowercase(), errorMessage)
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
        try {
            aoaClient.reset()
            promise.resolve(null)
        } catch (e: Throwable) {
            promise.reject("AOA_RESET_FAILED", e.message, e)
        }
    }

    @ReactMethod(isBlockingSynchronousMethod = true)
    fun isConnected(): Boolean = aoaClient.isConnected()

    @ReactMethod
    fun sendRequest(envelopeJson: String, promise: Promise) {
        executor.execute {
            try {
                val response = aoaClient.sendRequest(envelopeJson)
                promise.resolve(response)
            } catch (e: Throwable) {
                promise.reject("AOA_SEND_REQUEST_FAILED", e.message, e)
            }
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
        executor.execute {
            try {
                val response = aoaClient.finishStreamingRequest(requestId)
                promise.resolve(response)
            } catch (e: Throwable) {
                promise.reject("AOA_FINISH_STREAM_FAILED", e.message, e)
            }
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
        if (!reactContext.hasActiveReactInstance()) {
            return
        }
        try {
            val params = Arguments.createMap().apply {
                putString("state", state)
                if (errorMessage != null) putString("errorMessage", errorMessage) else putNull("errorMessage")
            }
            reactContext
                .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
                .emit("AoaTransportStateChanged", params)
        } catch (e: Exception) {
            Log.w(LOG_TAG, "Failed to emit AOA transport state change: ${e.message}")
        }
    }

    companion object {
        private const val LOG_TAG = "AoaTransportModule"
    }
}
