package com.ausearch.aubackup.transfer

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.ausearch.aubackup.MainActivity
import com.ausearch.aubackup.R
import com.facebook.react.HeadlessJsTaskService
import com.facebook.react.bridge.Arguments
import com.facebook.react.jstasks.HeadlessJsTaskConfig
import org.json.JSONException
import org.json.JSONObject

class BackupTransferForegroundService : HeadlessJsTaskService() {
  override fun onCreate() {
    super.onCreate()
    applicationContextRef = applicationContext
    serviceInstance = this
    ensureNotificationChannel()
  }

  override fun onDestroy() {
    serviceInstance = null
    super.onDestroy()
  }

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    applicationContextRef = applicationContext
    when (intent?.action) {
      ACTION_REQUEST_STOP -> {
        stopRequested = true
        updateProgressNotification(latestSnapshotJson, "Stopping backup…")
        return START_NOT_STICKY
      }
      ACTION_START -> {
        stopRequested = false
        latestSnapshotJson = null
        latestStateJson = buildStateJson(status = "running", errorMessage = null)
        lastProgressEmissionElapsedMs = 0L
        broadcastStateChanged()
        startForeground(NOTIFICATION_ID, buildNotification(snapshotJson = null, statusText = "Preparing backup…"))
      }
    }
    return super.onStartCommand(intent, flags, startId)
  }

  override fun getTaskConfig(intent: Intent?): HeadlessJsTaskConfig? {
    if (intent?.action != ACTION_START) {
      return null
    }
    val taskPayloadJson = intent.getStringExtra(EXTRA_TASK_PAYLOAD_JSON) ?: return null
    val taskData = Bundle().apply {
      putString(EXTRA_TASK_PAYLOAD_JSON, taskPayloadJson)
    }
    return HeadlessJsTaskConfig(
      HEADLESS_TASK_KEY,
      Arguments.fromBundle(taskData),
      0,
      true
    )
  }

  override fun onTaskRemoved(rootIntent: Intent?) {
    stopRequested = true
    latestStateJson = buildStateJson(status = "stopped", errorMessage = null)
    broadcastStateChanged()
    removeNotificationAndStop()
    super.onTaskRemoved(rootIntent)
  }

  fun updateProgressNotification(snapshotJson: String?, statusText: String? = null) {
    val notificationManager = getSystemService(NotificationManager::class.java)
    notificationManager.notify(NOTIFICATION_ID, buildNotification(snapshotJson, statusText))
  }

  fun finishAndStop() {
    removeNotificationAndStop()
  }

  fun showTerminalNotificationAndStop(stateJson: String, snapshotJson: String?) {
    val notificationManager = getSystemService(NotificationManager::class.java)
    notificationManager.notify(NOTIFICATION_ID, buildTerminalNotification(stateJson, snapshotJson))
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
      stopForeground(STOP_FOREGROUND_DETACH)
    } else {
      @Suppress("DEPRECATION")
      stopForeground(false)
    }
    stopSelf()
  }

  private fun ensureNotificationChannel() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
      return
    }
    val notificationManager = getSystemService(NotificationManager::class.java)
    val channel = NotificationChannel(
      NOTIFICATION_CHANNEL_ID,
      "Backup transfer",
      NotificationManager.IMPORTANCE_LOW
    ).apply {
      description = "Shows progress while AuBackup transfers items in the background."
      setShowBadge(false)
    }
    notificationManager.createNotificationChannel(channel)
  }

  private fun buildNotification(snapshotJson: String?, statusText: String?): Notification {
    val launchIntent = Intent(this, MainActivity::class.java).apply {
      addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
    }
    val contentIntent = PendingIntent.getActivity(
      this,
      0,
      launchIntent,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    val snapshot = snapshotJson?.let(::parseSnapshot)
    val title = statusText
      ?: snapshot?.let {
        val transferredCount = it.optJSONObject("counts")?.optInt("transferredAssets", 0) ?: 0
        val totalCount = it.optJSONObject("counts")?.optInt("totalAssets", 0) ?: 0
        "Backing up $transferredCount / $totalCount items"
      }
      ?: "Backing up in background"
    val text = snapshot?.let {
      val counts = it.optJSONObject("counts")
      val matchedCount = counts?.optInt("matchedAssets", 0) ?: 0
      val failedCount = counts?.optInt("failedAssets", 0) ?: 0
      val speedMbPerSecond = (it.optDouble("bytesPerSecond", 0.0) / (1024.0 * 1024.0))
      "Skipped $matchedCount • Failed $failedCount • ${"%.2f".format(speedMbPerSecond)} MB/s"
    } ?: "AuBackup keeps the current transfer alive while the app is backgrounded."

    val builder = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
      .setContentTitle(title)
      .setContentText(text)
      .setSmallIcon(R.mipmap.ic_launcher)
      .setOngoing(true)
      .setOnlyAlertOnce(true)
      .setCategory(NotificationCompat.CATEGORY_PROGRESS)
      .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
      .setContentIntent(contentIntent)

    if (snapshot != null) {
      val counts = snapshot.optJSONObject("counts")
      val totalCount = counts?.optInt("totalAssets", 0) ?: 0
      val transferredCount = counts?.optInt("transferredAssets", 0) ?: 0
      if (totalCount > 0) {
        builder.setProgress(totalCount, transferredCount.coerceAtMost(totalCount), false)
      }
    }

    return builder.build()
  }

  private fun removeNotificationAndStop() {
    val notificationManager = getSystemService(NotificationManager::class.java)
    notificationManager.cancel(NOTIFICATION_ID)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
      stopForeground(STOP_FOREGROUND_REMOVE)
    } else {
      @Suppress("DEPRECATION")
      stopForeground(true)
    }
    stopSelf()
  }

  private fun buildTerminalNotification(stateJson: String, snapshotJson: String?): Notification {
    val launchIntent = Intent(this, MainActivity::class.java).apply {
      addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
    }
    val contentIntent = PendingIntent.getActivity(
      this,
      0,
      launchIntent,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )
    val status = parseStatus(stateJson)
    val errorMessage = parseErrorMessage(stateJson)
    val snapshot = snapshotJson?.let(::parseSnapshot)
    val counts = snapshot?.optJSONObject("counts")
    val transferredCount = counts?.optInt("transferredAssets", 0) ?: 0
    val matchedCount = counts?.optInt("matchedAssets", 0) ?: 0
    val failedCount = counts?.optInt("failedAssets", 0) ?: 0

    val title = when (status) {
      "completed" -> "Backup completed"
      "failed" -> "Backup failed"
      else -> "Backup stopped"
    }
    val text = when (status) {
      "completed" -> "Transferred $transferredCount • Skipped $matchedCount • Failed $failedCount"
      "failed" -> errorMessage ?: "The background backup session ended with an error."
      else -> "The backup session was stopped."
    }

    return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
      .setContentTitle(title)
      .setContentText(text)
      .setSmallIcon(R.mipmap.ic_launcher)
      .setOngoing(false)
      .setAutoCancel(true)
      .setOnlyAlertOnce(true)
      .setContentIntent(contentIntent)
      .build()
  }

  companion object {
    const val ACTION_START = "com.ausearch.aubackup.transfer.action.START"
    const val ACTION_REQUEST_STOP = "com.ausearch.aubackup.transfer.action.REQUEST_STOP"
    const val ACTION_STATE_CHANGED = "com.ausearch.aubackup.transfer.action.STATE_CHANGED"
    const val EXTRA_TASK_PAYLOAD_JSON = "taskPayloadJson"
    const val EXTRA_SNAPSHOT_JSON = "snapshotJson"
    const val EXTRA_STATE_JSON = "stateJson"
    const val HEADLESS_TASK_KEY = "AuBackupTransferTask"

    private const val NOTIFICATION_CHANNEL_ID = "aubackup.transfer"
    private const val NOTIFICATION_ID = 1001
    private const val PROGRESS_NOTIFICATION_INTERVAL_MS = 1000L

    @Volatile
    private var latestSnapshotJson: String? = null

    @Volatile
    private var latestStateJson: String? = null

    @Volatile
    private var stopRequested = false

    @Volatile
    private var serviceInstance: BackupTransferForegroundService? = null

    @Volatile
    private var applicationContextRef: Context? = null

    @Volatile
    private var lastProgressEmissionElapsedMs = 0L

    fun start(context: Context, taskPayloadJson: String) {
      applicationContextRef = context.applicationContext
      val intent = Intent(context, BackupTransferForegroundService::class.java).apply {
        action = ACTION_START
        putExtra(EXTRA_TASK_PAYLOAD_JSON, taskPayloadJson)
      }
      ContextCompat.startForegroundService(context, intent)
    }

    fun requestStop(context: Context) {
      stopRequested = true
      applicationContextRef = context.applicationContext
      val intent = Intent(context, BackupTransferForegroundService::class.java).apply {
        action = ACTION_REQUEST_STOP
      }
      context.startService(intent)
    }

    fun publishProgress(context: Context, snapshotJson: String) {
      applicationContextRef = context.applicationContext
      latestSnapshotJson = snapshotJson
      if (latestStateJson == null || parseStatus(latestStateJson) == "idle") {
        latestStateJson = buildStateJson(status = "running", errorMessage = null)
      }
      val elapsedMs = SystemClock.elapsedRealtime() - lastProgressEmissionElapsedMs
      if (elapsedMs >= PROGRESS_NOTIFICATION_INTERVAL_MS) {
        lastProgressEmissionElapsedMs = SystemClock.elapsedRealtime()
        broadcastStateChanged()
        serviceInstance?.updateProgressNotification(snapshotJson)
      }
    }

    fun publishState(context: Context, stateJson: String) {
      applicationContextRef = context.applicationContext
      latestStateJson = stateJson
      broadcastStateChanged()
      when (parseStatus(stateJson)) {
        "completed", "failed" -> serviceInstance?.showTerminalNotificationAndStop(stateJson, latestSnapshotJson)
        "stopped" -> serviceInstance?.finishAndStop()
        "running" -> serviceInstance?.updateProgressNotification(latestSnapshotJson)
      }
    }

    fun getCurrentPayload(): Pair<String?, String?> {
      return Pair(latestStateJson, latestSnapshotJson)
    }

    fun clearStopRequested() {
      stopRequested = false
    }

    fun clearState() {
      latestStateJson = null
      latestSnapshotJson = null
      stopRequested = false
      lastProgressEmissionElapsedMs = 0L
    }

    fun isStopRequested(): Boolean {
      return stopRequested
    }

    private fun broadcastStateChanged() {
      val context = applicationContextRef ?: return
      val intent = Intent(ACTION_STATE_CHANGED).apply {
        setPackage(context.packageName)
        putExtra(EXTRA_STATE_JSON, latestStateJson)
        putExtra(EXTRA_SNAPSHOT_JSON, latestSnapshotJson)
      }
      context.sendBroadcast(intent)
    }

    private fun buildStateJson(status: String, errorMessage: String?): String {
      return JSONObject()
        .put("status", status)
        .put("errorMessage", errorMessage)
        .toString()
    }

    private fun parseStatus(stateJson: String?): String {
      if (stateJson == null) {
        return "idle"
      }
      return try {
        JSONObject(stateJson).optString("status", "idle")
      } catch (_: JSONException) {
        "idle"
      }
    }

    private fun parseErrorMessage(stateJson: String?): String? {
      if (stateJson == null) {
        return null
      }
      return try {
        JSONObject(stateJson).opt("errorMessage") as? String
      } catch (_: JSONException) {
        null
      }
    }

    private fun parseSnapshot(snapshotJson: String): JSONObject? {
      return try {
        JSONObject(snapshotJson)
      } catch (_: JSONException) {
        null
      }
    }
  }
}
