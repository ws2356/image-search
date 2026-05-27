package com.ausearch.aubackup.transfer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import androidx.core.content.ContextCompat
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.modules.core.DeviceEventManagerModule

class BackupTransferServiceModule(
  private val reactApplicationContext: ReactApplicationContext
) : ReactContextBaseJavaModule(reactApplicationContext) {
  private var listenerCount = 0
  private var receiverRegistered = false

  private val stateChangedReceiver = object : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
      emitStateChanged(
        stateJson = intent?.getStringExtra(BackupTransferForegroundService.EXTRA_STATE_JSON),
        snapshotJson = intent?.getStringExtra(BackupTransferForegroundService.EXTRA_SNAPSHOT_JSON)
      )
    }
  }

  override fun getName(): String = "BackupTransferServiceModule"

  @ReactMethod
  fun startHeadlessTransferSession(taskPayloadJson: String, promise: Promise) {
    BackupTransferForegroundService.start(reactApplicationContext, taskPayloadJson)
    promise.resolve(null)
  }

  @ReactMethod
  fun requestStopTransferSession(promise: Promise) {
    BackupTransferForegroundService.requestStop(reactApplicationContext)
    promise.resolve(null)
  }

  @ReactMethod
  fun publishProgress(snapshotJson: String, promise: Promise) {
    BackupTransferForegroundService.publishProgress(reactApplicationContext, snapshotJson)
    promise.resolve(null)
  }

  @ReactMethod
  fun publishState(stateJson: String, promise: Promise) {
    BackupTransferForegroundService.publishState(reactApplicationContext, stateJson)
    promise.resolve(null)
  }

  @ReactMethod
  fun getCurrentState(promise: Promise) {
    val (stateJson, snapshotJson) = BackupTransferForegroundService.getCurrentPayload()
    val payload = Arguments.createMap().apply {
      if (stateJson != null) {
        putString("stateJson", stateJson)
      } else {
        putNull("stateJson")
      }
      if (snapshotJson != null) {
        putString("snapshotJson", snapshotJson)
      } else {
        putNull("snapshotJson")
      }
    }
    promise.resolve(payload)
  }

  @ReactMethod
  fun clearStopRequested(promise: Promise) {
    BackupTransferForegroundService.clearStopRequested()
    promise.resolve(null)
  }

  @ReactMethod
  fun clearState(promise: Promise) {
    BackupTransferForegroundService.clearState()
    promise.resolve(null)
  }

  @ReactMethod(isBlockingSynchronousMethod = true)
  fun isStopRequested(): Boolean {
    return BackupTransferForegroundService.isStopRequested()
  }

  @ReactMethod
  fun addListener(eventName: String) {
    if (eventName != TRANSFER_SERVICE_STATE_EVENT) {
      return
    }
    listenerCount += 1
    registerReceiverIfNeeded()
  }

  @ReactMethod
  fun removeListeners(count: Int) {
    listenerCount = (listenerCount - count).coerceAtLeast(0)
    if (listenerCount == 0) {
      unregisterReceiverIfNeeded()
    }
  }

  override fun invalidate() {
    unregisterReceiverIfNeeded()
    super.invalidate()
  }

  private fun registerReceiverIfNeeded() {
    if (receiverRegistered) {
      return
    }
    ContextCompat.registerReceiver(
      reactApplicationContext,
      stateChangedReceiver,
      IntentFilter(BackupTransferForegroundService.ACTION_STATE_CHANGED),
      ContextCompat.RECEIVER_NOT_EXPORTED
    )
    receiverRegistered = true
  }

  private fun unregisterReceiverIfNeeded() {
    if (!receiverRegistered) {
      return
    }
    reactApplicationContext.unregisterReceiver(stateChangedReceiver)
    receiverRegistered = false
  }

  private fun emitStateChanged(stateJson: String?, snapshotJson: String?) {
    val payload = Arguments.createMap().apply {
      if (stateJson != null) {
        putString("stateJson", stateJson)
      } else {
        putNull("stateJson")
      }
      if (snapshotJson != null) {
        putString("snapshotJson", snapshotJson)
      } else {
        putNull("snapshotJson")
      }
    }
    reactApplicationContext
      .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
      .emit(TRANSFER_SERVICE_STATE_EVENT, payload)
  }

  companion object {
    const val TRANSFER_SERVICE_STATE_EVENT = "BackupTransferServiceStateChanged"
  }
}
