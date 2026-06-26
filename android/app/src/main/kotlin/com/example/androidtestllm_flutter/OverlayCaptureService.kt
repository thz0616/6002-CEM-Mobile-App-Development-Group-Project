package com.example.androidtestllm_flutter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.pm.ServiceInfo
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.Toast
import androidx.core.app.NotificationCompat
import java.io.File
import java.io.FileOutputStream

class OverlayCaptureService : Service() {
    private var mediaProjection: MediaProjection? = null
    private var overlayButton: Button? = null
    private var windowManager: WindowManager? = null
    private var isCapturing = false
    private val mainHandler = Handler(Looper.getMainLooper())
    private val projectionCallback = object : MediaProjection.Callback() {
        override fun onStop() {
            mediaProjection = null
            removeOverlayButton()
            stopSelf()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                startCaptureForeground()
                ensureProjection(intent)
                showOverlayButton()
            }
            ACTION_STOP -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                } else {
                    @Suppress("DEPRECATION")
                    stopForeground(true)
                }
                stopSelf()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        removeOverlayButton()
        mediaProjection?.let { projection ->
            projection.unregisterCallback(projectionCallback)
            projection.stop()
        }
        mediaProjection = null
        super.onDestroy()
    }

    private fun ensureProjection(intent: Intent?) {
        if (intent == null) return
        if (mediaProjection != null) return

        val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
        val resultData = intent.getParcelableExtraCompat<Intent>(EXTRA_RESULT_DATA) ?: return
        val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val projection = manager.getMediaProjection(resultCode, resultData) ?: return
        projection.registerCallback(projectionCallback, mainHandler)
        mediaProjection = projection
    }

    private fun showOverlayButton() {
        if (overlayButton != null) return

        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val button = Button(this).apply {
            text = "CAP"
            setOnClickListener {
                if (!isCapturing) {
                    captureScreen()
                }
            }
        }

        val size = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            64f,
            resources.displayMetrics,
        ).toInt()
        val params = WindowManager.LayoutParams(
            size,
            size,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                WindowManager.LayoutParams.TYPE_PHONE
            },
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.END
            x = 24
            y = 220
        }

        windowManager?.addView(button, params)
        overlayButton = button
    }

    private fun removeOverlayButton() {
        overlayButton?.let { button ->
            windowManager?.removeView(button)
        }
        overlayButton = null
        windowManager = null
    }

    private fun captureScreen() {
        val projection = mediaProjection
        if (projection == null) {
            showToast("Screen capture permission is no longer available.")
            return
        }

        isCapturing = true
        val metrics = resources.displayMetrics
        val width = metrics.widthPixels
        val height = metrics.heightPixels
        val density = metrics.densityDpi
        val imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
        var virtualDisplay: VirtualDisplay? = null

        imageReader.setOnImageAvailableListener({ reader ->
            val image = reader.acquireLatestImage() ?: return@setOnImageAvailableListener
            try {
                val plane = image.planes.firstOrNull() ?: return@setOnImageAvailableListener
                val buffer = plane.buffer
                val pixelStride = plane.pixelStride
                val rowStride = plane.rowStride
                val rowPadding = rowStride - pixelStride * width
                val bitmap = Bitmap.createBitmap(
                    width + rowPadding / pixelStride,
                    height,
                    Bitmap.Config.ARGB_8888,
                )
                bitmap.copyPixelsFromBuffer(buffer)
                val cropped = Bitmap.createBitmap(bitmap, 0, 0, width, height)
                bitmap.recycle()

                val output = File(cacheDir, "capture_${System.currentTimeMillis()}.png")
                FileOutputStream(output).use { stream ->
                    cropped.compress(Bitmap.CompressFormat.PNG, 100, stream)
                }
                cropped.recycle()

                getSharedPreferences("prefs", Context.MODE_PRIVATE)
                    .edit()
                    .putString(KEY_PENDING_CAPTURE_PATH, output.absolutePath)
                    .apply()

                bringAppToFront()
            } finally {
                image.close()
                reader.setOnImageAvailableListener(null, null)
                reader.close()
                virtualDisplay?.release()
                isCapturing = false
            }
        }, Handler(Looper.getMainLooper()))

        try {
            virtualDisplay = projection.createVirtualDisplay(
                "AccountingCapture",
                width,
                height,
                density,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                imageReader.surface,
                null,
                null,
            )
        } catch (error: RuntimeException) {
            imageReader.setOnImageAvailableListener(null, null)
            imageReader.close()
            isCapturing = false
            Log.e(TAG, "Unable to start screen capture", error)
            showToast("Unable to capture the screen. Please restart capture mode.")
            return
        }

        mainHandler.postDelayed({
            if (isCapturing) {
                imageReader.setOnImageAvailableListener(null, null)
                imageReader.close()
                virtualDisplay?.release()
                isCapturing = false
                showToast("Screen capture timed out. Please try again.")
            }
        }, 3000)
    }

    private fun bringAppToFront() {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
            )
        }
        if (launchIntent != null) {
            startActivity(launchIntent)
        }
    }

    private fun showToast(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
    }

    private fun createNotification(): Notification {
        createNotificationChannel()
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("Accounting Capture")
            .setContentText("Capture mode is active.")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun startCaptureForeground() {
        val notification = createNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            "Accounting Capture",
            NotificationManager.IMPORTANCE_LOW,
        )
        manager.createNotificationChannel(channel)
    }

    @Suppress("DEPRECATION")
    private inline fun <reified T> Intent.getParcelableExtraCompat(key: String): T? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            getParcelableExtra(key, T::class.java)
        } else {
            getParcelableExtra(key) as? T
        }
    }

    companion object {
        const val ACTION_START = "screen_capture_start"
        const val ACTION_STOP = "screen_capture_stop"
        const val EXTRA_RESULT_CODE = "result_code"
        const val EXTRA_RESULT_DATA = "result_data"
        const val KEY_PENDING_CAPTURE_PATH = "pending_capture_path"

        private const val NOTIFICATION_CHANNEL_ID = "accounting_capture_channel"
        private const val NOTIFICATION_ID = 2002
        private const val TAG = "OverlayCaptureService"
    }
}
