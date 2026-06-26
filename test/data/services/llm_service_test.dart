import 'package:flutter_test/flutter_test.dart';
import 'package:androidtestllm_flutter/data/services/llm_service.dart';

void main() {
  test('LlmService constructs correct extraction payload for Ollama', () {
    final service = LlmService();
    final payload = service.buildOllamaExtractionPayload('Take one Aspirin 81 mg daily');
    
    expect(payload['model'], isNotEmpty);
    expect(payload['prompt'], contains('Aspirin'));
    expect(payload['format'], 'json');
  });
}