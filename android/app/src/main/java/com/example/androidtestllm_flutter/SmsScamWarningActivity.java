package com.example.androidtestllm_flutter;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.os.Build;
import android.os.Bundle;
import android.view.Window;
import android.view.WindowManager;

import java.util.Locale;

public class SmsScamWarningActivity extends Activity {
    public static final String EXTRA_SENDER = "sender";
    public static final String EXTRA_BODY = "body";
    public static final String EXTRA_PROBABILITY = "probability";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true);
            setTurnScreenOn(true);
        } else {
            Window window = getWindow();
            window.addFlags(
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED |
                            WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            );
        }

        String sender = getIntent().getStringExtra(EXTRA_SENDER);
        String body = getIntent().getStringExtra(EXTRA_BODY);
        float probability = getIntent().getFloatExtra(EXTRA_PROBABILITY, 0f);
        if (sender == null || sender.trim().isEmpty()) {
            sender = "Unknown sender";
        }
        if (body == null) {
            body = "";
        }

        String preview = body.length() > 220 ? body.substring(0, 220) + "..." : body;
        String percent = String.format(Locale.US, "%.0f%%", probability * 100f);
        String message =
                "This may be a scam message.\n\n" +
                        "Sender: " + sender + "\n" +
                        "Scam probability: " + percent + "\n\n" +
                        preview;

        setFinishOnTouchOutside(false);
        new AlertDialog.Builder(this)
                .setTitle("Suspicious SMS detected")
                .setMessage(message)
                .setPositiveButton("I Understand", (dialog, which) -> finish())
                .setNegativeButton("Open App", (dialog, which) -> {
                    getSharedPreferences(SmsScamReceiver.PREFS_NAME, MODE_PRIVATE)
                            .edit()
                            .putBoolean(SmsScamReceiver.KEY_OPEN_REQUEST, true)
                            .apply();
                    Intent intent = new Intent(this, MainActivity.class);
                    intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
                    startActivity(intent);
                    finish();
                })
                .setOnCancelListener(dialog -> finish())
                .show();
    }
}
