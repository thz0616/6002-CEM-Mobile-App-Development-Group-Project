package com.example.androidtestllm_flutter;

import android.content.ContentValues;
import android.content.Context;
import android.content.SharedPreferences;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteOpenHelper;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

public class SmsScamDatabase extends SQLiteOpenHelper {
    private static final String TAG = "SmsScamDatabase";
    private static final String DATABASE_NAME = "sms_scam_detection.db";
    private static final int DATABASE_VERSION = 1;
    private static final String TABLE = "sms_scam_records";
    private static final int MAX_RECORDS = 200;
    private static final String KEY_LEGACY_MIGRATED = "sms_scam_records_migrated_to_db";

    private static SmsScamDatabase instance;

    public static synchronized SmsScamDatabase getInstance(Context context) {
        if (instance == null) {
            instance = new SmsScamDatabase(context.getApplicationContext());
            instance.migrateLegacyRecords(context.getApplicationContext());
        }
        return instance;
    }

    private SmsScamDatabase(Context context) {
        super(context, DATABASE_NAME, null, DATABASE_VERSION);
    }

    @Override
    public void onCreate(SQLiteDatabase db) {
        db.execSQL(
                "CREATE TABLE " + TABLE + " (" +
                        "_id INTEGER PRIMARY KEY AUTOINCREMENT, " +
                        "sender TEXT NOT NULL, " +
                        "body TEXT NOT NULL, " +
                        "probability REAL NOT NULL, " +
                        "is_scam INTEGER NOT NULL, " +
                        "detected_at INTEGER NOT NULL" +
                        ")"
        );
        db.execSQL("CREATE INDEX idx_sms_scam_detected_at ON " + TABLE + "(detected_at DESC)");
        db.execSQL("CREATE INDEX idx_sms_scam_is_scam ON " + TABLE + "(is_scam)");
    }

    @Override
    public void onUpgrade(SQLiteDatabase db, int oldVersion, int newVersion) {
    }

    public synchronized void insertRecord(
            String sender,
            String body,
            float probability,
            boolean isScam,
            long detectedAt
    ) {
        SQLiteDatabase db = getWritableDatabase();
        ContentValues values = new ContentValues();
        values.put("sender", sender == null ? "" : sender);
        values.put("body", body == null ? "" : body);
        values.put("probability", probability);
        values.put("is_scam", isScam ? 1 : 0);
        values.put("detected_at", detectedAt);
        db.insert(TABLE, null, values);
        db.execSQL(
                "DELETE FROM " + TABLE + " WHERE _id NOT IN (" +
                        "SELECT _id FROM " + TABLE + " ORDER BY detected_at DESC LIMIT " + MAX_RECORDS +
                        ")"
        );
    }

    public synchronized String listRecordsJson() {
        JSONArray rows = new JSONArray();
        SQLiteDatabase db = getReadableDatabase();
        try (Cursor cursor = db.query(
                TABLE,
                new String[]{"sender", "body", "probability", "is_scam", "detected_at"},
                null,
                null,
                null,
                null,
                "detected_at DESC",
                String.valueOf(MAX_RECORDS)
        )) {
            while (cursor.moveToNext()) {
                JSONObject item = new JSONObject();
                item.put("sender", cursor.getString(0));
                item.put("body", cursor.getString(1));
                item.put("probability", cursor.getDouble(2));
                item.put("isScam", cursor.getInt(3) == 1);
                item.put("detectedAt", cursor.getLong(4));
                rows.put(item);
            }
        } catch (Exception e) {
            Log.e(TAG, "Failed to read SMS scam records", e);
        }
        return rows.toString();
    }

    private synchronized void migrateLegacyRecords(Context context) {
        SharedPreferences prefs = context.getSharedPreferences(SmsScamReceiver.PREFS_NAME, Context.MODE_PRIVATE);
        if (prefs.getBoolean(KEY_LEGACY_MIGRATED, false)) {
            return;
        }

        String legacy = prefs.getString(SmsScamReceiver.KEY_RECORDS, null);
        if (legacy == null || legacy.isEmpty()) {
            prefs.edit().putBoolean(KEY_LEGACY_MIGRATED, true).apply();
            return;
        }

        try {
            JSONArray rows = new JSONArray(legacy);
            for (int i = rows.length() - 1; i >= 0; i--) {
                JSONObject item = rows.getJSONObject(i);
                insertRecord(
                        item.optString("sender", ""),
                        item.optString("body", ""),
                        (float) item.optDouble("probability", 0),
                        item.optBoolean("isScam", false),
                        item.optLong("detectedAt", System.currentTimeMillis())
                );
            }
            prefs.edit()
                    .remove(SmsScamReceiver.KEY_RECORDS)
                    .putBoolean(KEY_LEGACY_MIGRATED, true)
                    .apply();
        } catch (Exception e) {
            Log.e(TAG, "Failed to migrate legacy SMS scam records", e);
        }
    }
}
