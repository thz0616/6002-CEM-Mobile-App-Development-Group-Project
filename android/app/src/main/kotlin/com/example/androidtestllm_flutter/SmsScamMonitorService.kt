package com.example.androidtestllm_flutter

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.provider.Telephony
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject

class SmsScamMonitorService : Service() {
    private val workerThread = HandlerThread("SmsScamMonitor")
    private lateinit var workerHandler: Handler
    private var observer: ContentObserver? = null
    private var started = false

    override fun onCreate() {
        super.onCreate()
        workerThread.start()
        workerHandler = Handler(workerThread.looper)
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopMonitoring()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
        }

        if (!hasSmsPermission()) {
            stopMonitoring()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        startForeground(NOTIFICATION_ID, buildNotification())
        startMonitoring()
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopMonitoring()
        try {
            workerThread.quitSafely()
        } catch (_: Throwable) {
        }
        super.onDestroy()
    }

    private fun startMonitoring() {
        if (started) return

        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (prefs.getLong(KEY_LAST_SEEN_ID, -1L) < 0L) {
            prefs.edit().putLong(KEY_LAST_SEEN_ID, queryLatestSmsId()).apply()
        }

        observer = object : ContentObserver(workerHandler) {
            override fun onChange(selfChange: Boolean) {
                scanInbox()
            }

            override fun onChange(selfChange: Boolean, uri: Uri?) {
                scanInbox()
            }
        }

        contentResolver.registerContentObserver(
            Telephony.Sms.Inbox.CONTENT_URI,
            true,
            observer as ContentObserver
        )
        started = true
        scanInbox()
    }

    private fun buildNotification() = run {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("SMS scam detection active")
            .setContentText("Monitoring incoming SMS messages")
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun stopMonitoring() {
        if (!started) return

        observer?.let {
            try {
                contentResolver.unregisterContentObserver(it)
            } catch (_: Throwable) {
            }
        }
        observer = null
        started = false
    }

    private fun scanInbox() {
        if (!hasSmsPermission()) return

        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(KEY_ENABLED, false)) return

        val lastSeenId = prefs.getLong(KEY_LAST_SEEN_ID, 0L)
        val selection = if (lastSeenId > 0L) "${Telephony.Sms._ID} > ?" else null
        val selectionArgs = if (lastSeenId > 0L) arrayOf(lastSeenId.toString()) else null
        val sortOrder = "${Telephony.Sms._ID} ASC"

        contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            arrayOf(
                Telephony.Sms._ID,
                Telephony.Sms.ADDRESS,
                Telephony.Sms.BODY,
                Telephony.Sms.DATE,
            ),
            selection,
            selectionArgs,
            sortOrder
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val smsId = cursor.getLongOrNull(Telephony.Sms._ID)
                val sender = cursor.getStringOrEmpty(Telephony.Sms.ADDRESS)
                val body = cursor.getStringOrEmpty(Telephony.Sms.BODY)
                val detectedAt = cursor.getLongOrDefault(Telephony.Sms.DATE, System.currentTimeMillis())
                if (smsId <= lastSeenId || body.isBlank()) continue
                processMessage(prefs, sender, body, detectedAt)
                prefs.edit().putLong(KEY_LAST_SEEN_ID, smsId).apply()
            }
        }
    }

    private fun processMessage(
        prefs: android.content.SharedPreferences,
        sender: String,
        body: String,
        detectedAt: Long
    ) {
        val probability = estimateScamProbability(body)
        val isScam = probability >= SCAM_THRESHOLD
        saveRecord(prefs, sender, body, probability, isScam, detectedAt)
        if (isScam) {
            prefs.edit().putBoolean(KEY_OPEN_REQUEST, true).apply()
            showScamNotification(sender, probability)
        }
    }

    private fun saveRecord(
        prefs: android.content.SharedPreferences,
        sender: String,
        body: String,
        probability: Double,
        isScam: Boolean,
        detectedAt: Long
    ) {
        val records = JSONArray(prefs.getString(KEY_RECORDS, "[]") ?: "[]")
        val next = JSONArray()
        next.put(
            JSONObject()
                .put("sender", sender)
                .put("body", body)
                .put("probability", probability)
                .put("isScam", isScam)
                .put("detectedAt", detectedAt)
        )

        val limit = minOf(records.length(), MAX_RECORDS - 1)
        for (i in 0 until limit) {
            next.put(records.getJSONObject(i))
        }

        prefs.edit().putString(KEY_RECORDS, next.toString()).apply()
    }

    private fun showScamNotification(sender: String, probability: Double) {
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val text = "From ${sender.ifBlank { "unknown sender" }} - ${(probability * 100).toInt()}% scam probability"
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Suspicious SMS detected")
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()

        manager.notify(NOTIFICATION_ID, notification)
    }

    private fun estimateScamProbability(body: String): Double {
        val text = body.lowercase()
        var score = 0.08

        val highRiskTerms = listOf(
            "otp",
            "password",
            "bank",
            "account suspended",
            "verify",
            "verification",
            "click",
            "link",
            "prize",
            "won",
            "urgent",
            "limited time",
            "transfer",
            "refund",
            "tac",
            "pin"
        )
        for (term in highRiskTerms) {
            if (text.contains(term)) score += 0.08
        }
        if (Regex("""https?://|www\.|bit\.ly|tinyurl|t\.co""").containsMatchIn(text)) {
            score += 0.28
        }
        if (Regex("""\b\d{4,8}\b""").containsMatchIn(text) && text.contains("otp")) {
            score += 0.18
        }
        if (text.contains("rm") && (text.contains("claim") || text.contains("refund"))) {
            score += 0.18
        }

        return score.coerceIn(0.0, 0.98)
    }

    private fun hasSmsPermission(): Boolean {
        return ContextCompat.checkSelfPermission(this, Manifest.permission.READ_SMS) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "SMS Scam Monitor",
            NotificationManager.IMPORTANCE_LOW
        )
        manager.createNotificationChannel(channel)
    }

    private fun queryLatestSmsId(): Long {
        val cursor = contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            arrayOf(Telephony.Sms._ID),
            null,
            null,
            "${Telephony.Sms._ID} DESC"
        )
        cursor?.use {
            if (it.moveToFirst()) {
                return it.getLongOrDefault(Telephony.Sms._ID, 0L)
            }
        }
        return 0L
    }

    private fun Cursor.getStringOrEmpty(column: String): String {
        val index = getColumnIndex(column)
        return if (index >= 0 && !isNull(index)) getString(index).orEmpty() else ""
    }

    private fun Cursor.getLongOrDefault(column: String, defaultValue: Long): Long {
        val index = getColumnIndex(column)
        return if (index >= 0 && !isNull(index)) getLong(index) else defaultValue
    }

    private fun Cursor.getLongOrNull(column: String): Long {
        return getLongOrDefault(column, 0L)
    }

    companion object {
        private const val ACTION_START = "action_start"
        private const val ACTION_STOP = "action_stop"
        private const val PREFS = "prefs"
        private const val KEY_ENABLED = "sms_scam_detection_enabled"
        private const val KEY_RECORDS = "sms_scam_records"
        private const val KEY_OPEN_REQUEST = "sms_scam_open_request"
        private const val KEY_LAST_SEEN_ID = "sms_scam_last_seen_id"
        private const val CHANNEL_ID = "sms_scam_monitor"
        private const val NOTIFICATION_ID = 24018
        private const val MAX_RECORDS = 80
        private const val SCAM_THRESHOLD = 0.65
    }
}
