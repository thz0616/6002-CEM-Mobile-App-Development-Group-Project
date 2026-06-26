import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../providers/calendar_sync_provider.dart';

class ScanToCalendarScreen extends ConsumerStatefulWidget {
  const ScanToCalendarScreen({super.key});

  @override
  ConsumerState<ScanToCalendarScreen> createState() => _ScanToCalendarScreenState();
}

class _ScanToCalendarScreenState extends ConsumerState<ScanToCalendarScreen> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  String _lastWords = '';
  bool _listening = false;

  Future<void> _pickImage(ImageSource src) async {
    await ref.read(calendarSyncProvider.notifier).syncFromImage(src);
  }

  Future<void> _recordVoice() async {
    if (!_listening) {
      final available = await _speech.initialize();
      if (!available) return;
      setState(() => _listening = true);
      _speech.listen(onResult: (r) {
        setState(() => _lastWords = r.recognizedWords);
      });
    } else {
      _speech.stop();
      setState(() => _listening = false);
      if (_lastWords.trim().isNotEmpty) {
        await ref.read(calendarSyncProvider.notifier).syncFromAudio(_lastWords);
        setState(() => _lastWords = '');
      }
    }
  }

  Future<void> _enterTextManually() async {
    final txt = await showDialog<String?>(
      context: context,
      builder: (c) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Enter event text'),
          content: TextField(controller: controller, maxLines: 4),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(c, controller.text), child: const Text('OK')),
          ],
        );
      },
    );
    if (txt != null && txt.trim().isNotEmpty) {
      await ref.read(calendarSyncProvider.notifier).syncFromAudio(txt);
    }
  }

  Widget _buildActionCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool isPulsing = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: isPulsing ? 1.0 : 0.4), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: isPulsing ? 0.3 : 0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: color.withValues(alpha: 0.5), size: 24),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(calendarSyncProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
        title: const Text('Scan to Calendar'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1976D2).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.event_available_rounded, color: Color(0xFF1976D2), size: 56),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'How would you like to capture the event?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            
            _buildActionCard(
              context: context,
              title: 'Take Photo',
              subtitle: 'Snap a flyer, card or invitation',
              icon: Icons.camera_alt_rounded,
              color: const Color(0xFF1976D2),
              onTap: () => _pickImage(ImageSource.camera),
            ),
            const SizedBox(height: 14),
            
            _buildActionCard(
              context: context,
              title: 'Upload Gallery',
              subtitle: 'Choose an existing image',
              icon: Icons.photo_library_rounded,
              color: const Color(0xFF8E24AA),
              onTap: () => _pickImage(ImageSource.gallery),
            ),
            const SizedBox(height: 14),
            
            _buildActionCard(
              context: context,
              title: _listening ? 'Stop & Process Voice' : 'Record Voice',
              subtitle: _listening ? 'Listening...' : 'Speak the event details',
              icon: _listening ? Icons.mic : Icons.mic_none_rounded,
              color: _listening ? const Color(0xFFE53935) : const Color(0xFFF57C00),
              isPulsing: _listening,
              onTap: _recordVoice,
            ),
            const SizedBox(height: 14),
            
            _buildActionCard(
              context: context,
              title: 'Enter Text Manually',
              subtitle: 'Type or paste event info manually',
              icon: Icons.edit_note_rounded,
              color: const Color(0xFF00897B),
              onTap: _enterTextManually,
            ),
            
            const SizedBox(height: 32),
            
            if (state.isLoading) ...[
               const Center(child: CircularProgressIndicator()),
               const SizedBox(height: 16),
               const Center(
                 child: Text('AI is extracting details...', style: TextStyle(color: Colors.grey)),
               ),
            ],
            
            if (state.hasError) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 12),
                    Expanded(child: Text('${state.error}', style: const TextStyle(color: Colors.red))),
                  ],
                ),
              ),
            ],
            
            if (_lastWords.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text('Transcript:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_lastWords, style: const TextStyle(fontStyle: FontStyle.italic)),
              ),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }
}
