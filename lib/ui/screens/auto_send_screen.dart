import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/services/llm_service.dart';
import '../../core/utils/phone_number_utils.dart';

class AutoSendState {
  final bool isGemini;
  final String selectedLanguage;
  final String statusText;
  final String outputText;
  final bool isListening;
  final bool isRecording;

  AutoSendState({
    required this.isGemini,
    required this.selectedLanguage,
    required this.statusText,
    required this.outputText,
    required this.isListening,
    required this.isRecording,
  });

  AutoSendState copyWith({
    bool? isGemini,
    String? selectedLanguage,
    String? statusText,
    String? outputText,
    bool? isListening,
    bool? isRecording,
  }) {
    return AutoSendState(
      isGemini: isGemini ?? this.isGemini,
      selectedLanguage: selectedLanguage ?? this.selectedLanguage,
      statusText: statusText ?? this.statusText,
      outputText: outputText ?? this.outputText,
      isListening: isListening ?? this.isListening,
      isRecording: isRecording ?? this.isRecording,
    );
  }
}

class AutoSendNotifier extends StateNotifier<AutoSendState> {
  final LlmService _llmService = LlmService();
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  final AudioRecorder _audioRecorder = AudioRecorder();

  List<Map<String, dynamic>> _favoriteContacts = [];
  String? _recordingPath;

  AutoSendNotifier()
    : super(
        AutoSendState(
          isGemini: false,
          selectedLanguage: 'en',
          statusText: 'Ready',
          outputText: 'Transcription and AI response will appear here...',
          isListening: false,
          isRecording: false,
        ),
      ) {
    _initSpeech();
    _loadContacts();
  }

  Future<void> _initSpeech() async {
    await _speechToText.initialize();
  }

  Future<void> _loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final contactsJson = prefs.getString('saved_contacts');
    final favList = prefs.getStringList('favorite_contacts') ?? [];
    Set<String> favoriteNumbers = favList.toSet();

    if (contactsJson != null && contactsJson.isNotEmpty) {
      try {
        final List<dynamic> arr = jsonDecode(contactsJson);
        for (var obj in arr) {
          final String name = obj['name'] ?? '';
          final String number = obj['number'] ?? '';
          final String normalizedNum = normalizeNumber(number);

          if (name.isNotEmpty && favoriteNumbers.contains(normalizedNum)) {
            _favoriteContacts.add({'name': name, 'number': number});
          }
        }
      } catch (_) {}
    }
  }

  void toggleProvider(bool gemini) {
    state = state.copyWith(isGemini: gemini);
  }

  void selectLanguage(String langCode) {
    state = state.copyWith(selectedLanguage: langCode);
  }

  Future<void> startListeningOrRecording() async {
    if (state.isGemini) {
      if (await Permission.microphone.request().isGranted) {
        final directory = await getApplicationCacheDirectory();
        _recordingPath =
            '${directory.path}/gemini_audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1),
          path: _recordingPath!,
        );
        state = state.copyWith(isRecording: true, statusText: 'Recording...');
      }
    } else {
      if (await Permission.microphone.request().isGranted) {
        String localeId = 'en_US';
        switch (state.selectedLanguage) {
          case 'zh':
            localeId = 'zh_CN';
            break;
          case 'ms':
            localeId = 'ms_MY';
            break;
          case 'ta':
            localeId = 'ta_IN';
            break;
        }

        state = state.copyWith(
          isListening: true,
          statusText: 'Listening...',
          outputText: '',
        );

        await _speechToText.listen(
          onResult: (result) {
            if (result.finalResult) {
              _processOllama(result.recognizedWords);
            } else {
              state = state.copyWith(
                statusText: 'You: ${result.recognizedWords}',
              );
            }
          },
          localeId: localeId,
          listenMode: stt.ListenMode.dictation,
        );
      }
    }
  }

  Future<void> stopListeningOrRecording() async {
    if (state.isGemini) {
      if (state.isRecording) {
        await _audioRecorder.stop();
        state = state.copyWith(
          isRecording: false,
          statusText: 'Processing with Gemini...',
        );
        if (_recordingPath != null) {
          _processGemini(_recordingPath!);
        }
      }
    } else {
      if (state.isListening) {
        await _speechToText.stop();
        state = state.copyWith(isListening: false, statusText: 'Processing...');
      }
    }
  }

  Future<void> _processOllama(String transcription) async {
    state = state.copyWith(
      statusText: 'Thinking...',
      outputText: '=== Transcription ===\n$transcription\n\n',
    );

    final contactsList =
        _favoriteContacts.isEmpty
            ? "No favorite contacts available"
            : _favoriteContacts.map((c) => c['name']).join(', ');

    final prompt = '''USER SAID: "$transcription"
CONTACTS: $contactsList

Task: Extract contact and message from what user said above.
Rules:
1. Contact: ONLY from CONTACTS list (if unsure/missing → null)
2. Message: Remove ask/tell/message/remind, change he/she→you, keep time/date/details, SAME language as user
3. Output ONLY raw JSON: {"sendContact": "name or null", "sendMessage": "text"}

Now process the USER SAID above and output JSON:''';

    try {
      final llmResponse = await _llmService.generateOllama(prompt);
      _displayAndExecuteOutput(transcription, llmResponse);
    } catch (e) {
      state = state.copyWith(
        statusText: 'Error occurred',
        outputText: state.outputText + 'Error: $e',
      );
    }
  }

  Future<void> _processGemini(String audioPath) async {
    final contactsList =
        _favoriteContacts.isEmpty
            ? "No favorite contacts available"
            : _favoriteContacts.map((c) => c['name']).join(', ');

    final prompt =
        '''Listen to this audio and extract the message sending command.

Available favorite contacts: $contactsList

Task:
1. Transcribe the full audio exactly as spoken (detect language automatically)
2. Identify the contact name from the audio (MUST be from favorites list)
3. Extract and convert the message (Remove ask/tell, keep variables, same language as spoken).
Output JSON format:
{"transcription": "full audio transcription", "sendContact": "name or null", "sendMessage": "converted message"}''';

    try {
      final jsonResponse = await _llmService.generateGeminiFromAudio(
        audioPath,
        prompt,
      );

      final output = '=== Gemini Response ===\n$jsonResponse\n\n';

      try {
        final cleanedJson = _cleanJson(jsonResponse);
        final Map<String, dynamic> parsed = jsonDecode(cleanedJson);
        final transcription = parsed['transcription'] ?? '';
        _displayAndExecuteOutput(transcription, cleanedJson, rawOutput: output);
      } catch (_) {
        state = state.copyWith(
          statusText: 'Ready',
          outputText: output + '(Could not parse as JSON)',
        );
      }
    } catch (e) {
      state = state.copyWith(
        statusText: 'Error occurred',
        outputText: state.outputText + '\nError: $e',
      );
    }
  }

  String _cleanJson(String raw) {
    String cleaned = raw.trim();
    if (cleaned.startsWith('```json'))
      cleaned = cleaned.substring(7);
    else if (cleaned.startsWith('```'))
      cleaned = cleaned.substring(3);
    if (cleaned.endsWith('```'))
      cleaned = cleaned.substring(0, cleaned.length - 3);
    return cleaned.trim();
  }

  void _displayAndExecuteOutput(
    String transcription,
    String llmResponse, {
    String? rawOutput,
  }) {
    String output =
        rawOutput ??
        '=== Transcription ===\n$transcription\n\n=== AI Structured Output ===\n';
    try {
      final cleaned = _cleanJson(llmResponse);
      final json = jsonDecode(cleaned);
      final encoder = JsonEncoder.withIndent('  ');
      if (rawOutput == null) output += encoder.convert(json) + '\n\n';

      output += '=== Parsed Fields ===\n';
      final contact = json['sendContact']?.toString();
      final message = json['sendMessage']?.toString();
      output += 'Contact: ${contact ?? "null"}\nMessage: ${message ?? ""}\n';

      state = state.copyWith(outputText: output, statusText: 'Ready');

      if (contact == null || contact == 'null' || contact.trim().isEmpty) {
        // Should show dialog, handled in UI or through state if we wanted
      } else {
        if (message != null && message.trim().isNotEmpty) {
          final phone = _findPhoneNumberForContact(contact);
          if (phone != null) {
            _openWhatsApp(phone, message);
          }
        }
      }
    } catch (e) {
      state = state.copyWith(
        statusText: 'Ready',
        outputText:
            state.outputText + llmResponse + '\n\n(Could not parse as JSON)',
      );
    }
  }

  String? _findPhoneNumberForContact(String contactName) {
    for (var c in _favoriteContacts) {
      if (c['name'].toString().toLowerCase() ==
          contactName.toLowerCase().trim()) {
        return c['number'];
      }
    }
    return null;
  }

  Future<void> _openWhatsApp(String phoneNumber, String message) async {
    final wpNumber = standardizePhoneNumberForWhatsApp(phoneNumber);
    final encodedMessage = Uri.encodeComponent(message);
    final url = Uri.parse('https://wa.me/$wpNumber?text=$encodedMessage');

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}

final autoSendProvider = StateNotifierProvider<AutoSendNotifier, AutoSendState>(
  (ref) {
    return AutoSendNotifier();
  },
);

class AutoSendScreen extends ConsumerWidget {
  const AutoSendScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(autoSendProvider);
    final notifier = ref.read(autoSendProvider.notifier);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Auto Send Message',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('AI Provider', style: TextStyle(color: Colors.grey)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => notifier.toggleProvider(false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      color:
                          !state.isGemini
                              ? const Color(0xFF404040)
                              : const Color(0xFF2A2A2A),
                      child: Center(
                        child: Text(
                          'Ollama',
                          style: TextStyle(
                            color:
                                !state.isGemini ? Colors.green : Colors.white,
                            fontWeight:
                                !state.isGemini
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => notifier.toggleProvider(true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      color:
                          state.isGemini
                              ? const Color(0xFF404040)
                              : const Color(0xFF2A2A2A),
                      child: Center(
                        child: Text(
                          'Gemini',
                          style: TextStyle(
                            color: state.isGemini ? Colors.green : Colors.white,
                            fontWeight:
                                state.isGemini
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            if (!state.isGemini) ...[
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Select Language:',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _LangButton(
                    label: 'EN',
                    isSelected: state.selectedLanguage == 'en',
                    onTap: () => notifier.selectLanguage('en'),
                  ),
                  _LangButton(
                    label: '中文',
                    isSelected: state.selectedLanguage == 'zh',
                    onTap: () => notifier.selectLanguage('zh'),
                  ),
                  _LangButton(
                    label: 'BM',
                    isSelected: state.selectedLanguage == 'ms',
                    onTap: () => notifier.selectLanguage('ms'),
                  ),
                  _LangButton(
                    label: 'தமிழ்',
                    isSelected: state.selectedLanguage == 'ta',
                    onTap: () => notifier.selectLanguage('ta'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Selected: ${_getLanguageName(state.selectedLanguage)}',
                  style: const TextStyle(color: Colors.green),
                ),
              ),
              const SizedBox(height: 16),
            ] else ...[
              const SizedBox(height: 94), // Maintain rough height spacing
            ],

            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: const Color(0xFF1E1E1E),
                child: SingleChildScrollView(
                  child: Text(
                    state.outputText,
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),
            Text(state.statusText, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 16),

            GestureDetector(
              onTapDown: (_) => notifier.startListeningOrRecording(),
              onTapUp: (_) => notifier.stopListeningOrRecording(),
              onTapCancel: () => notifier.stopListeningOrRecording(),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.mic, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        (state.isListening || state.isRecording)
                            ? 'RELEASE TO STOP'
                            : 'HOLD TO SPEAK',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  String _getLanguageName(String code) {
    switch (code) {
      case 'zh':
        return '中文';
      case 'ms':
        return 'Bahasa Malaysia';
      case 'ta':
        return 'தமிழ்';
      default:
        return 'English';
    }
  }
}

class _LangButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _LangButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.green : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.green, width: 2),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.green,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
