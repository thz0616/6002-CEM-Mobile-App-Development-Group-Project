import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import '../../data/repositories/llm_repository.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/settings_repository.dart';

class ChatModeScreen extends ConsumerStatefulWidget {
  const ChatModeScreen({super.key});

  @override
  ConsumerState<ChatModeScreen> createState() => _ChatModeScreenState();
}

class _ChatModeScreenState extends ConsumerState<ChatModeScreen> {
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();

  bool _isListening = false;
  bool _isSpeaking = false;
  bool _isThinking = false;
  bool _isPaused = false;

  String _currentStatus = 'Listening...';
  String _userText = '';
  String _history = '';
  Timer? _silenceTimer;

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _initTts();
  }

  void _resetSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(const Duration(seconds: 3), () {
      if (!_isPaused && !_isSpeaking && !_isThinking) {
        final text = _userText.trim();
        if (text.isNotEmpty) {
          _userText = '';
          _sendToLlm(text);
        }
      }
    });
  }

  Future<void> _initSpeech() async {
    bool available = await _speechToText.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (!_isSpeaking && !_isThinking && !_isPaused && mounted) {
            _startListening();
          }
        }
      },
      onError: (val) {
        if (mounted) {
          setState(() {
            // Ignore no match errors to avoid flashing scary errors
            if (val.errorMsg != 'error_no_match' &&
                val.errorMsg != 'error_speech_timeout' &&
                val.errorMsg != 'error_busy') {
              _currentStatus = 'Error: ${val.errorMsg}';
            }
          });

          if (val.errorMsg == 'error_busy' ||
              val.errorMsg == 'error_no_match' ||
              val.errorMsg == 'error_speech_timeout') {
            if (!_isPaused && mounted && !_isSpeaking && !_isThinking) {
              _startListening();
            }
          }
        }
      },
    );
    if (available && mounted) {
      _startListening();
    }
  }

  Future<void> _initTts() async {
    final settings = ref.read(settingsProvider);
    await _flutterTts.setLanguage(settings.preferredLanguage);
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    _flutterTts.setCancelHandler(() {
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });
      }
    });

    _flutterTts.setCompletionHandler(() {
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });
        if (!_isPaused && mounted) {
          _startListening();
        }
      }
    });
  }

  void _startListening() async {
    if (_isThinking || _isSpeaking || _isPaused) return;

    if (_speechToText.isListening) {
      await _speechToText.cancel();
    }

    // Slight pause to ensure cleanup but keeping tight enough to not drop audio
    await Future.delayed(const Duration(milliseconds: 100));

    if (!mounted || _isThinking || _isSpeaking || _isPaused) return;

    setState(() {
      _isListening = true;
      _currentStatus =
          _userText.isNotEmpty ? 'You: $_userText' : 'Listening...';
    });

    final settings = ref.read(settingsProvider);
    await _speechToText.listen(
      localeId: settings.preferredLanguage,
      onResult: (result) {
        if (!mounted || _isThinking || _isSpeaking || _isPaused) return;
        setState(() {
          _userText = result.recognizedWords;
          _currentStatus = 'You: $_userText';
        });
        _resetSilenceTimer();
      },
      listenMode: stt.ListenMode.dictation,
      cancelOnError: false,
    );
  }

  void _stopListening() async {
    _silenceTimer?.cancel();
    if (mounted) {
      setState(() {
        _isPaused = true;
        _currentStatus = 'Paused';
      });
    }
    await _speechToText.stop();
    if (mounted) {
      setState(() {
        _isListening = false;
      });
    }
  }

  void _togglePause() async {
    if (_isPaused) {
      setState(() => _isPaused = false);
      if (!_isSpeaking) _startListening();
    } else {
      if (mounted) {
        setState(() => _isPaused = true);
      }
      if (_isSpeaking) {
        await _flutterTts.stop();
        if (mounted) {
          setState(() => _isSpeaking = false);
        }
      }
      _stopListening();
    }
  }

  Future<void> _sendToLlm(String text) async {
    if (text.isEmpty || _isThinking) return;

    setState(() {
      _isListening = false;
      _isThinking = true;
      _history += 'You: $text\n\n';
      _currentStatus = 'Thinking...';
    });

    await _speechToText.stop();

    final llmRepo = ref.read(llmRepositoryProvider);
    final convRepo = ref.read(conversationRepositoryProvider);

    final prompt = convRepo.buildPromptForSend(text);
    await convRepo.appendUser(text);

    try {
      final response = await llmRepo.generate(prompt);
      await convRepo.appendAssistant(response);

      if (mounted) {
        setState(() {
          _isThinking = false;
          _isSpeaking = true;
          _history += 'Bot:\n$response\n\n';
          _currentStatus = '';
        });
        await _flutterTts.speak(response);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isThinking = false;
          _currentStatus = 'Error: $e';
        });
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) _startListening();
        });
      }
    }
  }

  @override
  void dispose() {
    _speechToText.cancel();
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? Colors.black : Colors.white;
    final appBarColor = isDark ? Colors.black : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final statusTextColor = isDark ? Colors.white70 : Colors.black54;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text('Chat Mode', style: TextStyle(color: textColor)),
        backgroundColor: appBarColor,
        iconTheme: IconThemeData(color: textColor),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_history.isNotEmpty)
                      Text(
                        _history,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 18,
                          height: 1.5,
                        ),
                      ),
                    if (_userText.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Text(
                          'You: $_userText',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 18,
                            height: 1.5,
                          ),
                        ),
                      ),
                    Text(
                      _currentStatus,
                      style: TextStyle(
                        color: statusTextColor,
                        fontSize: 18,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 32.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FloatingActionButton(
                    heroTag: 'pausePlayBtn',
                    backgroundColor: Colors.purple,
                    onPressed: _togglePause,
                    child: Icon(
                      _isPaused ? Icons.play_arrow : Icons.pause,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 32),
                  FloatingActionButton(
                    heroTag: 'endBtn',
                    backgroundColor: Colors.red,
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
