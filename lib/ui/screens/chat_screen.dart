import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import '../../data/repositories/llm_repository.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/settings_repository.dart';
import 'chat_mode_screen.dart';

import 'dart:io';

class ChatMessage {
  final String text;
  final bool isUser;
  final String? imagePath;
  final bool hasReadAloud;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.imagePath,
    this.hasReadAloud = false,
  });
}

class ChatScreen extends ConsumerStatefulWidget {
  final String? initialImagePath;
  final String? initialExtractedText;
  final String? prefillSummary;

  const ChatScreen({
    super.key,
    this.initialImagePath,
    this.initialExtractedText,
    this.prefillSummary,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;

  final stt.SpeechToText _speechToText = stt.SpeechToText();
  bool _isListening = false;

  final List<String> _pendingImages = [];

  final FlutterTts _tts = FlutterTts();
  bool _ttsReady = false;
  String? _currentlySpeakingText;

  @override
  void initState() {
    super.initState();
    _initTts();
    if (widget.initialExtractedText != null) {
      _messages.add(
        ChatMessage(
          text: 'Extracted text: ${widget.initialExtractedText}',
          isUser: false,
          imagePath: widget.initialImagePath,
          hasReadAloud: true,
        ),
      );
      Future.microtask(() {
        ref
            .read(conversationRepositoryProvider)
            .appendUser(
              'I scanned an image with the following text: ${widget.initialExtractedText}. Please answer my future questions based on this text.',
            );
      });
    }
    if (widget.prefillSummary != null) {
      _messages.add(
        ChatMessage(
          text: 'Summary loaded:\n\n${widget.prefillSummary}',
          isUser: false,
        ),
      );
      Future.microtask(() {
        ref
            .read(conversationRepositoryProvider)
            .setInterpreterContext(widget.prefillSummary!);
      });
    }
  }

  Future<void> _initTts() async {
    final settings = ref.read(settingsProvider);
    await _tts.setLanguage(settings.preferredLanguage);
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _tts.setCompletionHandler(() {
      if (mounted) {
        setState(() => _currentlySpeakingText = null);
      }
    });
    if (mounted) setState(() => _ttsReady = true);
  }

  @override
  void dispose() {
    _tts.stop();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _speakText(String text) async {
    if (!_ttsReady || text.isEmpty) return;
    if (_currentlySpeakingText == text) {
      await _tts.stop();
      if (mounted) setState(() => _currentlySpeakingText = null);
      return;
    }
    // Strip markdown for cleaner speech
    final plain = text
        .replaceAll(RegExp(r'\*\*|__|\*|_|#+\s'), '')
        .replaceAll(RegExp(r'\[.*?\]\(.*?\)'), '')
        .trim();
    setState(() => _currentlySpeakingText = text);
    await _tts.speak(plain);
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speechToText.stop();
      setState(() => _isListening = false);
    } else {
      bool available = await _speechToText.initialize();
      if (available) {
        setState(() => _isListening = true);
        final settings = ref.read(settingsProvider);
        _speechToText.listen(
          localeId: settings.preferredLanguage,
          onResult: (result) {
            setState(() {
              _messageController.text = result.recognizedWords;
            });
          },
        );
      }
    }
  }

  void _showAttachmentDrawer() {
    showModalBottomSheet(
      context: context,
      builder:
          (context) => SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('Gallery'),
                  onTap: () async {
                    Navigator.pop(context);
                    final picked = await ImagePicker().pickImage(
                      source: ImageSource.gallery,
                    );
                    if (picked != null) {
                      setState(() {
                        _pendingImages.add(picked.path);
                      });
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.camera_alt),
                  title: const Text('Camera'),
                  onTap: () async {
                    Navigator.pop(context);
                    final picked = await ImagePicker().pickImage(
                      source: ImageSource.camera,
                    );
                    if (picked != null) {
                      setState(() {
                        _pendingImages.add(picked.path);
                      });
                    }
                  },
                ),
              ],
            ),
          ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if ((text.isEmpty && _pendingImages.isEmpty) || _isLoading) return;

    if (_isListening) await _toggleListening();

    _messageController.clear();
    final imagesToSend = List<String>.from(_pendingImages);
    setState(() {
      _pendingImages.clear();
      _messages.add(
        ChatMessage(
          text: text,
          isUser: true,
          imagePath: imagesToSend.isNotEmpty ? imagesToSend.first : null,
        ),
      );
      _isLoading = true;
    });
    _scrollToBottom();

    final llmRepo = ref.read(llmRepositoryProvider);
    final convRepo = ref.read(conversationRepositoryProvider);

    final prompt = convRepo.buildPromptForSend(text);
    await convRepo.appendUser(text);

    try {
      final response = await llmRepo.generate(
        prompt,
        imagePath: imagesToSend.isNotEmpty ? imagesToSend.first : null,
      );
      await convRepo.appendAssistant(response);

      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(text: response, isUser: false));
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(
            ChatMessage(text: "Error: ${e.toString()}", isUser: false),
          );
          _isLoading = false;
        });
        _scrollToBottom();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chatbot'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              await ref.read(conversationRepositoryProvider).clearAll();
              setState(() {
                _messages.clear();
              });
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Context cleared. Starting fresh!"),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return _MessageBubble(
                  message: message,
                  isTtsEnabled: settings.ttsEnabled,
                  isSpeaking: _currentlySpeakingText == message.text,
                  onReadAloud: () => _speakText(message.text),
                );
              },
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(),
            ),
          if (_pendingImages.isNotEmpty)
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _pendingImages.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(_pendingImages[index]),
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: -10,
                          right: -10,
                          child: IconButton(
                            icon: const Icon(Icons.cancel, color: Colors.red),
                            onPressed: () {
                              setState(() {
                                _pendingImages.removeAt(index);
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  offset: const Offset(0, -2),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  color: Colors.white,
                  onPressed: _showAttachmentDrawer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.mic),
                        color: _isListening ? Colors.red : Colors.grey,
                        onPressed: _toggleListening,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey.withOpacity(0.1),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                    ),
                    onChanged: (text) => setState(() {}),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor:
                      _messageController.text.isNotEmpty ||
                              _pendingImages.isNotEmpty
                          ? Colors.blue
                          : Colors.purple,
                  child: IconButton(
                    icon: Icon(
                      _messageController.text.isNotEmpty ||
                              _pendingImages.isNotEmpty
                          ? Icons.send
                          : Icons.chat,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      if (_messageController.text.isNotEmpty ||
                          _pendingImages.isNotEmpty) {
                        _sendMessage();
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ChatModeScreen(),
                          ),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isTtsEnabled;
  final bool isSpeaking;
  final VoidCallback onReadAloud;

  const _MessageBubble({
    required this.message,
    required this.isTtsEnabled,
    required this.isSpeaking,
    required this.onReadAloud,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.center,
        children: [
          if (message.imagePath != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0, top: 16.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(message.imagePath!),
                  width: MediaQuery.of(context).size.width * 0.8,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          Align(
            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              decoration: BoxDecoration(
                color: isUser ? Colors.grey.shade800 : Colors.grey.shade400,
                borderRadius: BorderRadius.circular(16),
              ),
              child:
                  isUser
                      ? Text(
                        message.text,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      )
                      : MarkdownBody(
                        data: message.text,
                        styleSheet: MarkdownStyleSheet(
                          p: const TextStyle(
                            color: Colors.black87,
                            fontSize: 16,
                          ),
                          h1: const TextStyle(
                            color: Colors.black87,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                          h2: const TextStyle(
                            color: Colors.black87,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                          h3: const TextStyle(
                            color: Colors.black87,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          listBullet: const TextStyle(
                            color: Colors.black87,
                            fontSize: 16,
                          ),
                          code: TextStyle(
                            backgroundColor: Colors.grey.shade300,
                            color: Colors.black87,
                            fontFamily: 'monospace',
                          ),
                          codeblockDecoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
            ),
          ),
          if (isTtsEnabled && (!isUser || message.hasReadAloud))
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE53935), // Red button
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                onPressed: onReadAloud,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 12.0,
                  ),
                  child: Text(
                    isSpeaking ? 'STOP' : 'READ ALOUD',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
