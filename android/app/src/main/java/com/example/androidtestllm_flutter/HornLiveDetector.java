package com.example.androidtestllm_flutter;

import android.content.Context;
import android.content.res.AssetFileDescriptor;
import android.content.res.AssetManager;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import android.os.Handler;
import android.os.HandlerThread;
import android.util.Log;
import android.os.Build;
import android.Manifest;
import android.content.pm.PackageManager;
import androidx.core.content.ContextCompat;

import org.json.JSONObject;
import org.tensorflow.lite.Interpreter;
import org.tensorflow.lite.support.common.FileUtil;

import java.io.BufferedOutputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.text.SimpleDateFormat;
import java.util.Arrays;
import java.util.Date;
import java.util.Locale;
import java.util.HashMap;
import java.util.Map;

/**
 * Live horn detector that:
 * - Records mic audio at 16 kHz mono.
 * - Segments 1-second windows, saves each as WAV in app cache.
 * - Runs YAMNet tflite to get 1024-d embeddings, mean-pooled per window.
 * - Runs head model tflite (your exported model) to get horn probability.
 * - Applies simple hysteresis post-processing online.
 */
public class HornLiveDetector {
    public interface Listener {
        void onSegmentSaved(File wavFile);
        void onProbability(float p);
        void onEventStart(int startSecond);
        void onEventEnd(int endSecond);
    }

    private static final String TAG = "HornLiveDetector";

    private final Context context;
    private final AssetManager assets;
    private final Listener listener;

    private Interpreter yamnet;
    private Interpreter head;

    private float thr = 0.5f;
    private float windowSeconds = 0.2f;
    private int medianMs = 600;
    private int minEventMs = 200;
    private float hStart = 0.9f;
    private float hKeep = 0.4f;
    // Optional runtime override for window seconds (in seconds)
    private Float windowOverride = null;

    private AudioRecord recorder;
    private HandlerThread workerThread;
    private Handler worker;

    private volatile boolean running = false;

    private float[] medianBuf; // simple rolling median buffer values
    private int medianK = 1;

    private boolean active = false;
    private int activeStartFrame = -1; // frame index (increments by 1 per window)
    private int timeMs = 0;            // cumulative time in milliseconds
    private int frameIndex = 0;        // current frame index

    private File segmentsDir;

    public HornLiveDetector(Context ctx, Listener listener) {
        this.context = ctx.getApplicationContext();
        this.assets = ctx.getAssets();
        this.listener = listener;
    }

    public void setWindowSecondsOverride(float seconds) {
        if (seconds <= 0) {
            this.windowOverride = null; // Use meta.json value
            return;
        }
        if (seconds < 0.2f) seconds = 0.2f;
        this.windowOverride = seconds;
    }

    public void start() throws Exception {
        if (running) return;
        loadModelsAndMeta();
        setupRecorder();
        segmentsDir = new File(context.getCacheDir(), "horn_segments");
        if (!segmentsDir.exists()) segmentsDir.mkdirs();

        running = true;
        workerThread = new HandlerThread("HornLiveWorker");
        workerThread.start();
        worker = new Handler(workerThread.getLooper());
        worker.post(this::loop);
    }

    public void stop() {
        running = false;
        try { if (recorder != null) recorder.stop(); } catch (Exception ignored) {}
        try { if (recorder != null) recorder.release(); } catch (Exception ignored) {}
        recorder = null;
        if (workerThread != null) {
            workerThread.quitSafely();
            workerThread = null;
        }
        if (yamnet != null) { yamnet.close(); yamnet = null; }
        if (head != null) { head.close(); head = null; }
        active = false;
        activeStartFrame = -1;
        frameIndex = 0;
        timeMs = 0;
    }

    private void loadModelsAndMeta() throws Exception {
        // Load YAMNet (must be named yamnet.tflite in assets root per Gradle sourceSets)
        try {
            // Diagnostic: list assets root once
            try {
                String[] root = assets.list("");
                Log.i(TAG, "Assets root entries: " + (root == null ? "<null>" : java.util.Arrays.toString(root)));
            } catch (Exception ignore) {}
            // Log supported ABIs
            try {
                Log.i(TAG, "Device SUPPORTED_ABIS=" + java.util.Arrays.toString(Build.SUPPORTED_ABIS));
            } catch (Exception ignore) {}
            // Check file is present
            try { assets.open("yamnet.tflite").close(); } catch (Exception nf) {
                throw new Exception("yamnet.tflite not found in assets root. Ensure app/src/main/tflite_model/yamnet.tflite is packaged.", nf);
            }
            // Log file length if possible
            try {
                android.content.res.AssetFileDescriptor afd = assets.openFd("yamnet.tflite");
                Log.i(TAG, "yamnet.tflite length=" + afd.getLength());
                afd.close();
            } catch (Exception eLen) {
                try (InputStream inLen = assets.open("yamnet.tflite")) {
                    byte[] all = readAll(inLen);
                    Log.i(TAG, "yamnet.tflite length (stream)=" + all.length);
                } catch (Exception ignore2) {}
            }
            ByteBuffer yamnetModel = loadAssetToMmap("yamnet.tflite");
            Interpreter.Options opts = new Interpreter.Options();
            opts.setNumThreads(Math.max(1, Runtime.getRuntime().availableProcessors() / 2));
            // Some devices crash with XNNPACK; disable for safety
            try { opts.setUseXNNPACK(false); } catch (Throwable ignored) {}
            try { opts.setUseNNAPI(false); } catch (Throwable ignored) {}
            yamnet = new Interpreter(yamnetModel, opts);
        } catch (Exception e) {
            Log.e(TAG, "Create YAMNet interpreter failed", e);
            throw new Exception("Load YAMNet failed: " + e.getMessage(), e);
        }

        // Find your head model and metadata. If exact names exist, use them; else best-effort scan.
        String headPath = "202509201715.tflite";
        String metaPath = "202509201715.meta.json";
        try {
            // Try to open explicitly; will throw if not present
            assets.open(headPath).close();
            assets.open(metaPath).close();
        } catch (Exception e) {
            // Fallback: pick any .meta.json and matching .tflite (not yamnet)
            String[] list = assets.list("");
            if (list != null) {
                for (String name : list) {
                    if (name.endsWith(".meta.json")) { metaPath = name; }
                }
                for (String name : list) {
                    if (name.endsWith(".tflite") && !name.equals("yamnet.tflite")) { headPath = name; break; }
                }
            }
        }
        try {
            ByteBuffer headModel = loadAssetToMmap(headPath);
            Interpreter.Options opts2 = new Interpreter.Options();
            opts2.setNumThreads(Math.max(1, Runtime.getRuntime().availableProcessors() / 2));
            head = new Interpreter(headModel, opts2);
        } catch (Exception e) {
            Log.e(TAG, "Create head interpreter failed", e);
            throw new Exception("Load head model failed (" + headPath + "): " + e.getMessage(), e);
        }

        // Read metadata for thresholds and post-process
        try (InputStream in = assets.open(metaPath)) {
            byte[] bytes = readAll(in);
            JSONObject jo = new JSONObject(new String(bytes));
            thr = (float) jo.optDouble("threshold", thr);
            windowSeconds = (float) jo.optDouble("window_seconds", windowSeconds);
            JSONObject pp = jo.optJSONObject("postprocess");
            if (pp != null) {
                medianMs = pp.optInt("median_ms", medianMs);
                minEventMs = pp.optInt("min_event_ms", minEventMs);
                hStart = (float) pp.optDouble("hysteresis_start", hStart);
                hKeep = (float) pp.optDouble("hysteresis_keep", hKeep);
            }
        }
        // Apply runtime override for window seconds if provided
        if (windowOverride != null) {
            windowSeconds = windowOverride;
        }
        // Enforce minimum window of 200ms
        windowSeconds = Math.max(0.2f, windowSeconds);
        // Median window size in frames (frames per second = 1/windowSeconds)
        float fps = 1f / Math.max(1e-9f, windowSeconds);
        medianK = Math.max(1, Math.round((medianMs / 1000f) * fps));
        if ((medianK % 2) == 0) medianK += 1; // odd length
        medianBuf = new float[Math.max(1, medianK)];
        Arrays.fill(medianBuf, 0f);
    }

    private void setupRecorder() throws Exception {
        int sr = 16000;
        int ch = AudioFormat.CHANNEL_IN_MONO;
        int fmt = AudioFormat.ENCODING_PCM_16BIT;
        int minBuf = AudioRecord.getMinBufferSize(sr, ch, fmt);
        int bufSize = Math.max(minBuf, sr * 2); // at least 2 seconds
        // Explicit permission check for RECORD_AUDIO
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            throw new Exception("RECORD_AUDIO permission not granted");
        }

        AudioRecord tmp = null;
        try {
            tmp = new AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, sr, ch, fmt, bufSize);
        } catch (SecurityException se) {
            Log.w(TAG, "AudioRecord VOICE_RECOGNITION security exception", se);
            tmp = null;
        }
        if (tmp == null || tmp.getState() != AudioRecord.STATE_INITIALIZED) {
            if (tmp != null) { try { tmp.release(); } catch (Exception ignored) {} }
            try {
                tmp = new AudioRecord(MediaRecorder.AudioSource.MIC, sr, ch, fmt, bufSize);
            } catch (SecurityException se2) {
                Log.e(TAG, "AudioRecord MIC security exception", se2);
                tmp = null;
            }
        }
        if (tmp == null || tmp.getState() != AudioRecord.STATE_INITIALIZED) {
            throw new Exception("Failed to initialize AudioRecord (VOICE_RECOGNITION and MIC)");
        }
        recorder = tmp;
        try {
            recorder.startRecording();
        } catch (SecurityException se) {
            try { recorder.release(); } catch (Exception ignored) {}
            recorder = null;
            throw new Exception("startRecording() security exception (permission denied at runtime)", se);
        } catch (IllegalStateException ise) {
            try { recorder.release(); } catch (Exception ignored) {}
            recorder = null;
            throw new Exception("startRecording() failed: " + ise.getMessage(), ise);
        }
    }

    private void loop() {
        int samplesPerWindow = Math.max(1, Math.round(16000 * windowSeconds));
        short[] pcm16 = new short[samplesPerWindow];
        float[] mono = new float[samplesPerWindow];
        int windowMs = Math.max(1, Math.round(windowSeconds * 1000f));
        while (running) {
            int read = 0;
            while (read < samplesPerWindow && running) {
                int r = recorder.read(pcm16, read, samplesPerWindow - read);
                if (r > 0) read += r; else try { Thread.sleep(5); } catch (InterruptedException ignored) {}
            }
            if (!running) break;

            // Convert to float [-1,1]
            float maxAbs = 0f;
            double sumsq = 0.0;
            for (int i = 0; i < samplesPerWindow; i++) {
                float v = pcm16[i] / 32768f;
                mono[i] = v;
                float a = Math.abs(v);
                if (a > maxAbs) maxAbs = a;
                sumsq += (double) v * v;
            }
            float rms = (float) Math.sqrt(sumsq / Math.max(1, samplesPerWindow));

            // Save WAV segment
            File wav = saveWavSegment(pcm16, 16000);
            if (listener != null && wav != null) listener.onSegmentSaved(wav);

            // Get YAMNet embeddings for this window
            float[] emb = extractEmbeddingMean(mono);
            // Run head model to get probability
            float prob = runHead(emb);
            if (listener != null) listener.onProbability(prob);

            // Log per-window inference result
            Log.i(TAG, String.format(Locale.US,
                    "t=%.3fs win=%.3fs rms=%.4f max=%.4f prob=%.4f file=%s",
                    timeMs / 1000f, windowSeconds, rms, maxAbs, prob, (wav != null ? wav.getName() : "<none>")));

            // Online median smoothing (simple buffer median)
            float probSm = prob;
            if (medianK > 1) {
                // shift left
                System.arraycopy(medianBuf, 1, medianBuf, 0, medianBuf.length - 1);
                medianBuf[medianBuf.length - 1] = prob;
                float[] tmp = Arrays.copyOf(medianBuf, medianBuf.length);
                Arrays.sort(tmp);
                probSm = tmp[tmp.length / 2];
            }

            // Hysteresis + min duration in frames
            if (!active && probSm >= hStart) {
                active = true;
                activeStartFrame = frameIndex;
                if (listener != null) listener.onEventStart(timeMs / 1000);
            } else if (active && probSm < hKeep) {
                int endFrame = frameIndex;
                int minFrames = Math.max(1, (int) Math.ceil(minEventMs / 1000f / Math.max(1e-9f, windowSeconds)));
                if ((endFrame - activeStartFrame) >= minFrames) {
                    if (listener != null) listener.onEventEnd(timeMs / 1000);
                }
                active = false;
                activeStartFrame = -1;
            }

            frameIndex += 1;
            timeMs += windowMs;
        }
    }

    private float[] extractEmbeddingMean(float[] mono) {
        try {
            // Inspect input shape and resize to match
            int[] inShape = yamnet.getInputTensor(0).shape();
            // Try to support [N] or [1,N]
            if (inShape.length == 1) {
                try { yamnet.resizeInput(0, new int[]{mono.length}); } catch (Exception ignored) {}
            } else if (inShape.length == 2) {
                try { yamnet.resizeInput(0, new int[]{1, mono.length}); } catch (Exception ignored) {}
            }
            try { yamnet.allocateTensors(); } catch (Exception e) { Log.w(TAG, "yamnet.allocateTensors failed, continuing", e); }

            // Re-query output shapes after potential resize
            int outCount = yamnet.getOutputTensorCount();
            Log.d(TAG, "YAMNet output tensor count=" + outCount);
            // Prepare outputs map for multiple outputs
            Map<Integer, Object> outputs = new HashMap<>();
            int embIndex = -1;
            float[][] embBuf = null;
            for (int i = 0; i < outCount; i++) {
                int[] s = yamnet.getOutputTensor(i).shape();
                int rows = s.length > 0 ? s[0] : 1;
                int cols = s.length > 1 ? s[1] : 1;
                float[][] buf = new float[Math.max(1, rows)][Math.max(1, cols)];
                outputs.put(i, buf);
                if (cols == 1024) { embIndex = i; embBuf = buf; }
                Log.d(TAG, "YAMNet out[" + i + "] shape=" + Arrays.toString(s));
            }

            // Prepare input object matching shape
            Object inputObj;
            if (yamnet.getInputTensor(0).shape().length == 2) {
                float[][] x = new float[1][mono.length];
                System.arraycopy(mono, 0, x[0], 0, mono.length);
                inputObj = x;
            } else {
                inputObj = mono;
            }

            // Run with multiple outputs if available
            if (outCount > 1) {
                Object[] inputs = new Object[]{inputObj};
                yamnet.runForMultipleInputsOutputs(inputs, outputs);
                if (embBuf == null) {
                    // Fallback: pick the largest cols
                    int best = -1, bestCols = -1;
                    for (int i = 0; i < outCount; i++) {
                        float[][] b = (float[][]) outputs.get(i);
                        if (b != null && b.length > 0) {
                            int c = b[0].length;
                            if (c > bestCols) { bestCols = c; best = i; }
                        }
                    }
                    if (best >= 0) embBuf = (float[][]) outputs.get(best);
                    Log.w(TAG, "No 1024-d embedding output from YAMNet; using output index=" + best + " cols=" + bestCols + " (head expects 1024)");
                }
            } else {
                // Single output
                int[] s = yamnet.getOutputTensor(0).shape();
                float[][] out = new float[Math.max(1, s[0])][Math.max(1, s.length > 1 ? s[1] : 1024)];
                yamnet.run(inputObj, out);
                embBuf = out;
            }

            if (embBuf == null || embBuf.length == 0) return new float[1024];
            int frames = embBuf.length;
            int dim = embBuf[0].length;
            Log.d(TAG, "Embedding buffer frames=" + frames + " dim=" + dim);
            float[] mean = new float[1024];
            for (int i = 0; i < frames; i++) {
                float[] row = embBuf[i];
                int L = Math.min(1024, row.length);
                for (int j = 0; j < L; j++) mean[j] += row[j];
            }
            for (int j = 0; j < 1024; j++) mean[j] /= Math.max(1, frames);
            return mean;
        } catch (Exception e) {
            Log.e(TAG, "YAMNet run failed", e);
            return new float[1024];
        }
    }

    private float runHead(float[] emb1024) {
        try {
            int inIdx = 0;
            int outIdx = 0;
            int[] inShape = head.getInputTensor(inIdx).shape(); // e.g., [1,1024] or [1024]
            int[] outShape = head.getOutputTensor(outIdx).shape(); // e.g., [1] or [1,1]

            // Try to adapt input shape
            if (inShape.length == 2) {
                int b = inShape[0];
                int d = inShape[1];
                if (b != 1 || d != 1024) {
                    try { head.resizeInput(inIdx, new int[]{1, 1024}); } catch (Exception ignored) {}
                }
            } else if (inShape.length == 1) {
                if (inShape[0] != 1024) {
                    try { head.resizeInput(inIdx, new int[]{1024}); } catch (Exception ignored) {}
                }
            }
            try { head.allocateTensors(); } catch (Exception e) { Log.w(TAG, "head.allocateTensors failed, continuing", e); }

            // Re-fetch tensors after possible resize
            org.tensorflow.lite.Tensor inT = head.getInputTensor(inIdx);
            org.tensorflow.lite.Tensor outT = head.getOutputTensor(outIdx);
            org.tensorflow.lite.Tensor.QuantizationParams inQ = inT.quantizationParams();
            org.tensorflow.lite.Tensor.QuantizationParams outQ = outT.quantizationParams();
            int[] inShapeNow = inT.shape();
            int[] outShapeNow = outT.shape();
            Log.d(TAG, "Head inShape=" + Arrays.toString(inShapeNow) + " outShape=" + Arrays.toString(outShapeNow)
                    + " inType=" + inT.dataType() + " outType=" + outT.dataType());

            // Build input buffer matching shape and type
            Object inBuf;
            if (inT.dataType() == org.tensorflow.lite.DataType.INT8) {
                byte[] q = new byte[1024];
                float scale = inQ.getScale();
                long zero = inQ.getZeroPoint();
                if (scale <= 0) scale = 1f;
                for (int i = 0; i < 1024; i++) {
                    int v = Math.round(emb1024[i] / scale + zero);
                    if (v < -128) v = -128; else if (v > 127) v = 127;
                    q[i] = (byte) v;
                }
                if (inShapeNow.length == 1) {
                    inBuf = q; // [1024]
                } else {
                    inBuf = new byte[][]{q}; // [1,1024]
                }
            } else { // FLOAT32
                float[] f = Arrays.copyOf(emb1024, 1024);
                if (inShapeNow.length == 1) {
                    inBuf = f; // [1024]
                } else {
                    inBuf = new float[][]{f}; // [1,1024]
                }
            }

            // Build output buffer matching shape and type
            if (outT.dataType() == org.tensorflow.lite.DataType.INT8) {
                float scale = outQ.getScale();
                long zero = outQ.getZeroPoint();
                if (outShapeNow.length == 1) {
                    byte[] out = new byte[1]; // [1]
                    head.run(inBuf, out);
                    return scale * (((int) out[0]) - zero);
                } else {
                    byte[][] out = new byte[1][1]; // [1,1]
                    head.run(inBuf, out);
                    return scale * (((int) out[0][0]) - zero);
                }
            } else { // FLOAT32
                if (outShapeNow.length == 1) {
                    float[] out = new float[1]; // [1]
                    head.run(inBuf, out);
                    return out[0];
                } else {
                    float[][] out = new float[1][1]; // [1,1]
                    head.run(inBuf, out);
                    return out[0][0];
                }
            }
        } catch (Exception e) {
            Log.e(TAG, "Head run failed", e);
            return 0f;
        }
    }

    private File saveWavSegment(short[] pcm16, int sr) {
        try {
            String ts = new SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(new Date());
            File f = new File(segmentsDir, "seg_" + ts + "_" + timeMs + "ms.wav");
            try (FileOutputStream fos = new FileOutputStream(f);
                 BufferedOutputStream bos = new BufferedOutputStream(fos)) {
                byte[] wav = pcm16ToWav(pcm16, sr);
                bos.write(wav);
            }
            return f;
        } catch (Exception e) {
            Log.w(TAG, "Failed to save WAV", e);
            return null;
        }
    }

    private static byte[] pcm16ToWav(short[] pcm, int sr) throws Exception {
        int channels = 1;
        int bps = 16;
        int byteRate = sr * channels * bps / 8;
        int dataLen = pcm.length * 2;
        int chunkSize = 36 + dataLen;
        ByteArrayOutputStream baos = new ByteArrayOutputStream(44 + dataLen);
        // RIFF header
        baos.write(new byte[]{'R','I','F','F'});
        baos.write(intLE(chunkSize));
        baos.write(new byte[]{'W','A','V','E'});
        // fmt chunk
        baos.write(new byte[]{'f','m','t',' '});
        baos.write(intLE(16)); // PCM
        baos.write(shortLE((short)1)); // PCM
        baos.write(shortLE((short)channels));
        baos.write(intLE(sr));
        baos.write(intLE(byteRate));
        baos.write(shortLE((short)(channels * bps / 8)));
        baos.write(shortLE((short)bps));
        // data chunk
        baos.write(new byte[]{'d','a','t','a'});
        baos.write(intLE(dataLen));
        // samples
        ByteBuffer buf = ByteBuffer.allocate(dataLen).order(ByteOrder.LITTLE_ENDIAN);
        for (short s : pcm) buf.putShort(s);
        baos.write(buf.array());
        return baos.toByteArray();
    }

    private static byte[] intLE(int v) { return new byte[]{(byte)(v),(byte)(v>>8),(byte)(v>>16),(byte)(v>>24)}; }
    private static byte[] shortLE(short v) { return new byte[]{(byte)(v),(byte)(v>>8)}; }

    private ByteBuffer loadAssetToMmap(String assetName) throws Exception {
        try {
            AssetFileDescriptor afd = assets.openFd(assetName);
            try (FileInputStream fis = new FileInputStream(afd.getFileDescriptor())) {
                long start = afd.getStartOffset();
                long length = afd.getLength();
                return fis.getChannel().map(java.nio.channels.FileChannel.MapMode.READ_ONLY, start, length);
            }
        } catch (Exception mmapFail) {
            // Fallback to loading into a direct ByteBuffer if asset is compressed
            try (InputStream in = assets.open(assetName)) {
                byte[] bytes = readAll(in);
                ByteBuffer buf = ByteBuffer.allocateDirect(bytes.length).order(ByteOrder.nativeOrder());
                buf.put(bytes);
                buf.rewind();
                return buf;
            }
        }
    }

    private static byte[] readAll(InputStream in) throws Exception {
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        byte[] buf = new byte[4096];
        int r;
        while ((r = in.read(buf)) != -1) baos.write(buf, 0, r);
        return baos.toByteArray();
    }
}
