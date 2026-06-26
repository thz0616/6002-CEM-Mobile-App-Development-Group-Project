package com.example.androidtestllm_flutter;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import android.provider.Telephony;
import android.telephony.SmsMessage;
import android.util.Log;

import androidx.core.app.NotificationCompat;
import androidx.core.app.NotificationManagerCompat;
import androidx.core.content.ContextCompat;

import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class SmsScamReceiver extends BroadcastReceiver {
    public static final String PREFS_NAME = "prefs";
    public static final String KEY_ENABLED = "sms_scam_detection_enabled";
    public static final String KEY_RECORDS = "sms_scam_records";
    public static final String KEY_OPEN_REQUEST = "sms_scam_open_request";

    private static final String TAG = "SmsScamReceiver";
    private static final String CHANNEL_ID = "sms_scam_alerts";
    private static final float ALERT_THRESHOLD = 0.75f;
    private static final ExecutorService EXECUTOR = Executors.newSingleThreadExecutor();

    @Override
    public void onReceive(Context context, Intent intent) {
        if (!Telephony.Sms.Intents.SMS_RECEIVED_ACTION.equals(intent.getAction())) {
            return;
        }

        SharedPreferences prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        if (!prefs.getBoolean(KEY_ENABLED, false)) {
            return;
        }

        PendingResult pendingResult = goAsync();
        EXECUTOR.execute(() -> {
            try {
                SmsPayload payload = readSms(intent);
                if (payload.body.isEmpty()) {
                    return;
                }

                SmsScamClassifier classifier = SmsScamClassifier.getInstance(context);
                float scamProbability = classifier.classify(payload.body);
                Log.i(TAG, "SMS scam probability=" + scamProbability + " from=" + payload.sender);

                boolean isScam = scamProbability >= ALERT_THRESHOLD;
                saveRecord(context, payload, scamProbability, isScam);

                if (isScam) {
                    prefs.edit().putBoolean(KEY_OPEN_REQUEST, true).apply();
                    showPopupWarning(context, payload, scamProbability);
                    showWarning(context, payload, scamProbability);
                }
            } catch (Exception e) {
                Log.e(TAG, "Failed to classify incoming SMS", e);
            } finally {
                pendingResult.finish();
            }
        });
    }

    private SmsPayload readSms(Intent intent) {
        SmsMessage[] messages = Telephony.Sms.Intents.getMessagesFromIntent(intent);
        StringBuilder body = new StringBuilder();
        String sender = "";
        for (SmsMessage message : messages) {
            if (message == null) {
                continue;
            }
            if (sender.isEmpty() && message.getOriginatingAddress() != null) {
                sender = message.getOriginatingAddress();
            }
            if (message.getMessageBody() != null) {
                body.append(message.getMessageBody());
            }
        }
        return new SmsPayload(sender, body.toString().trim());
    }

    private void saveRecord(Context context, SmsPayload payload, float probability, boolean isScam) {
        try {
            SmsScamDatabase.getInstance(context).insertRecord(
                    payload.sender,
                    payload.body,
                    probability,
                    isScam,
                    System.currentTimeMillis()
            );
            SharedPreferences prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
            org.json.JSONArray records = new org.json.JSONArray(
                    prefs.getString(KEY_RECORDS, "[]") == null ? "[]"
                            : prefs.getString(KEY_RECORDS, "[]")
            );
            org.json.JSONArray next = new org.json.JSONArray();
            next.put(new org.json.JSONObject()
                    .put("sender", payload.sender)
                    .put("body", payload.body)
                    .put("probability", probability)
                    .put("isScam", isScam)
                    .put("detectedAt", System.currentTimeMillis()));
            int limit = Math.min(records.length(), 79);
            for (int i = 0; i < limit; i++) {
                next.put(records.getJSONObject(i));
            }
            prefs.edit().putString(KEY_RECORDS, next.toString()).apply();
        } catch (Exception e) {
            Log.e(TAG, "Failed to save SMS scam detection record", e);
        }
    }

    private void showWarning(Context context, SmsPayload payload, float probability) {
        createChannel(context);

        Intent openIntent = warningIntent(context, payload, probability);
        openIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        PendingIntent pendingIntent = PendingIntent.getActivity(
                context,
                4402,
                openIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );

        String percent = String.format(Locale.US, "%.0f%%", probability * 100f);
        String senderText = payload.sender.isEmpty() ? "Unknown sender" : payload.sender;
        String preview = payload.body.length() > 120
                ? payload.body.substring(0, 120) + "..."
                : payload.body;

        NotificationCompat.Builder builder = new NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_sys_warning)
                .setContentTitle("Suspicious SMS detected")
                .setContentText(senderText + " - " + percent + " scam probability")
                .setStyle(new NotificationCompat.BigTextStyle().bigText(preview))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setFullScreenIntent(pendingIntent, true)
                .setAutoCancel(true)
                .setContentIntent(pendingIntent);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                ContextCompat.checkSelfPermission(
                        context,
                        android.Manifest.permission.POST_NOTIFICATIONS
                ) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            Log.w(TAG, "POST_NOTIFICATIONS not granted; cannot show SMS scam warning");
            return;
        }

        NotificationManagerCompat.from(context).notify(
                4500 + (int) (System.currentTimeMillis() % 1000),
                builder.build()
        );
    }

    private void showPopupWarning(Context context, SmsPayload payload, float probability) {
        try {
            Intent intent = warningIntent(context, payload, probability);
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            context.startActivity(intent);
        } catch (Exception e) {
            Log.w(TAG, "Could not show SMS scam popup; notification fallback will be used", e);
        }
    }

    private Intent warningIntent(Context context, SmsPayload payload, float probability) {
        Intent intent = new Intent(context, SmsScamWarningActivity.class);
        intent.putExtra(SmsScamWarningActivity.EXTRA_SENDER, payload.sender);
        intent.putExtra(SmsScamWarningActivity.EXTRA_BODY, payload.body);
        intent.putExtra(SmsScamWarningActivity.EXTRA_PROBABILITY, probability);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        return intent;
    }

    private void createChannel(Context context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return;
        }
        NotificationManager manager =
                (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        NotificationChannel existing = manager.getNotificationChannel(CHANNEL_ID);
        if (existing != null) {
            return;
        }
        NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID,
                "SMS Scam Alerts",
                NotificationManager.IMPORTANCE_HIGH
        );
        channel.setDescription("Warnings for suspicious incoming SMS messages");
        manager.createNotificationChannel(channel);
    }

    private static class SmsPayload {
        final String sender;
        final String body;

        SmsPayload(String sender, String body) {
            this.sender = sender == null ? "" : sender;
            this.body = body == null ? "" : body;
        }
    }
}
