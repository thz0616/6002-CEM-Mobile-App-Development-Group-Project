package com.example.androidtestllm_flutter

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.example.app/horn_control"
    private val EVENT_CHANNEL = "com.example.app/horn_events"
    private val SMS_METHOD_CHANNEL = "com.example.app/sms_scam_control"
    private val SCREEN_CAPTURE_CHANNEL = "com.example.app/screen_capture"
    private var pendingScreenCaptureResult: MethodChannel.Result? = null

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SCREEN_CAPTURE_PERMISSION_REQUEST_CODE) return

        val result = pendingScreenCaptureResult
        pendingScreenCaptureResult = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            result?.success(false)
            return
        }

        val serviceIntent = Intent(this, OverlayCaptureService::class.java).apply {
            action = OverlayCaptureService.ACTION_START
            putExtra(OverlayCaptureService.EXTRA_RESULT_CODE, resultCode)
            putExtra(OverlayCaptureService.EXTRA_RESULT_DATA, data)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
        result?.success(true)
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "startHornDetection") {
                val windowSec = call.argument<Int>("windowSeconds") ?: 0
                val intent = Intent(this, HornDetectionService::class.java).apply {
                    action = HornDetectionService.ACTION_START
                    putExtra(HornDetectionService.EXTRA_WINDOW_SECONDS, windowSec)
                }
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                    startForegroundService(intent)
                } else {
                    startService(intent)
                }
                result.success(true)
            } else if (call.method == "stopHornDetection") {
                val intent = Intent(this, HornDetectionService::class.java).apply {
                    action = HornDetectionService.ACTION_STOP
                }
                startService(intent)
                result.success(true)
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_METHOD_CHANNEL).setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences("prefs", Context.MODE_PRIVATE)
            val editor = prefs.edit()

            when (call.method) {
                "setSmsScamDetectionEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    editor.putBoolean("sms_scam_detection_enabled", enabled).apply()
                    result.success(true)
                }
                "getSmsScamRecords" -> {
                    result.success(prefs.getString("sms_scam_records", "[]"))
                }
                "consumeSmsScamOpenRequest" -> {
                    val shouldOpen = prefs.getBoolean("sms_scam_open_request", false)
                    if (shouldOpen) {
                        editor.putBoolean("sms_scam_open_request", false).apply()
                    }
                    result.success(shouldOpen)
                }
                "deleteSmsScamRecord" -> {
                    val sender = call.argument<String>("sender") ?: ""
                    val body = call.argument<String>("body") ?: ""
                    val probability = call.argument<Number>("probability")?.toDouble() ?: 0.0
                    val isScam = call.argument<Boolean>("isScam") ?: false
                    val detectedAt = call.argument<Number>("detectedAt")?.toLong() ?: 0L

                    val records = org.json.JSONArray(prefs.getString("sms_scam_records", "[]") ?: "[]")
                    val next = org.json.JSONArray()
                    var removed = false
                    for (i in 0 until records.length()) {
                        val item = records.getJSONObject(i)
                        val sameSender = item.optString("sender", "") == sender
                        val sameBody = item.optString("body", "") == body
                        val sameProbability = item.optDouble("probability", -1.0) == probability
                        val sameScam = item.optBoolean("isScam", false) == isScam
                        val sameDetectedAt = item.optLong("detectedAt", -1L) == detectedAt
                        if (!removed && sameSender && sameBody && sameProbability && sameScam && sameDetectedAt) {
                            removed = true
                            continue
                        }
                        next.put(item)
                    }
                    if (removed) {
                        editor.putString("sms_scam_records", next.toString()).apply()
                    }
                    result.success(removed)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_CAPTURE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "canDrawOverlays" -> {
                    result.success(Settings.canDrawOverlays(this))
                }
                "openOverlaySettings" -> {
                    val intent = Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:$packageName")
                    ).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(intent)
                    result.success(true)
                }
                "startCaptureMode" -> {
                    if (!Settings.canDrawOverlays(this)) {
                        result.success(false)
                        return@setMethodCallHandler
                    }

                    pendingScreenCaptureResult = result
                    val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                    @Suppress("DEPRECATION")
                    startActivityForResult(
                        manager.createScreenCaptureIntent(),
                        SCREEN_CAPTURE_PERMISSION_REQUEST_CODE,
                    )
                }
                "stopCaptureMode" -> {
                    val intent = Intent(this, OverlayCaptureService::class.java).apply {
                        action = OverlayCaptureService.ACTION_STOP
                    }
                    startService(intent)
                    result.success(true)
                }
                "consumePendingCapture" -> {
                    val prefs = getSharedPreferences("prefs", Context.MODE_PRIVATE)
                    val path = prefs.getString(OverlayCaptureService.KEY_PENDING_CAPTURE_PATH, null)
                    if (path != null) {
                        prefs.edit().remove(OverlayCaptureService.KEY_PENDING_CAPTURE_PATH).apply()
                    }
                    result.success(path)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                private var receiver: BroadcastReceiver? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    receiver = object : BroadcastReceiver() {
                        override fun onReceive(context: Context, intent: Intent) {
                            when (intent.action) {
                                HornDetectionService.ACTION_PROB -> {
                                    val prob = intent.getFloatExtra(HornDetectionService.EXTRA_PROB, 0f)
                                    events?.success(mapOf("type" to "prob", "value" to prob))
                                }
                                HornDetectionService.ACTION_EVENT_START -> {
                                    val sec = intent.getIntExtra(HornDetectionService.EXTRA_SECOND, 0)
                                    events?.success(mapOf("type" to "event_start", "value" to sec))
                                }
                                HornDetectionService.ACTION_EVENT_END -> {
                                    val sec = intent.getIntExtra(HornDetectionService.EXTRA_SECOND, 0)
                                    events?.success(mapOf("type" to "event_end", "value" to sec))
                                }
                                HornDetectionService.ACTION_STATE_CHANGED -> {
                                    val running = intent.getBooleanExtra(HornDetectionService.EXTRA_RUNNING, false)
                                    events?.success(mapOf("type" to "state_changed", "value" to running))
                                }
                            }
                        }
                    }
                    val filter = IntentFilter().apply {
                        addAction(HornDetectionService.ACTION_PROB)
                        addAction(HornDetectionService.ACTION_EVENT_START)
                        addAction(HornDetectionService.ACTION_EVENT_END)
                        addAction(HornDetectionService.ACTION_STATE_CHANGED)
                    }
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                        registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
                    } else {
                        registerReceiver(receiver, filter)
                    }
                }

                override fun onCancel(arguments: Any?) {
                    receiver?.let { unregisterReceiver(it) }
                    receiver = null
                }
            }
        )
    }

    companion object {
        private const val SCREEN_CAPTURE_PERMISSION_REQUEST_CODE = 2001
    }
}
