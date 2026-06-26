import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as htmlParser;
import 'package:html/dom.dart' as htmlDom;

import '../../data/repositories/llm_repository.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/settings_repository.dart';
import 'chat_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Theme constants (matches the blue theme from Android)
// ─────────────────────────────────────────────────────────────────────────────
const _kBlue = Color(0xFF1E88E5);
const _kDarkBg = Color(0xFF121212);
const _kCardBg = Color(0xFF1E1E2E);
const _kHeaderBg = Color(0xFF1A237E); // deep navy for section headers

// white with various opacities (const-safe hex values)
const _kWhite87 = Color(0xDEFFFFFF);
const _kWhite70 = Color(0xB3FFFFFF);
const _kWhite60 = Color(0x99FFFFFF);

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────
class SummarizerScreen extends ConsumerStatefulWidget {
  const SummarizerScreen({super.key});

  @override
  ConsumerState<SummarizerScreen> createState() => _SummarizerScreenState();
}

class _SummarizerScreenState extends ConsumerState<SummarizerScreen>
    with TickerProviderStateMixin {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  bool _isLoading = false;
  bool _hasResult = false;
  String _originalContent = '';
  String _summaryContent = '';
  String _errorMessage = '';

  // TTS
  final FlutterTts _tts = FlutterTts();
  bool _ttsReady = false;
  bool _isSpeaking = false;

  // Animation for the result section
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _initTts();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
  }

  Future<void> _initTts() async {
    final settings = ref.read(settingsProvider);
    await _tts.setLanguage(settings.preferredLanguage);
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _isSpeaking = false);
    });
    if (mounted) setState(() => _ttsReady = true);
  }

  @override
  void dispose() {
    _tts.stop();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _systemPrompt() {
    return 'ROLE: Digital Content Interpreter for seniors.\n'
        'GOAL: Convert complex or long text into a direct, easy-to-understand summary.\n'
        'STYLE:\n'
        '- Use plain, short sentences.\n'
        '- Be direct. Do NOT ask questions, propose options, or chat.\n'
        '- No greetings, no meta phrases.\n'
        '- Prefer bullet points.\n'
        'OUTPUT FORMAT ONLY:\n'
        '- One-sentence Overview.\n'
        '- Key Points: 3-7 bullet points.\n'
        '- Next Steps (if applicable): numbered list, simple actions.\n'
        'CONSTRAINTS: No emojis, no disclaimers, no extra commentary.';
  }

  String _stripThinking(String s) {
    return s
        .replaceAll(
            RegExp(r'<think>.*?</think>',
                caseSensitive: false, dotAll: true),
            '')
        .replaceAll(
            RegExp(r'<\s*think\s*>.*?<\s*/\s*think\s*>',
                caseSensitive: false, dotAll: true),
            '')
        .trim();
  }

  String _formatMarkdown(String s) {
    if (s.isEmpty) return s;
    // Remove stray double-stars
    s = s.replaceAll('**', '');
    // Section headers
    s = s.replaceAll(RegExp(r'\s*(Overview:)', caseSensitive: false), '\n\n**Overview:**\n');
    s = s.replaceAll(RegExp(r'\s*(Key Points:)', caseSensitive: false), '\n\n**Key Points:**\n');
    s = s.replaceAll(RegExp(r'\s*(Next Steps:)', caseSensitive: false), '\n\n**Next Steps:**\n');
    // Bullet points (no lookbehind - not supported in Dart RE2)
    s = s.replaceAll(RegExp(r'\s+\*\s+'), '\n* ');
    // Numbered lists
    s = s.replaceAll(RegExp(r'\s+(\d+\.)'), '\n\$1');
    // Collapse newlines
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return s.trim();
  }

  String _safeTrim(String s, int max) {
    if (s.length <= max) return s;
    return '${s.substring(0, max)}\n\n...[truncated]';
  }

  // ── HTML Fetching & Parsing ────────────────────────────────────────────────

  Future<String> _fetchHtml(String url) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
      },
    ));
    final response = await dio.get<String>(url,
        options: Options(responseType: ResponseType.plain));
    return response.data ?? '';
  }

  String _extractMainText(htmlDom.Document doc) {
    // Try to find <article> or <main>
    htmlDom.Element? main = doc.querySelector('article') ??
        doc.querySelector('main') ??
        doc.querySelector('[role="main"]');

    final root = main ?? doc.body;
    if (root == null) return doc.body?.text ?? '';

    final blocks = root.querySelectorAll('h1, h2, h3, p, li');
    final sb = StringBuffer();
    int charCount = 0;
    for (final el in blocks) {
      final tag = el.localName ?? '';
      final t = el.text.trim();
      if (t.isEmpty) continue;
      if (RegExp(r'h[1-3]').hasMatch(tag)) {
        sb.write('\n\n## $t\n');
      } else if (tag == 'li') {
        sb.write('\n- $t');
      } else {
        sb.write('\n$t');
      }
      charCount += t.length;
    }

    String out = sb.toString().trim();

    // Fallback if too short
    if (charCount < 400) {
      final paras = doc.body!.querySelectorAll('p, li');
      final sb2 = StringBuffer(out.isEmpty ? '' : '$out\n\n');
      int added = 0;
      for (final p in paras) {
        final t = p.text.trim();
        if (t.isEmpty) continue;
        sb2.write('$t\n');
        added += t.length;
        if (added > 3000) break;
      }
      out = sb2.toString().trim();
    }

    if (out.isEmpty) out = doc.body?.text ?? '';
    return out;
  }

  // ── Core Logic ─────────────────────────────────────────────────────────────

  Future<void> _onSummarize() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please paste a URL or some text first.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _hasResult = false;
      _originalContent = '';
      _summaryContent = '';
      _errorMessage = '';
    });

    final bool isUrl = text.toLowerCase().startsWith('http://') ||
        text.toLowerCase().startsWith('https://');

    try {
      if (isUrl) {
        await _summarizeUrl(text);
      } else {
        await _summarizeText(text);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error: ${e.toString()}';
          _isLoading = false;
          _hasResult = true;
        });
        _fadeCtrl.forward(from: 0);
      }
    }
  }

  Future<void> _summarizeUrl(String url) async {
    // Step 1: Fetch & parse HTML
    final html = await _fetchHtml(url);
    final doc = htmlParser.parse(html);
    final title = doc.head?.querySelector('title')?.text ?? '';
    final metaDesc = doc.head
            ?.querySelector("meta[name='description']")
            ?.attributes['content'] ??
        doc.head
            ?.querySelector("meta[property='og:description']")
            ?.attributes['content'] ??
        '';
    final bodyText = _extractMainText(doc);

    final sb = StringBuffer();
    if (title.isNotEmpty) sb.write('# $title\n');
    if (metaDesc.isNotEmpty) sb.write('\n$metaDesc\n\n');
    sb.write(bodyText);

    final original = _safeTrim(sb.toString(), 12000);

    if (mounted) {
      setState(() {
        _originalContent = original;
        _summaryContent = '*Summarizing...*';
        _hasResult = true;
        _isLoading = true;
      });
      _fadeCtrl.forward(from: 0);
      await Future.delayed(const Duration(milliseconds: 150));
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      }
    }

    // Step 2: Summarize via LLM
    final prompt =
        'Summarize the following content in simple steps for seniors. Keep it clear and short.\n\n$original';
    final llm = ref.read(llmRepositoryProvider);
    final conv = ref.read(conversationRepositoryProvider);
    final fullPrompt = conv.buildPromptForSend(prompt);

    final result = await llm.generate(fullPrompt, system: _systemPrompt());
    final clean = _formatMarkdown(_stripThinking(result));

    await conv.appendUser(
        'Summarize URL: ${url.substring(0, url.length.clamp(0, 150))}');
    await conv.appendAssistant(clean);

    if (mounted) {
      setState(() {
        _summaryContent = clean;
        _isLoading = false;
      });
    }
  }

  Future<void> _summarizeText(String text) async {
    if (mounted) {
      setState(() {
        _originalContent = text;
        _summaryContent = '*Summarizing...*';
        _hasResult = true;
        _isLoading = true;
      });
      _fadeCtrl.forward(from: 0);
    }

    final prompt =
        'Summarize the following text in simple steps for seniors. Keep it clear and short.\n\n$text';
    final llm = ref.read(llmRepositoryProvider);
    final conv = ref.read(conversationRepositoryProvider);
    final fullPrompt = conv.buildPromptForSend(prompt);

    final result = await llm.generate(fullPrompt, system: _systemPrompt());
    final clean = _formatMarkdown(_stripThinking(result));

    await conv.appendUser(
        'Summarize: ${text.substring(0, text.length.clamp(0, 200))}');
    await conv.appendAssistant(clean);

    if (mounted) {
      setState(() {
        _summaryContent = clean;
        _isLoading = false;
      });
    }
  }

  // ── TTS ────────────────────────────────────────────────────────────────────

  Future<void> _speakSummary() async {
    if (!_ttsReady || _summaryContent.isEmpty) return;
    if (_isSpeaking) {
      await _tts.stop();
      if (mounted) setState(() => _isSpeaking = false);
      return;
    }
    // Strip markdown for cleaner speech
    final plain = _summaryContent
        .replaceAll(RegExp(r'\*\*|__|\*|_|#+\s'), '')
        .replaceAll(RegExp(r'\[.*?\]\(.*?\)'), '')
        .trim();
    setState(() => _isSpeaking = true);
    await _tts.speak(plain);
  }

  // ── Chatbot handoff ────────────────────────────────────────────────────────

  void _sendToChatbot() {
    if (_summaryContent.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          prefillSummary: _summaryContent,
        ),
      ),
    );
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? _kDarkBg : Colors.grey[100],
      appBar: AppBar(
        backgroundColor: _kBlue,
        foregroundColor: Colors.white,
        title: const Text(
          'Content Summarizer',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
      ),
      body: CustomScrollView(
        controller: _scrollCtrl,
        slivers: [
          // ── Input section (always shown) ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: _InputCard(
                controller: _inputCtrl,
                isLoading: _isLoading,
                onSummarize: _onSummarize,
              ),
            ),
          ),

          // ── Error ──
          if (_errorMessage.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Color.fromARGB(153, 183, 28, 28),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _errorMessage,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),

          // ── Results ──
          if (_hasResult && _errorMessage.isEmpty) ...[
            SliverToBoxAdapter(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                  child: _ContentCard(
                    label: 'Original Content',
                    icon: Icons.article_outlined,
                    content: _originalContent,
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: _SummaryCard(
                    content: _summaryContent,
                    isLoading: _isLoading,
                  ),
                ),
              ),
            ),
          ],

          // ── Bottom action bar ──
          if (_hasResult && _errorMessage.isEmpty)
            SliverToBoxAdapter(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  child: _BottomBar(
                    isSpeaking: _isSpeaking,
                    onSpeak: _speakSummary,
                    onChatbot: _sendToChatbot,
                    disabled: _isLoading,
                    isTtsEnabled: settings.ttsEnabled,
                  ),
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Input Card
// ─────────────────────────────────────────────────────────────────────────────
class _InputCard extends StatelessWidget {
  final TextEditingController controller;
  final bool isLoading;
  final VoidCallback onSummarize;

  const _InputCard({
    required this.controller,
    required this.isLoading,
    required this.onSummarize,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? _kCardBg : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final hintColor = isDark ? const Color(0x61FFFFFF) : Colors.black38;
    final dividerColor = isDark ? const Color(0x1FFFFFFF) : Colors.grey[300]!;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color.fromARGB(128, 30, 136, 229), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color.fromARGB(38, 30, 136, 229),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Label
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Text(
              'Input',
              style: TextStyle(
                color: _kBlue,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ),
          // Text field
          TextField(
            controller: controller,
            maxLines: 5,
            minLines: 3,
            style: TextStyle(color: textColor, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Enter text or paste URL...',
              hintStyle: TextStyle(color: hintColor),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          Divider(color: dividerColor, height: 1),
          // Summarize button
          Padding(
            padding: const EdgeInsets.all(12),
            child: ElevatedButton.icon(
              onPressed: isLoading ? null : onSummarize,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kBlue,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Color.fromARGB(102, 30, 136, 229),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              icon: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome, size: 18),
              label: Text(
                isLoading ? 'SUMMARIZING...' : 'SUMMARIZE',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, letterSpacing: 1.2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Content Card (Original)
// ─────────────────────────────────────────────────────────────────────────────
class _ContentCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final String content;

  const _ContentCard({
    required this.label,
    required this.icon,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? _kCardBg : Colors.white;
    final borderColor = isDark ? const Color(0x1FFFFFFF) : Colors.grey[300]!;
    final textColor = isDark ? _kWhite87 : Colors.black87;
    final titleColor = isDark ? Colors.white : Colors.black87;
    final bulletColor = isDark ? _kWhite87 : Colors.black87;
    final strongColor = isDark ? Colors.white : Colors.black;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            decoration: const BoxDecoration(
              color: _kHeaderBg,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: _kWhite70, size: 18),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          // Content (markdown rendered)
          Padding(
            padding: const EdgeInsets.all(16),
            child: MarkdownBody(
              data: content,
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(color: textColor, fontSize: 15, height: 1.5),
                h1: TextStyle(
                    color: titleColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
                h2: TextStyle(
                    color: titleColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
                h3: TextStyle(
                    color: isDark ? _kWhite70 : Colors.black54,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
                listBullet: TextStyle(color: bulletColor, fontSize: 15),
                strong: TextStyle(
                    color: strongColor, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary Card
// ─────────────────────────────────────────────────────────────────────────────
class _SummaryCard extends StatelessWidget {
  final String content;
  final bool isLoading;

  const _SummaryCard({required this.content, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? _kCardBg : Colors.white;
    final textColor = isDark ? _kWhite87 : Colors.black87;
    final titleColor = isDark ? Colors.white : Colors.black87;
    final bulletColor = isDark ? _kWhite87 : Colors.black87;
    final strongColor = isDark ? Colors.white : Colors.black;
    final emColor = isDark ? _kWhite60 : Colors.black54;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color.fromARGB(102, 30, 136, 229)),
        boxShadow: [
          BoxShadow(
            color: const Color.fromARGB(31, 30, 136, 229),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color.fromARGB(217, 30, 136, 229),
                  Color.fromARGB(128, 30, 136, 229)
                ],
              ),
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(16)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.summarize, color: _kWhite70, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Summary',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                if (isLoading) ...[
                  const SizedBox(width: 10),
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _kWhite70),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: MarkdownBody(
              data: content,
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(color: textColor, fontSize: 15, height: 1.6),
                h2: TextStyle(
                    color: titleColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
                listBullet: TextStyle(color: bulletColor, fontSize: 15),
                strong: TextStyle(
                    color: strongColor, fontWeight: FontWeight.bold),
                em: TextStyle(color: emColor, fontStyle: FontStyle.italic),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom Action Bar
// ─────────────────────────────────────────────────────────────────────────────
class _BottomBar extends StatelessWidget {
  final bool isSpeaking;
  final bool disabled;
  final VoidCallback onSpeak;
  final VoidCallback onChatbot;
  final bool isTtsEnabled;

  const _BottomBar({
    required this.isSpeaking,
    required this.disabled,
    required this.onSpeak,
    required this.onChatbot,
    required this.isTtsEnabled,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (isTtsEnabled) ...[
          Expanded(
            child: _ActionBtn(
              icon: isSpeaking
                  ? Icons.stop_circle_outlined
                  : Icons.play_circle_outlined,
              label: isSpeaking ? 'STOP' : 'SPEAK OUT',
              color: const Color(0xFF1565C0),
              onPressed: disabled ? null : onSpeak,
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: _ActionBtn(
            icon: Icons.chat_bubble_outline,
            label: 'CHATBOT',
            color: const Color(0xFF6A1B9A),
            onPressed: disabled ? null : onChatbot,
          ),
        ),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final disabledColor = Color.fromARGB(
      90,
      (color.r * 255).round(),
      (color.g * 255).round(),
      (color.b * 255).round(),
    );
    return ElevatedButton.icon(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        disabledBackgroundColor: disabledColor,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 4,
      ),
      icon: Icon(icon, size: 20),
      label: Text(
        label,
        style: const TextStyle(
            fontWeight: FontWeight.bold, letterSpacing: 1.1, fontSize: 13),
      ),
    );
  }
}
