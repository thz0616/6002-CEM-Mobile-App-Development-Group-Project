import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LlmService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 120),
  ));

  /// Tries compatible Gemini model/version pairs to avoid hard-failing when a
  /// specific model alias is unavailable for the current API key/project.
  Future<Response<dynamic>> _postGeminiGenerateContent({
    required String apiKey,
    required Map<String, dynamic> data,
    List<String>? preferredModels,
  }) async {
    final models = preferredModels ??
        const [
          // 'gemini-1.5-flash',
          // 'gemini-1.5-flash-latest',
          // 'gemini-1.5-flash-002',
          'gemini-2.5-flash',
          'gemini-2.0-flash',
        ];
    const versions = ['v1beta', 'v1'];

    DioException? lastError;
    for (final version in versions) {
      for (final model in models) {
        try {
          return await _dio.post(
            'https://generativelanguage.googleapis.com/$version/models/$model:generateContent?key=$apiKey',
            data: data,
          );
        } on DioException catch (e) {
          lastError = e;
          final status = e.response?.statusCode;
          final body = e.response?.data?.toString() ?? '';
          final isUnsupported = status == 404 ||
              body.contains('not found for API version') ||
              body.contains('is not supported for generateContent');
          if (isUnsupported) {
            continue;
          }
          rethrow;
        }
      }
    }
    throw lastError ??
        Exception('No compatible Gemini model found for this API key.');
  }

  Future<String> generateOllama(String prompt, {String? base64Image}) async {
    final prefs = await SharedPreferences.getInstance();
    const injectedModel = String.fromEnvironment('LLM_MODEL');
    final model = injectedModel.isNotEmpty
        ? injectedModel
        : 'gemma4:31b-cloud';

    // Check for injected HOST_IP from run.ps1, fallback to 10.0.2.2 (emulator)
    const String injectedIp = String.fromEnvironment('HOST_IP');
    final String defaultIp = injectedIp.isNotEmpty ? injectedIp : '10.0.2.2';

    // Default to the IP for local dev if not specified
    final baseUrl = prefs.getString('llm_base_url') ?? 'http://$defaultIp:11434';

    try {
      final response = await _dio.post(
        '$baseUrl/api/generate',
        data: {
          'model': model,
          'prompt': prompt,
          'stream': false,
          'think': false,
          if (base64Image != null) 'images': [base64Image],
        },
      );
      return response.data['response'] ?? '';
    } catch (e) {
      throw Exception('Ollama error: $e');
    }
  }

  /// Sends a text-only prompt to Gemini 1.5 Flash and returns the raw text
  /// response. Requests JSON output via [responseMimeType].
  Future<String> generateGeminiText(
    String prompt, {
    bool forceJson = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('gemini_api_key') ?? '';
    if (apiKey.isEmpty) {
      throw Exception('Gemini API key not set. Please add it in Settings.');
    }

    try {
      final response = await _postGeminiGenerateContent(
        apiKey: apiKey,
        data: {
          'contents': [
            {
              'parts': [
                {'text': prompt},
              ],
            },
          ],
          if (forceJson)
            'generationConfig': {'responseMimeType': 'application/json'},
        },
      );

      final candidates = response.data['candidates'] as List<dynamic>?;
      if (candidates != null && candidates.isNotEmpty) {
        final parts =
            candidates[0]['content']['parts'] as List<dynamic>?;
        if (parts != null && parts.isNotEmpty) {
          return parts[0]['text']?.toString() ?? '';
        }
      }
      throw Exception('Empty response from Gemini');
    } on DioException catch (e) {
      final msg = e.response?.data?.toString() ?? e.message;
      throw Exception('Gemini request failed: $msg');
    }
  }

  /// Sends a food photo + plan context to Gemini Vision and returns a
  /// JSON string with nutritional analysis and goal-alignment feedback.
  Future<String> analyzeFoodImage(
    String imagePath, {
    required String goalLabel,
    required String mealType,
    required String plannedMealName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('gemini_api_key') ?? '';
    if (apiKey.isEmpty) {
      throw Exception('Gemini API key not set. Please add it in Settings.');
    }

    final bytes = await File(imagePath).readAsBytes();
    final base64Image = base64Encode(bytes);
    final ext = imagePath.toLowerCase();
    final mimeType = ext.endsWith('.png') ? 'image/png' : 'image/jpeg';

    final prompt = '''
You are a professional nutritionist. Analyze the food in this image.

Context:
- User goal: {GOAL}
- Planned meal ({MEAL_TYPE}): {PLANNED_MEAL}

Instructions:
1. Identify the food(s) visible in the image.
2. Estimate realistic nutritional values for one serving.
3. Determine if the food aligns with the user's stated goal.
4. If it does NOT align, give a brief, encouraging reminder.

Return ONLY valid JSON (no markdown fences):
{
  "detected_food": "Name of the food detected",
  "calories": "XXX kcal",
  "protein": "XXg",
  "carbs": "XXg",
  "fibre": "Xg",
  "fat": "XXg",
  "aligns_with_goal": true,
  "feedback": "Short feedback message (max 2 sentences)"
}
'''
        .replaceAll('{GOAL}', goalLabel)
        .replaceAll('{MEAL_TYPE}', mealType)
        .replaceAll('{PLANNED_MEAL}', plannedMealName);

    try {
      final response = await _postGeminiGenerateContent(
        apiKey: apiKey,
        preferredModels: const ['gemini-2.5-flash'],
        data: {
          'contents': [
            {
              'parts': [
                {'text': prompt},
                {
                  'inline_data': {
                    'mime_type': mimeType,
                    'data': base64Image,
                  },
                },
              ],
            },
          ],
          'generationConfig': {'responseMimeType': 'application/json'},
        },
      );

      final candidates = response.data['candidates'] as List<dynamic>?;
      if (candidates != null && candidates.isNotEmpty) {
        final parts =
            candidates[0]['content']['parts'] as List<dynamic>?;
        if (parts != null && parts.isNotEmpty) {
          return parts[0]['text']?.toString() ?? '';
        }
      }
      throw Exception('Empty response from Gemini Vision');
    } on DioException catch (e) {
      final msg = e.response?.data?.toString() ?? e.message;
      throw Exception('Gemini Vision failed: $msg');
    }
  }

  /// Parses OCR-extracted text from food packaging using Gemini 2.0 Flash
  /// (text-only, no vision — saves quota vs image upload).
  /// [ocrText] is the raw text returned by ML Kit on-device OCR.
  Future<String> parseExpiryFromText(String ocrText) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('gemini_api_key') ?? '';
    if (apiKey.isEmpty) {
      throw Exception('Gemini API key not set. Please add it in Settings.');
    }

    final prompt = '''
You are a food expiry date parser. The following text was extracted from a food packaging label using OCR.

OCR text:
"""
$ocrText
"""

Tasks:
1. Find ALL date-like strings in the text (e.g. production date, manufacture date, best before, use by, expiry, bb, exp, mfg, pkg date, etc.)
2. Identify the product name and food category if mentioned.
3. Select the BEST expiry/best-before date using this rule:
   - Prefer dates labelled "expiry", "best before", "use by", "exp", "bb"
   - If multiple future dates exist and none are labelled, pick the LATEST future date
   - If all dates are in the past, still return the latest one
4. If no dates are found or the text is garbled/empty, set is_blurry to true and expiry_date to empty string.

Return ONLY valid JSON (no markdown fences):
{
  "product_name": "Product name or empty string if not found",
  "category": "One of: dairy, meat, bread, beverage, canned, frozen, produce, condiment, snack, other",
  "dates_found": ["date string as seen in text", "..."],
  "expiry_date": "YYYY-MM-DD or empty string if not found",
  "confidence": "high, medium, or low",
  "is_blurry": false
}
''';

    try {
      final response = await _postGeminiGenerateContent(
        apiKey: apiKey,
        preferredModels: const ['gemini-2.5-flash'],
        data: {
          'contents': [
            {
              'parts': [
                {'text': prompt},
              ],
            },
          ],
          'generationConfig': {'responseMimeType': 'application/json'},
        },
      );
      final candidates = response.data['candidates'] as List<dynamic>?;
      if (candidates != null && candidates.isNotEmpty) {
        final parts =
            candidates[0]['content']['parts'] as List<dynamic>?;
        if (parts != null && parts.isNotEmpty) {
          return parts[0]['text']?.toString() ?? '';
        }
      }
      throw Exception('Empty response from Gemini');
    } on DioException catch (e) {
      final msg = e.response?.data?.toString() ?? e.message;
      throw Exception('Gemini parse failed: $msg');
    }
  }

  /// Generates storage and handling advice for a food item using Gemini 2.0 Flash.
  Future<String> getStorageAdvice(
    String productName,
    String category,
    String expiryDateStr,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('gemini_api_key') ?? '';
    if (apiKey.isEmpty) {
      throw Exception('Gemini API key not set. Please add it in Settings.');
    }

    final prompt = '''
You are a food safety expert. Provide practical storage advice for the following food item.

Product: $productName
Category: $category
Expiry date: $expiryDateStr

Give 2-4 sentences of specific, practical advice covering:
- Where to store it (fridge, pantry, freezer, etc.)
- How to store it properly (container type, temperature, etc.)
- How long it keeps once opened
- Any special handling tips

Be concise and actionable. Do NOT use bullet points — write as flowing sentences.
''';

    try {
      final response = await _postGeminiGenerateContent(
        apiKey: apiKey,
        preferredModels: const ['gemini-2.5-flash'],
        data: {
          'contents': [
            {
              'parts': [
                {'text': prompt},
              ],
            },
          ],
        },
      );
      final candidates = response.data['candidates'] as List<dynamic>?;
      if (candidates != null && candidates.isNotEmpty) {
        final parts =
            candidates[0]['content']['parts'] as List<dynamic>?;
        if (parts != null && parts.isNotEmpty) {
          return parts[0]['text']?.toString() ?? '';
        }
      }
      return '';
    } on DioException catch (e) {
      final msg = e.response?.data?.toString() ?? e.message;
      throw Exception('Storage advice failed: $msg');
    }
  }

  /// Generates storage and handling advice for a food item using Ollama.
  Future<String> getStorageAdviceOllama(
    String productName,
    String category,
    String expiryDateStr,
  ) async {
    final prompt = '''
You are a food safety expert. Provide practical storage advice for the following food item.

Product: $productName
Category: $category
Expiry date: $expiryDateStr

Give 2-4 sentences of specific, practical advice covering:
- Where to store it (fridge, pantry, freezer, etc.)
- How to store it properly (container type, temperature, etc.)
- How long it keeps once opened
- Any special handling tips

Be concise and actionable. Do NOT use bullet points — write as flowing sentences.
''';

    try {
      return await generateOllama(prompt);
    } catch (e) {
      throw Exception('Ollama storage advice failed: $e');
    }
  }

  Future<String> generateGeminiFromAudio(
    String audioPath,
    String prompt,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('gemini_api_key') ?? '';
    if (apiKey.isEmpty) {
      throw Exception('Gemini API key not found in Settings');
    }

    final bytes = await File(audioPath).readAsBytes();
    final base64Audio = base64Encode(bytes);

    try {
      final response = await _postGeminiGenerateContent(
        apiKey: apiKey,
        data: {
          "contents": [
            {
              "parts": [
                {"text": prompt},
                {
                  "inlineData": {"mimeType": "audio/mp4", "data": base64Audio},
                },
              ],
            },
          ],
          "generationConfig": {"responseMimeType": "application/json"},
        },
      );

      final candidates = response.data['candidates'] as List<dynamic>?;
      if (candidates != null && candidates.isNotEmpty) {
        final content = candidates[0]['content'];
        final parts = content['parts'] as List<dynamic>?;
        if (parts != null && parts.isNotEmpty) {
          return parts[0]['text'];
        }
      }
      throw Exception('Empty response from Gemini');
    } catch (e) {
      throw Exception('Gemini error: $e');
    }
  }

  Map<String, dynamic> buildOllamaExtractionPayload(String rawText, {String modelName = 'llama3'}) {
    return {
      'model': modelName,
      'prompt': 'Extract medication_name, dosage, and frequency from: "$rawText". Return strictly as JSON.',
      'stream': false,
      'format': 'json',
    };
  }
  
  Map<String, dynamic> buildOllamaSimplificationPayload(String medicalText, {String modelName = 'llama3'}) {
    return {
      'model': modelName,
      'prompt': 'Summarize these drug interactions in simple language: "$medicalText"',
      'stream': false,
    };
  }

  Future<Map<String, String>> extractMedicationFromImageOllama(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final base64Image = base64Encode(bytes);

    final prompt = '''
You are a pharmacist assistant. Extract the medication details from this image of a medication label or bottle.

Return ONLY valid JSON with no markdown formatting:
{
  "name": "Name of the medication (generic or brand)",
  "dosage": "Dosage amount (e.g. 20mg, 500mg, etc.)",
  "frequency": "Frequency if listed (e.g. twice daily, as needed). Leave empty if not found."
}
''';

    final responseText = await generateOllama(prompt, base64Image: base64Image);
    
    try {
      final start = responseText.indexOf('{');
      final end = responseText.lastIndexOf('}');
      if (start != -1 && end != -1) {
        final jsonStr = responseText.substring(start, end + 1);
        final data = jsonDecode(jsonStr);
        return {
          'name': data['name']?.toString() ?? '',
          'dosage': data['dosage']?.toString() ?? '',
          'frequency': data['frequency']?.toString() ?? '',
        };
      }
    } catch (e) {
      // Ignore parse error
    }
    return {'name': '', 'dosage': '', 'frequency': ''};
  }
}
