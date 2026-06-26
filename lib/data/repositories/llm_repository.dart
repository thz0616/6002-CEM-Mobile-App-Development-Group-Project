import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/utils/network_utils.dart';
import '../../domain/repositories/i_llm_repository.dart';

final llmRepositoryProvider = Provider((ref) => LlmRepository());

class LlmRepository implements ILLMRepository {
  final Dio _dio;
  String _model = const String.fromEnvironment(
    'LLM_MODEL',
    defaultValue: 'gemma4:31b-cloud',
  );

  LlmRepository({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(minutes: 5),
              sendTimeout: const Duration(seconds: 180),
            ),
          );

  String get model => _model;

  void setModel(String model) {
    _model = model;
  }

  @override
  Future<String> generate(
    String prompt, {
    String? system,
    String? imagePath,
  }) async {
    final baseUrl = await NetworkUtils.getLlmBaseUrl();

    final body = {
      'model': _model,
      'prompt': prompt,
      'stream': false,
      'think': false,
    };

    if (system != null && system.isNotEmpty) {
      body['system'] = system;
    }

    if (imagePath != null && imagePath.isNotEmpty) {
      final file = File(imagePath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        final base64Image = base64Encode(bytes);
        body['images'] = [base64Image];
      }
    }

    try {
      final response = await _dio.post('$baseUrl/api/generate', data: body);

      return _parseResponse(response);
    } on DioException catch (e) {
      final msg = e.response?.data != null
          ? e.response?.data.toString()
          : e.message;
      throw Exception('Failed to generate text ($msg)');
    } catch (e) {
      throw Exception('Failed to generate text: $e');
    }
  }

  Future<String> generateWithImages(
    String prompt,
    List<String> base64Images, {
    String? system,
  }) async {
    final baseUrl = await NetworkUtils.getLlmBaseUrl();

    final body = {
      'model': _model,
      'prompt': prompt,
      'stream': false,
      'think': false,
      if (base64Images.isNotEmpty) 'images': base64Images,
    };

    if (system != null && system.isNotEmpty) {
      body['system'] = system;
    }

    try {
      final response = await _dio.post('$baseUrl/api/generate', data: body);

      return _parseResponse(response);
    } on DioException catch (e) {
      throw Exception(_friendlyDioMessage(e, baseUrl));
    } catch (e) {
      throw Exception('Screenshot analysis failed: $e');
    }
  }

  Future<String> generateWithImagesStreaming(
    String prompt,
    List<String> base64Images, {
    String? system,
    bool enableThinkingDebug = false,
    void Function(String chunk, String fullText)? onProgress,
    void Function(String chunk, String fullText)? onThinkingProgress,
    void Function(String status)? onStatus,
  }) async {
    final baseUrl = await NetworkUtils.getLlmBaseUrl();

    final body = {
      'model': _model,
      'prompt': prompt,
      'stream': true,
      'think': enableThinkingDebug,
      if (base64Images.isNotEmpty) 'images': base64Images,
    };

    if (system != null && system.isNotEmpty) {
      body['system'] = system;
    }

    try {
      onStatus?.call('Checking Ollama at $baseUrl...');
      await _verifyOllama(baseUrl);
      onStatus?.call('Connected to Ollama. Model $_model is available.');

      final response = await _dio.post<ResponseBody>(
        '$baseUrl/api/generate',
        data: body,
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(minutes: 10),
        ),
      );

      final responseBody = response.data;
      if (responseBody == null) {
        throw const FormatException('Ollama returned an empty stream');
      }

      final fullText = StringBuffer();
      final fullThinking = StringBuffer();
      await for (final line
          in utf8.decoder.bind(responseBody.stream).transform(
            const LineSplitter(),
          )) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) {
          continue;
        }

        final chunk = _parseStreamChunk(trimmed);
        if (chunk.thinking.isNotEmpty) {
          fullThinking.write(chunk.thinking);
          onThinkingProgress?.call(
            chunk.thinking,
            fullThinking.toString(),
          );
        }
        if (chunk.response.isNotEmpty) {
          fullText.write(chunk.response);
          onProgress?.call(chunk.response, fullText.toString());
        }
      }

      return fullText.toString();
    } on DioException catch (e) {
      throw Exception(_friendlyDioMessage(e, baseUrl));
    } on FormatException catch (e) {
      throw Exception('Screenshot analysis failed: ${e.message}');
    } catch (e) {
      throw Exception('Screenshot analysis failed: $e');
    }
  }

  Future<void> _verifyOllama(String baseUrl) async {
    if (_isCloudModel(_model)) {
      await _probeCloudModel(baseUrl);
      return;
    }

    final response = await _dio.get('$baseUrl/api/tags');
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Ollama returned an invalid model list');
    }

    final models = data['models'];
    final modelNames = models is List
        ? models
              .whereType<Map>()
              .map((model) => model['name']?.toString())
              .whereType<String>()
              .toSet()
        : <String>{};
    if (!modelNames.contains(_model)) {
      throw FormatException(
        'The Ollama model "$_model" is not installed on this computer.',
      );
    }
  }

  Future<void> _probeCloudModel(String baseUrl) async {
    final response = await _dio.post(
      '$baseUrl/api/generate',
      data: {
        'model': _model,
        'prompt': 'Reply with OK only.',
        'stream': false,
        'think': false,
      },
    );
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Ollama returned an invalid cloud response');
    }
    final error = data['error']?.toString();
    if (error != null && error.isNotEmpty) {
      throw FormatException(error);
    }
  }

  bool _isCloudModel(String model) {
    return model.endsWith('-cloud');
  }

  String _friendlyDioMessage(DioException error, String baseUrl) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.connectionError) {
      return 'Cannot connect to Ollama at $baseUrl. Make sure Ollama is running, then restart the app with .\\run.ps1.';
    }
    if (error.type == DioExceptionType.receiveTimeout) {
      return 'Ollama took too long to analyze the screenshot. Please try again.';
    }

    final statusCode = error.response?.statusCode;
    final responseBody = error.response?.data?.toString() ?? '';
    if (statusCode == 404 && responseBody.toLowerCase().contains('model')) {
      return 'The Ollama model "$_model" is not installed on this computer.';
    }
    return 'Ollama request failed${statusCode == null ? '' : ' (HTTP $statusCode)'}.';
  }

  _OllamaStreamChunk _parseStreamChunk(String line) {
    final data = jsonDecode(line);
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Ollama stream chunk is not valid JSON');
    }

    final error = data['error']?.toString();
    if (error != null && error.isNotEmpty) {
      throw FormatException(error);
    }

    return _OllamaStreamChunk(
      response: data['response']?.toString() ?? '',
      thinking: data['thinking']?.toString() ?? '',
    );
  }

  String _parseResponse(Response response) {
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.data}');
    }

    final data = response.data;
    if (data is Map<String, dynamic>) {
      return data['response']?.toString() ?? '';
    } else if (data is String) {
      // In case it comes back as a raw string not parsed by Dio
      return data;
    }
    return '';
  }
}

class _OllamaStreamChunk {
  final String response;
  final String thinking;

  const _OllamaStreamChunk({
    required this.response,
    required this.thinking,
  });
}
