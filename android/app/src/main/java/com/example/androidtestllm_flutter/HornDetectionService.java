package com.example.androidtestllm_flutter;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;
import android.os.Handler;
import android.os.Looper;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.os.VibratorManager;
import android.hardware.camera2.CameraManager;
import android.hardware.camera2.CameraCharacteristics;

import androidx.annotation.Nullable;
import androidx.core.app.NotificationCompat;
import androidx.core.content.ContextCompat;

import java.io.File;

public class HornDetectionService extends Service {
    public static final String ACTION_START = "com.example.androidtestllm.action.START";
    public static final String ACTION_STOP = "com.example.androidtestllm.action.STOP";
    public static final String ACTION_PROB = "com.example.androidtestllm.action.PROB";
    public static final String ACTION_EVENT_START = "com.example.androidtestllm.action.EVENT_START";
    public static final String ACTION_EVENT_END = "com.example.androidtestllm.action.EVENT_END";
    public static final String ACTION_STATE_CHANGED = "com.example.androidtestllm.action.STATE_CHANGED";

    public static final String EXTRA_WINDOW_SECONDS = "window_seconds";
    public static final String EXTRA_PROB = "prob";
    public static final String EXTRA_SECOND = "second";
    public static final String EXTRA_RUNNING = "running";

    private static final String CHANNEL_ID = "horn_detect";
    // Use a fresh channel ID to avoid inheriting user's old disabled/low-importance settings
    private static final String ALERT_CHANNEL_ID = "horn_alerts_v2";
    private static final int NOTIF_ID = 1001;
    private static final int ALERT_NOTIF_ID = 1002;

    private HornLiveDetector detector;
    private PowerManager.WakeLock wakeLock;
    // Alert state for background (service-level)
    private boolean alertActive = false;
    private long alertStartTime = 0; // Track when alert started
    private static final int MIN_ALERT_DURATION_MS = 800; // Minimum alert duration (300+200+300)
    private static final int ALERT_PATTERN_DURATION_MS = 4000; // Full pattern duration: 8 complete cycles × 500ms
    private Handler torchHandler;
    private boolean torchOn = false;
    private String torchCameraId = null;
    private Runnable torchBlinkerRunnable = null; // Track the current blinker to prevent duplicates

    @Override
    public void onCreate() {
        super.onCreate();
        ensureChannels();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) return START_STICKY;
        String action = intent.getAction();
        if (ACTION_START.equals(action)) {
            int windowSec = intent.getIntExtra(EXTRA_WINDOW_SECONDS, 0);
            startForeground(NOTIF_ID, buildNotification());
            acquireWakeLock();
            startDetector(windowSec);
            setServiceRunning(true);
            sendStateChanged(true);
        } else if (ACTION_STOP.equals(action)) {
            stopDetector();
            stopForeground(true);
            stopSelf();
            setServiceRunning(false);
            sendStateChanged(false);
        }
        return START_STICKY;
    }

    private void startDetector(int windowSec) {
        if (detector != null) return;
        detector = new HornLiveDetector(getApplicationContext(), new HornLiveDetector.Listener() {
            @Override public void onSegmentSaved(File wavFile) { /* no-op */ }
            @Override public void onProbability(float p) {
                Intent br = new Intent(ACTION_PROB);
                br.putExtra(EXTRA_PROB, p);
                sendBroadcast(br);
                // Fallback: trigger alerts on threshold if events are not emitted
                if (p >= 0.90f && !alertActive && !alertsSuppressed()) {
                    showAlertNotification();
                    startAlertEffects(4000);
                } else if (p < 0.4f && alertActive) {
                    stopAlertEffects();
                    cancelAlertNotification();
                }
            }
            @Override public void onEventStart(int startSecond) {
                Intent br = new Intent(ACTION_EVENT_START);
                br.putExtra(EXTRA_SECOND, startSecond);
                sendBroadcast(br);
                // Only trigger alert if not already active to prevent multiple overlapping handlers
                if (!alertActive && !alertsSuppressed()) {
                    showAlertNotification();
                    startAlertEffects(4000);
                }
            }
            @Override public void onEventEnd(int endSecond) {
                Intent br = new Intent(ACTION_EVENT_END);
                br.putExtra(EXTRA_SECOND, endSecond);
                sendBroadcast(br);
                stopAlertEffects();
                cancelAlertNotification();
            }
        });
        try {
            detector.setWindowSecondsOverride(windowSec);
            detector.start();
        } catch (Exception e) {
            // If start fails, stop service
            stopDetector();
            stopForeground(true);
            stopSelf();
        }
    }

    private void stopDetector() {
        if (detector != null) {
            try { detector.stop(); } catch (Exception ignored) {}
            detector = null;
        }
        releaseWakeLock();
        // Do not broadcast here; caller paths (STOP/onDestroy) handle broadcasts
    }

    private void ensureChannels() {
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel ch = new NotificationChannel(CHANNEL_ID, "Horn Detection", NotificationManager.IMPORTANCE_LOW);
            ch.setDescription("Listening for horn sounds");
            NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm != null) {
                nm.createNotificationChannel(ch);
                NotificationChannel alert = new NotificationChannel(ALERT_CHANNEL_ID, "Horn Alerts", NotificationManager.IMPORTANCE_HIGH);
                alert.setDescription("Vehicle horn detected alerts");
                alert.enableVibration(true);
                alert.setVibrationPattern(new long[]{0, 300, 200, 300});
                alert.enableLights(true);
                alert.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
                nm.createNotificationChannel(alert);
            }
        }
    }

    private Notification buildNotification() {
        Intent open = new Intent(this, MainActivity.class);
        PendingIntent pi = PendingIntent.getActivity(this, 0, open,
                Build.VERSION.SDK_INT >= 23 ? PendingIntent.FLAG_IMMUTABLE : 0);
        return new NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("Horn detection running")
                .setContentText("Listening via microphone")
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentIntent(pi)
                .setOngoing(true)
                .build();
    }

    private void acquireWakeLock() {
        try {
            PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
            if (pm != null && (wakeLock == null || !wakeLock.isHeld())) {
                wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "horn:detector");
                wakeLock.acquire();
            }
        } catch (Exception ignored) {}
    }

    private boolean alertsSuppressed() {
        try {
            return getSharedPreferences("prefs", MODE_PRIVATE).getBoolean("suppress_horn_alerts", false);
        } catch (Exception e) {
            return false;
        }
    }

    private void releaseWakeLock() {
        try {
            if (wakeLock != null && wakeLock.isHeld()) wakeLock.release();
            wakeLock = null;
        } catch (Exception ignored) {}
    }

    @Override
    public void onDestroy() {
        stopDetector();
        setServiceRunning(false);
        sendStateChanged(false);
        super.onDestroy();
    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    // ====== Alerts (notification, vibration, torch) ======
    private void showAlertNotification() {
        NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm == null) return;
        Intent open = new Intent(this, MainActivity.class);
        PendingIntent pi = PendingIntent.getActivity(this, 0, open,
                Build.VERSION.SDK_INT >= 23 ? PendingIntent.FLAG_IMMUTABLE : 0);
        Notification n = new NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
                .setContentTitle("Vehicle horn detected")
                .setContentText("Caution: a vehicle horn sound was detected nearby")
                .setSmallIcon(R.mipmap.ic_launcher)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
                .setOnlyAlertOnce(false)
                .setAutoCancel(true)
                .setContentIntent(pi)
                .build();
        nm.notify(ALERT_NOTIF_ID, n);
    }

    private void cancelAlertNotification() {
        NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm != null) nm.cancel(ALERT_NOTIF_ID);
    }

    private void setServiceRunning(boolean running) {
        try {
            getSharedPreferences("prefs", MODE_PRIVATE).edit().putBoolean("horn_service_running", running).apply();
        } catch (Exception ignored) {}
    }

    private void sendStateChanged(boolean running) {
        try {
            Intent br = new Intent(ACTION_STATE_CHANGED);
            br.putExtra(EXTRA_RUNNING, running);
            sendBroadcast(br);
        } catch (Exception ignored) {}
    }

    private void startAlertEffects(int durationMs) {
        // Stop any existing alert effects to prevent overlapping handlers
        if (torchHandler != null) {
            torchHandler.removeCallbacksAndMessages(null);
        }
        if (torchBlinkerRunnable != null) {
            torchBlinkerRunnable = null;
        }
        setTorch(false);
        
        alertActive = true;
        alertStartTime = System.currentTimeMillis(); // Record start time
        // Ensure minimum duration of 800ms (one complete cycle: 300+200+300)
        int effectiveDuration = Math.max(MIN_ALERT_DURATION_MS, durationMs);
        
        // Vibrate with pattern: vibrate 300ms, pause 200ms, repeat 8 complete cycles = 4000ms
        try {
            if (Build.VERSION.SDK_INT >= 31) {
                VibratorManager vm = (VibratorManager) getSystemService(Context.VIBRATOR_MANAGER_SERVICE);
                if (vm != null) {
                    Vibrator vib = vm.getDefaultVibrator();
                    if (vib != null && vib.hasVibrator()) {
                        // Pattern: {delay, vibrate, sleep} × 8 complete cycles = 4000ms total
                        // Last 200ms is the pause of the 8th cycle
                        long[] pattern = {0, 300, 200, 300, 200, 300, 200, 300, 200, 300, 200, 300, 200, 300, 200, 300, 200};
                        vib.vibrate(VibrationEffect.createWaveform(pattern, -1)); // -1 = no repeat
                    }
                }
            } else {
                Vibrator vib = (Vibrator) getSystemService(Context.VIBRATOR_SERVICE);
                if (vib != null && vib.hasVibrator()) {
                    if (Build.VERSION.SDK_INT >= 26) {
                        long[] pattern = {0, 300, 200, 300, 200, 300, 200, 300, 200, 300, 200, 300, 200, 300, 200, 300, 200};
                        vib.vibrate(VibrationEffect.createWaveform(pattern, -1));
                    } else {
                        long[] pattern = {0, 300, 200, 300, 200, 300, 200, 300, 200, 300, 200, 300, 200, 300, 200, 300, 200};
                        vib.vibrate(pattern, -1);
                    }
                }
            }
        } catch (Exception ignored) {}

        // Torch blink synchronized with vibration: 300ms on, 200ms off, for exactly 3800ms
        startTorchBlinkSynchronized(ALERT_PATTERN_DURATION_MS);
        
        // Auto-reset alertActive after duration to allow re-triggering
        new Handler(Looper.getMainLooper()).postDelayed(() -> {
            if (alertActive) {
                alertActive = false;
            }
        }, effectiveDuration);
    }

    private void stopAlertEffects() {
        // Check if minimum duration has elapsed
        long elapsed = System.currentTimeMillis() - alertStartTime;
        if (elapsed < MIN_ALERT_DURATION_MS) {
            // Not enough time elapsed, delay the stop to reach minimum duration
            long remainingTime = MIN_ALERT_DURATION_MS - elapsed;
            new Handler(Looper.getMainLooper()).postDelayed(() -> {
                stopAlertEffectsImmediately();
            }, remainingTime);
            return;
        }
        
        // Minimum duration reached, stop immediately
        stopAlertEffectsImmediately();
    }
    
    private void stopAlertEffectsImmediately() {
        alertActive = false;
        // Stop vibration
        try {
            if (Build.VERSION.SDK_INT >= 31) {
                VibratorManager vm = (VibratorManager) getSystemService(Context.VIBRATOR_MANAGER_SERVICE);
                if (vm != null) {
                    Vibrator vib = vm.getDefaultVibrator();
                    if (vib != null) vib.cancel();
                }
            } else {
                Vibrator vib = (Vibrator) getSystemService(Context.VIBRATOR_SERVICE);
                if (vib != null) vib.cancel();
            }
        } catch (Exception ignored) {}

        if (torchHandler != null) torchHandler.removeCallbacksAndMessages(null);
        torchBlinkerRunnable = null;
        setTorch(false);
    }

    private void startTorchBlinkSynchronized(int durationMs) {
        if (Build.VERSION.SDK_INT < 23) return;
        if (torchHandler == null) torchHandler = new Handler(Looper.getMainLooper());

        // Build toggle schedule based on requested duration
        // Each full cycle = 300ms ON + 200ms OFF = 500ms
        int fullCycles = durationMs / 500;
        int remainder = durationMs % 500;
        int toggleLen = fullCycles * 2 + (remainder > 0 ? 1 : 0) + (remainder > 300 ? 1 : 0);
        final long[] toggleTimes = new long[toggleLen];
        final boolean[] toggleStates = new boolean[toggleLen];

        int idx = 0;
        for (int i = 0; i < fullCycles; i++) {
            long base = i * 500L;
            toggleTimes[idx] = base;           // ON at start of cycle
            toggleStates[idx] = true;
            idx++;
            toggleTimes[idx] = base + 300L;    // OFF after 300ms
            toggleStates[idx] = false;
            idx++;
        }
        if (remainder > 0) {
            long base = fullCycles * 500L;
            toggleTimes[idx] = base;           // Partial cycle ON
            toggleStates[idx] = true;
            idx++;
            if (remainder > 300) {
                toggleTimes[idx] = base + 300L; // Partial cycle OFF
                toggleStates[idx] = false;
                idx++;
            }
        }

        final long startTime = System.currentTimeMillis();
        torchBlinkerRunnable = new Runnable() {
            int currentIndex = 0;
            @Override public void run() {
                // Safety checks
                if (!alertActive || torchBlinkerRunnable != this) {
                    setTorch(false);
                    return;
                }

                long elapsed = System.currentTimeMillis() - startTime;

                // Advance to the first future toggle to avoid burst catch-up
                while (currentIndex < toggleTimes.length && toggleTimes[currentIndex] <= elapsed) {
                    currentIndex++;
                }

                // Apply the most recent desired state (if any toggle has occurred)
                if (currentIndex > 0) {
                    setTorch(toggleStates[currentIndex - 1]);
                } else {
                    setTorch(false);
                }

                // If no further toggles, stop
                if (currentIndex >= toggleTimes.length) {
                    setTorch(false);
                    return;
                }

                long delay = toggleTimes[currentIndex] - elapsed;
                if (delay < 1) delay = 1;
                torchHandler.postDelayed(this, delay);
            }
        };

        // Start schedule runner
        torchHandler.post(torchBlinkerRunnable);
    }

    private void setTorch(boolean on) {
        if (Build.VERSION.SDK_INT < 23) return;
        if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.CAMERA) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            return;
        }
        try {
            CameraManager cm = (CameraManager) getSystemService(Context.CAMERA_SERVICE);
            if (cm == null) return;
            if (torchCameraId == null) {
                for (String id : cm.getCameraIdList()) {
                    CameraCharacteristics cc = cm.getCameraCharacteristics(id);
                    Boolean hasFlash = cc.get(CameraCharacteristics.FLASH_INFO_AVAILABLE);
                    Integer facing = cc.get(CameraCharacteristics.LENS_FACING);
                    if (Boolean.TRUE.equals(hasFlash) && (facing == null || facing == CameraCharacteristics.LENS_FACING_BACK)) {
                        torchCameraId = id;
                        break;
                    }
                }
                if (torchCameraId == null) return;
            }
            try {
                cm.setTorchMode(torchCameraId, on);
                torchOn = on;
            } catch (SecurityException ignored) {
                return;
            }
        } catch (Exception ignored) {}
    }
}
