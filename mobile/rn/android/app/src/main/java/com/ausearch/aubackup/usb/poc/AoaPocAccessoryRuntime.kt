package com.ausearch.aubackup.usb.poc

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
import java.io.IOException

/**
 * Phase-0 runtime that keeps a USB accessory read loop alive so host-side AOA
 * throughput probes have an active Android consumer.
 */
object AoaPocAccessoryRuntime {
  private const val LOG_TAG = "AoaPocRuntime"
  private const val ACTION_USB_PERMISSION = "com.ausearch.aubackup.USB_ACCESSORY_PERMISSION"

  @Volatile
  private var initialized = false
  private var appContext: Context? = null
  private var usbManager: UsbManager? = null
  private var openedAccessoryDescriptor: ParcelFileDescriptor? = null
  private var readerThread: Thread? = null

  private val receiver = object : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
      val action = intent.action ?: return
      when (action) {
        UsbManager.ACTION_USB_ACCESSORY_ATTACHED -> {
          val attachedAccessory = extractAccessory(intent)
          if (attachedAccessory != null) {
            requestAccessoryPermission(attachedAccessory)
          } else {
            probeAttachedAccessoriesAndRequestPermission()
          }
        }
        UsbManager.ACTION_USB_ACCESSORY_DETACHED -> {
          val detachedAccessory = extractAccessory(intent)
          if (detachedAccessory == null || isSameAccessory(detachedAccessory, currentAccessory())) {
            closeAccessoryConnection()
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

  @Synchronized
  fun start(context: Context) {
    if (initialized) {
      return
    }
    appContext = context.applicationContext
    usbManager = appContext?.getSystemService(Context.USB_SERVICE) as? UsbManager
    registerReceiver()
    initialized = true
    probeAttachedAccessoriesAndRequestPermission()
    Log.i(LOG_TAG, "AOA runtime initialized.")
  }

  @Synchronized
  fun stop() {
    if (!initialized) {
      return
    }
    val context = appContext
    if (context != null) {
      try {
        context.unregisterReceiver(receiver)
      } catch (_: IllegalArgumentException) {
        // Receiver may already be unregistered by the runtime.
      }
    }
    closeAccessoryConnection()
    initialized = false
    appContext = null
    usbManager = null
  }

  private fun registerReceiver() {
    val context = appContext ?: return
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

  private fun probeAttachedAccessoriesAndRequestPermission() {
    val manager = usbManager ?: return
    val accessories = manager.accessoryList ?: return
    val accessory = accessories.firstOrNull() ?: return
    requestAccessoryPermission(accessory)
  }

  private fun requestAccessoryPermission(accessory: UsbAccessory) {
    val manager = usbManager ?: return
    if (manager.hasPermission(accessory)) {
      openAccessory(accessory)
      return
    }
    val context = appContext ?: return
    val permissionIntent = PendingIntent.getBroadcast(
      context,
      0,
      Intent(ACTION_USB_PERMISSION),
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
    )
    manager.requestPermission(accessory, permissionIntent)
  }

  @Synchronized
  private fun openAccessory(accessory: UsbAccessory) {
    val manager = usbManager ?: return
    closeAccessoryConnection()
    val descriptor = manager.openAccessory(accessory)
    if (descriptor == null) {
      Log.w(LOG_TAG, "openAccessory returned null.")
      return
    }
    openedAccessoryDescriptor = descriptor
    readerThread = Thread({
      runReadLoop(descriptor)
    }, "AoaPocAccessoryReader").also {
      it.isDaemon = true
      it.start()
    }
    Log.i(LOG_TAG, "Accessory read loop started.")
  }

  private fun runReadLoop(descriptor: ParcelFileDescriptor) {
    val buffer = ByteArray(16 * 1024)
    try {
      FileInputStream(descriptor.fileDescriptor).use { input ->
        while (!Thread.currentThread().isInterrupted) {
          val readBytes = input.read(buffer)
          if (readBytes < 0) {
            break
          }
        }
      }
    } catch (error: IOException) {
      Log.w(LOG_TAG, "Accessory read loop stopped with I/O error: ${error.message}")
    } finally {
      closeAccessoryConnection()
    }
  }

  @Synchronized
  private fun closeAccessoryConnection() {
    readerThread?.interrupt()
    readerThread = null
    openedAccessoryDescriptor?.closeQuietly()
    openedAccessoryDescriptor = null
  }

  private fun extractAccessory(intent: Intent): UsbAccessory? {
    @Suppress("DEPRECATION")
    return intent.getParcelableExtra(UsbManager.EXTRA_ACCESSORY)
  }

  private fun currentAccessory(): UsbAccessory? {
    val manager = usbManager ?: return null
    val accessories = manager.accessoryList ?: return null
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
}

private fun ParcelFileDescriptor.closeQuietly() {
  try {
    this.close()
  } catch (_: IOException) {
    // Ignore close errors in POC runtime cleanup.
  }
}

