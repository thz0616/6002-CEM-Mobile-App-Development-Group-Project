package com.example.androidtestllm_flutter;

import android.content.Context;
import android.content.res.AssetManager;
import android.util.Log;

import org.json.JSONObject;
import org.tensorflow.lite.Interpreter;
import org.tensorflow.lite.support.common.FileUtil;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

public class SmsScamClassifier {
    private static final String TAG = "SmsScamClassifier";
    private static final String ASSET_PREFIX = "flutter_assets/assets/ml/";
    private static final String MODEL_PATH = ASSET_PREFIX + "spam_sms_distilbert.tflite";
    private static final String VOCAB_PATH = ASSET_PREFIX + "vocab.txt";
    private static final String CONFIG_PATH = ASSET_PREFIX + "model_config.json";

    private static SmsScamClassifier instance;

    private final Interpreter interpreter;
    private final Map<String, Integer> vocab;
    private final int maxLength;
    private final int padId;
    private final int unkId;
    private final int clsId;
    private final int sepId;

    public static synchronized SmsScamClassifier getInstance(Context context) throws Exception {
        if (instance == null) {
            instance = new SmsScamClassifier(context.getApplicationContext());
        }
        return instance;
    }

    private SmsScamClassifier(Context context) throws Exception {
        AssetManager assets = context.getAssets();
        vocab = loadVocab(assets);
        maxLength = loadMaxLength(assets);
        padId = getRequiredTokenId("[PAD]");
        unkId = getRequiredTokenId("[UNK]");
        clsId = getRequiredTokenId("[CLS]");
        sepId = getRequiredTokenId("[SEP]");

        Interpreter.Options options = new Interpreter.Options();
        options.setNumThreads(Math.max(1, Runtime.getRuntime().availableProcessors() / 2));
        try {
            options.setUseXNNPACK(false);
        } catch (Throwable ignored) {
        }
        ByteBuffer model = FileUtil.loadMappedFile(context, MODEL_PATH);
        interpreter = new Interpreter(model, options);
        Log.i(TAG, "Loaded SMS scam model with maxLength=" + maxLength + ", vocab=" + vocab.size());
    }

    public float classify(String text) {
        EncodedInput encoded = encode(text == null ? "" : text);
        float[][] probabilities = new float[1][2];

        try {
            Map<String, Object> signatureInputs = new HashMap<>();
            signatureInputs.put("input_ids", encoded.inputIds);
            signatureInputs.put("attention_mask", encoded.attentionMask);
            Map<String, Object> signatureOutputs = new HashMap<>();
            signatureOutputs.put("logits", new float[1][2]);
            signatureOutputs.put("probabilities", probabilities);
            interpreter.runSignature(signatureInputs, signatureOutputs, "serving_default");
        } catch (Throwable signatureError) {
            try {
                Object[] orderedInputs = orderedInputs(encoded);
                Map<Integer, Object> outputs = orderedOutputs(probabilities);
                interpreter.runForMultipleInputsOutputs(orderedInputs, outputs);
            } catch (Throwable fallbackError) {
                Log.e(TAG, "SMS scam inference failed", fallbackError);
                return 0f;
            }
        }
        return probabilities[0][1];
    }

    private Object[] orderedInputs(EncodedInput encoded) {
        int inputCount = interpreter.getInputTensorCount();
        Object[] inputs = new Object[inputCount];
        for (int i = 0; i < inputCount; i++) {
            String name = interpreter.getInputTensor(i).name().toLowerCase(Locale.US);
            if (name.contains("attention")) {
                inputs[i] = encoded.attentionMask;
            } else {
                inputs[i] = encoded.inputIds;
            }
        }
        return inputs;
    }

    private Map<Integer, Object> orderedOutputs(float[][] probabilities) {
        Map<Integer, Object> outputs = new HashMap<>();
        for (int i = 0; i < interpreter.getOutputTensorCount(); i++) {
            String name = interpreter.getOutputTensor(i).name().toLowerCase(Locale.US);
            if (name.contains("prob")) {
                outputs.put(i, probabilities);
            } else {
                outputs.put(i, new float[1][2]);
            }
        }
        if (!outputs.containsValue(probabilities) && interpreter.getOutputTensorCount() > 0) {
            outputs.put(0, probabilities);
        }
        return outputs;
    }

    private EncodedInput encode(String text) {
        int[][] inputIds = new int[1][maxLength];
        int[][] attentionMask = new int[1][maxLength];
        for (int i = 0; i < maxLength; i++) {
            inputIds[0][i] = padId;
        }

        List<Integer> ids = new ArrayList<>();
        ids.add(clsId);
        for (String token : basicTokenize(text)) {
            for (Integer id : wordPiece(token)) {
                ids.add(id);
                if (ids.size() >= maxLength - 1) {
                    break;
                }
            }
            if (ids.size() >= maxLength - 1) {
                break;
            }
        }
        ids.add(sepId);

        int limit = Math.min(ids.size(), maxLength);
        for (int i = 0; i < limit; i++) {
            inputIds[0][i] = ids.get(i);
            attentionMask[0][i] = 1;
        }
        return new EncodedInput(inputIds, attentionMask);
    }

    private List<String> basicTokenize(String text) {
        String normalized = text.toLowerCase(Locale.US);
        List<String> tokens = new ArrayList<>();
        StringBuilder current = new StringBuilder();
        for (int i = 0; i < normalized.length(); i++) {
            char ch = normalized.charAt(i);
            if (Character.isLetterOrDigit(ch)) {
                current.append(ch);
            } else {
                flushToken(tokens, current);
                if (!Character.isWhitespace(ch)) {
                    tokens.add(String.valueOf(ch));
                }
            }
        }
        flushToken(tokens, current);
        return tokens;
    }

    private void flushToken(List<String> tokens, StringBuilder current) {
        if (current.length() > 0) {
            tokens.add(current.toString());
            current.setLength(0);
        }
    }

    private List<Integer> wordPiece(String token) {
        List<Integer> pieces = new ArrayList<>();
        if (token.length() > 100) {
            pieces.add(unkId);
            return pieces;
        }

        int start = 0;
        boolean failed = false;
        while (start < token.length()) {
            int end = token.length();
            String current = null;
            while (start < end) {
                String sub = token.substring(start, end);
                if (start > 0) {
                    sub = "##" + sub;
                }
                if (vocab.containsKey(sub)) {
                    current = sub;
                    break;
                }
                end--;
            }
            if (current == null) {
                failed = true;
                break;
            }
            pieces.add(vocab.get(current));
            start = end;
        }

        if (failed) {
            pieces.clear();
            pieces.add(unkId);
        }
        return pieces;
    }

    private Map<String, Integer> loadVocab(AssetManager assets) throws Exception {
        Map<String, Integer> map = new HashMap<>();
        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(assets.open(VOCAB_PATH), StandardCharsets.UTF_8))) {
            String line;
            int index = 0;
            while ((line = reader.readLine()) != null) {
                map.put(line.trim(), index++);
            }
        }
        return map;
    }

    private int loadMaxLength(AssetManager assets) {
        try (InputStream input = assets.open(CONFIG_PATH)) {
            byte[] bytes = new byte[input.available()];
            int read = input.read(bytes);
            if (read > 0) {
                JSONObject json = new JSONObject(new String(bytes, StandardCharsets.UTF_8));
                return json.optInt("max_length", 128);
            }
        } catch (Exception e) {
            Log.w(TAG, "Failed to read SMS model config, using maxLength=128", e);
        }
        return 128;
    }

    private int getRequiredTokenId(String token) throws Exception {
        Integer id = vocab.get(token);
        if (id == null) {
            throw new Exception("Missing tokenizer token: " + token);
        }
        return id;
    }

    private static class EncodedInput {
        final int[][] inputIds;
        final int[][] attentionMask;

        EncodedInput(int[][] inputIds, int[][] attentionMask) {
            this.inputIds = inputIds;
            this.attentionMask = attentionMask;
        }
    }
}
