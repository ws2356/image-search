package com.ausearch.aubackup.usb.poc

import java.nio.ByteBuffer
import java.nio.charset.StandardCharsets

enum class AoaPocState {
  IDLE,
  ACCESSORY_NEGOTIATING,
  ACCESSORY_READY,
  STREAMING,
  DISCONNECTED,
  FAILED,
}

/**
 * Phase-0 Android USB AOA POC helper.
 * This class is intentionally isolated from production transfer flows.
 */
class AoaPocAccessoryService {
  @Volatile
  var state: AoaPocState = AoaPocState.IDLE
    private set

  fun onAccessoryNegotiating() {
    state = AoaPocState.ACCESSORY_NEGOTIATING
  }

  fun onAccessoryReady() {
    state = AoaPocState.ACCESSORY_READY
  }

  fun onStreamingStarted() {
    state = AoaPocState.STREAMING
  }

  fun onDisconnect() {
    state = AoaPocState.DISCONNECTED
  }

  fun onFailure() {
    state = AoaPocState.FAILED
  }

  fun encodeFrame(requestId: String, payload: ByteArray): ByteArray {
    require(requestId.toByteArray(StandardCharsets.US_ASCII).size == REQUEST_ID_BYTES) {
      "requestId must be exactly $REQUEST_ID_BYTES ASCII bytes."
    }
    val requestBytes = requestId.toByteArray(StandardCharsets.US_ASCII)
    val header = ByteBuffer.allocate(HEADER_BYTES)
    header.put(FRAME_VERSION)
    header.put(requestBytes)
    header.putInt(payload.size)
    return header.array() + payload
  }

  fun decodeFrame(frame: ByteArray): Pair<String, ByteArray> {
    require(frame.size >= HEADER_BYTES) { "frame header is incomplete." }
    val buffer = ByteBuffer.wrap(frame)
    val version = buffer.get()
    require(version == FRAME_VERSION) { "frame version is unsupported." }
    val requestBytes = ByteArray(REQUEST_ID_BYTES)
    buffer.get(requestBytes)
    val requestId = String(requestBytes, StandardCharsets.US_ASCII).trim()
    require(requestId.isNotEmpty()) { "requestId is missing." }
    val declaredLength = buffer.int
    val payload = ByteArray(frame.size - HEADER_BYTES)
    buffer.get(payload)
    require(payload.size == declaredLength) { "payload length mismatch." }
    return requestId to payload
  }

  companion object {
    const val FRAME_VERSION: Byte = 1
    const val REQUEST_ID_BYTES: Int = 36
    const val HEADER_BYTES: Int = 1 + REQUEST_ID_BYTES + 4
  }
}

