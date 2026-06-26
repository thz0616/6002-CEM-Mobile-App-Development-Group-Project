import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/services/horn_detection_service.dart';
import '../../data/services/llm_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Horn Detection'),
            subtitle: const Text('Enable or disable horn detection service'),
            value: settings.hornEnabled,
            onChanged: (val) async {
              if (val) {
                var status = await Permission.microphone.request();
                var notifStatus = await Permission.notification.request();
                if (status.isGranted && (notifStatus.isGranted || notifStatus.isLimited)) {
                  bool started = await ref.read(hornDetectionServiceProvider).startDetection(windowSeconds: 1);
                  if (started) {
                    ref.read(settingsProvider.notifier).setHornEnabled(true);
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Failed to start horn detection service.')),
                      );
                    }
                  }
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Microphone and Notification permissions are required')),
                    );
                  }
                }
              } else {
                await ref.read(hornDetectionServiceProvider).stopDetection();
                ref.read(settingsProvider.notifier).setHornEnabled(false);
              }
            },
          ),
          SwitchListTile(
            title: const Text('Horn Probability Label'),
            value: settings.showHornProbability,
            onChanged: (val) => notifier.setShowHornProbability(val),
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('Text-to-Speech (TTS) Read Aloud'),
            subtitle: const Text('Enable voice output for summaries and chat messages'),
            value: settings.ttsEnabled,
            onChanged: (val) => notifier.setTtsEnabled(val),
          ),
          ListTile(
            title: const Text('Preferred Language'),
            subtitle: const Text('Language for voice narration & speech input'),
            trailing: DropdownButton<String>(
              value: settings.preferredLanguage,
              items: const [
                DropdownMenuItem(value: 'en-US', child: Text('English (US)')),
                DropdownMenuItem(value: 'zh-CN', child: Text('Chinese (Simplified)')),
                DropdownMenuItem(value: 'ms-MY', child: Text('Malay (Malaysia)')),
                DropdownMenuItem(value: 'ta-IN', child: Text('Tamil (India)')),
              ],
              onChanged: (val) {
                if (val != null) {
                  notifier.setPreferredLanguage(val);
                }
              },
            ),
          ),
          const Divider(),
          _GeminiKeyTile(settings: settings, ref: ref),
          const Divider(),
          _OpenFdaKeyTile(settings: settings, ref: ref),
          const Divider(),
          ListTile(
            title: const Text('Contacts Sync / Favorites'),
            subtitle: Text('${settings.savedContacts.length} contacts synced'),
            trailing: ElevatedButton(
              onPressed: () async {
                try {
                  await notifier.syncContacts();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Contacts synced successfully')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error syncing contacts: $e')),
                    );
                  }
                }
              },
              child: const Text('Sync'),
            ),
          ),
          ...settings.savedContacts.map((c) {
            final normalized = c.number.replaceAll(RegExp(r'[^0-9+]'), '');
            final isFav = settings.favoriteContacts.contains(normalized);
            return ListTile(
              title: Text(c.name.isEmpty ? 'Unknown' : c.name),
              subtitle: Text(c.number),
              trailing: IconButton(
                icon: Icon(isFav ? Icons.star : Icons.star_border),
                color: isFav ? Colors.amber : null,
                onPressed: () => notifier.toggleFavorite(c.number),
              ),
            );
          }),
        ],
      ),
    );
  }

}

// ─── Gemini Key Tile ─────────────────────────────────────────

class _GeminiKeyTile extends ConsumerStatefulWidget {
  final SettingsState settings;
  final WidgetRef ref;

  const _GeminiKeyTile({required this.settings, required this.ref});

  @override
  ConsumerState<_GeminiKeyTile> createState() => _GeminiKeyTileState();
}

class _GeminiKeyTileState extends ConsumerState<_GeminiKeyTile> {
  bool _testing = false;
  String? _testResult; // null = untested, '' = ok, else error msg

  String get _maskedKey {
    final k = widget.settings.geminiApiKey;
    if (k.isEmpty) return 'Not set';
    if (k.length <= 8) return '${k.substring(0, 2)}****';
    return '${k.substring(0, 6)}…${k.substring(k.length - 4)}';
  }

  Future<void> _testKey() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      await LlmService().generateGeminiText(
        'Reply with the single word: OK',
        forceJson: false,
      );
      if (mounted) setState(() => _testResult = '');
    } catch (e) {
      if (mounted) {
        setState(() => _testResult = e.toString());
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _editKey() {
    final ctrl = TextEditingController(
        text: widget.settings.geminiApiKey);
    bool obscure = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Gemini API Key'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Helper link
              GestureDetector(
                onTap: () => launchUrl(
                  Uri.parse('https://aistudio.google.com/app/apikey'),
                  mode: LaunchMode.externalApplication,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.open_in_new,
                        size: 14, color: Colors.blue),
                    const SizedBox(width: 4),
                    const Text(
                      'Get key at aistudio.google.com',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue,
                          decoration: TextDecoration.underline),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                obscureText: obscure,
                decoration: InputDecoration(
                  hintText: 'AIza…',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(obscure
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded),
                    onPressed: () => setDlg(() => obscure = !obscure),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Make sure "Generative Language API" is enabled for this key in Google Cloud Console.',
                style: TextStyle(
                    fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                widget.ref
                    .read(settingsProvider.notifier)
                    .setGeminiApiKey(ctrl.text.trim());
                setState(() => _testResult = null);
                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasKey = widget.settings.geminiApiKey.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: const Icon(Icons.key_rounded),
          title: const Text('Gemini API Key'),
          subtitle: Text(_maskedKey,
              style: TextStyle(
                  fontFamily: 'monospace',
                  color: hasKey
                      ? Colors.green.shade700
                      : Colors.red.shade400)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Test button
              if (hasKey)
                _testing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        icon: Icon(
                          _testResult == null
                              ? Icons.science_rounded
                              : _testResult!.isEmpty
                                  ? Icons.check_circle_rounded
                                  : Icons.cancel_rounded,
                          color: _testResult == null
                              ? Colors.grey
                              : _testResult!.isEmpty
                                  ? Colors.green
                                  : Colors.red,
                        ),
                        tooltip: 'Test key',
                        onPressed: _testKey,
                      ),
              IconButton(
                icon: const Icon(Icons.edit_rounded),
                tooltip: 'Edit key',
                onPressed: _editKey,
              ),
            ],
          ),
        ),
        // Test result banner
        if (_testResult != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _testResult!.isEmpty
                    ? Colors.green.shade50
                    : Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _testResult!.isEmpty
                      ? Colors.green.shade300
                      : Colors.red.shade300,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _testResult!.isEmpty
                        ? Icons.check_circle_rounded
                        : Icons.error_outline_rounded,
                    size: 16,
                    color: _testResult!.isEmpty
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _testResult!.isEmpty
                          ? 'API key is valid ✓'
                          : _testResult!.contains('API_KEY_INVALID') ||
                                  _testResult!.contains('not valid')
                              ? 'Invalid key — please check you copied the full key from Google AI Studio.'
                              : _testResult!,
                      style: TextStyle(
                        fontSize: 12,
                        color: _testResult!.isEmpty
                            ? Colors.green.shade800
                            : Colors.red.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ─── OpenFDA Key Tile ─────────────────────────────────────────

class _OpenFdaKeyTile extends ConsumerStatefulWidget {
  final SettingsState settings;
  final WidgetRef ref;

  const _OpenFdaKeyTile({required this.settings, required this.ref});

  @override
  ConsumerState<_OpenFdaKeyTile> createState() => _OpenFdaKeyTileState();
}

class _OpenFdaKeyTileState extends ConsumerState<_OpenFdaKeyTile> {
  bool _testing = false;
  String? _testResult; // null = untested, '' = ok, else error msg

  String get _maskedKey {
    final k = widget.settings.openFdaApiKey;
    if (k.isEmpty) return 'Not set';
    if (k.length <= 8) return '${k.substring(0, 2)}****';
    return '${k.substring(0, 6)}…${k.substring(k.length - 4)}';
  }

  Future<void> _testKey() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final url = Uri.parse('https://api.fda.gov/drug/label.json?api_key=${widget.settings.openFdaApiKey}&limit=1');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        if (mounted) setState(() => _testResult = '');
      } else {
        if (mounted) setState(() => _testResult = 'Error: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _testResult = e.toString());
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _editKey() {
    final ctrl = TextEditingController(text: widget.settings.openFdaApiKey);
    bool obscure = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('OpenFDA API Key'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => launchUrl(
                  Uri.parse('https://open.fda.gov/apis/authentication/'),
                  mode: LaunchMode.externalApplication,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.open_in_new, size: 14, color: Colors.blue),
                    const SizedBox(width: 4),
                    const Text(
                      'Get key at open.fda.gov',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue,
                          decoration: TextDecoration.underline),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                obscureText: obscure,
                decoration: InputDecoration(
                  hintText: 'Enter OpenFDA API Key',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(obscure
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded),
                    onPressed: () => setDlg(() => obscure = !obscure),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                widget.ref
                    .read(settingsProvider.notifier)
                    .setOpenFdaApiKey(ctrl.text.trim());
                setState(() => _testResult = null);
                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasKey = widget.settings.openFdaApiKey.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: const Icon(Icons.medical_services_rounded),
          title: const Text('OpenFDA API Key'),
          subtitle: Text(_maskedKey,
              style: TextStyle(
                  fontFamily: 'monospace',
                  color: hasKey
                      ? Colors.green.shade700
                      : Colors.red.shade400)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasKey)
                _testing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        icon: Icon(
                          _testResult == null
                              ? Icons.science_rounded
                              : _testResult!.isEmpty
                                  ? Icons.check_circle_rounded
                                  : Icons.cancel_rounded,
                          color: _testResult == null
                              ? Colors.grey
                              : _testResult!.isEmpty
                                  ? Colors.green
                                  : Colors.red,
                        ),
                        tooltip: 'Test key',
                        onPressed: _testKey,
                      ),
              IconButton(
                icon: const Icon(Icons.edit_rounded),
                tooltip: 'Edit key',
                onPressed: _editKey,
              ),
            ],
          ),
        ),
        if (_testResult != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _testResult!.isEmpty
                    ? Colors.green.shade50
                    : Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _testResult!.isEmpty
                      ? Colors.green.shade300
                      : Colors.red.shade300,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _testResult!.isEmpty
                        ? Icons.check_circle_rounded
                        : Icons.error_outline_rounded,
                    size: 16,
                    color: _testResult!.isEmpty
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _testResult!.isEmpty
                          ? 'OpenFDA key is valid ✓'
                          : _testResult!,
                      style: TextStyle(
                        fontSize: 12,
                        color: _testResult!.isEmpty
                            ? Colors.green.shade800
                            : Colors.red.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

