import 'dart:convert';
import 'dart:io';

import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/services/llm_service.dart';

final calendarSyncProvider =
    StateNotifierProvider<CalendarSyncNotifier, AsyncValue<void>>((ref) {
  return CalendarSyncNotifier();
});

class CalendarSyncNotifier extends StateNotifier<AsyncValue<void>> {
  CalendarSyncNotifier() : super(const AsyncData(null));

  final LlmService _llmService = LlmService();
  final ImagePicker _imagePicker = ImagePicker();

  Future<void> syncFromImage(ImageSource source) async {
    state = const AsyncLoading();
    try {
      final XFile? image = await _imagePicker.pickImage(source: source);
      if (image == null) {
        state = const AsyncData(null);
        return;
      }

      final bytes = await File(image.path).readAsBytes();
      final base64Image = base64Encode(bytes);

      await _processWithOllama(
        imageOrTextPrompt: 'Analyze the provided image and extract event details.',
        base64Image: base64Image,
      );
    } catch (e, st) {
      print('Calendar Sync Error: $e\n$st');
      state = AsyncError(e, st);
    }
  }

  Future<void> syncFromAudio(String text) async {
    if (text.trim().isEmpty) return;

    state = const AsyncLoading();
    try {
      await _processWithOllama(
        imageOrTextPrompt: 'Analyze the following text and extract event details:\n\n$text',
      );
    } catch (e, st) {
      print('Calendar Sync Error: $e\n$st');
      state = AsyncError(e, st);
    }
  }

  Future<void> _processWithOllama({
    required String imageOrTextPrompt,
    String? base64Image,
  }) async {
    final now = DateTime.now();
    final prompt = '''
The current date and time is: ${now.toIso8601String()}.
$imageOrTextPrompt

Reply ONLY with a valid JSON document containing these exact keys:
- "title": event name (string)
- "startDate": ISO-8601 string combined date and time
- "endDate": ISO-8601 string combined date and time
- "location": event location (string, or empty string if none)
- "notes": extra description (string, or empty string if none)
''';

    print('Sent prompt to Ollama, waiting for response...');
    final result = await _llmService.generateOllama(
      prompt,
      base64Image: base64Image,
    );
    print('Raw Ollama Response:\n$result');

    // Robustly extract JSON block
    final int start = result.indexOf('{');
    final int end = result.lastIndexOf('}');
    if (start == -1 || end == -1) {
      throw Exception('Could not find JSON object in LLM response: $result');
    }
    
    final String jsonString = result.substring(start, end + 1);
    final Map<String, dynamic> data = jsonDecode(jsonString);

    final title = data['title'] as String? ?? 'New Event';
    final startDateStr = data['startDate'] as String?;
    final endDateStr = data['endDate'] as String?;
    final location = data['location'] as String? ?? '';
    final notes = data['notes'] as String? ?? '';

    DateTime startDate = now;
    if (startDateStr != null) {
      startDate = DateTime.tryParse(startDateStr) ?? now;
    }

    DateTime endDate = startDate.add(const Duration(hours: 1));
    if (endDateStr != null) {
      endDate = DateTime.tryParse(endDateStr) ?? endDate;
    }

    final Event event = Event(
      title: title,
      description: notes,
      location: location,
      startDate: startDate,
      endDate: endDate,
    );

    // Trigger Add2Calendar intent
    final success = await Add2Calendar.addEvent2Cal(event);
    if (!success) {
      throw Exception('Failed to open calendar app (Add2Calendar returned false). Check package visibility or if a calendar app is installed.');
    }

    state = const AsyncData(null);
  }
}
