import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Initialize this provider in main.dart');
});

final conversationRepositoryProvider = Provider((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ConversationRepository(prefs);
});

class ConversationRepository {
  static const String _keyHistory = 'conv_history';
  static const String _keyInterpreter = 'interpreter_context';
  
  final SharedPreferences _prefs;
  
  String? _historyCache;
  String? _interpreterCache;

  ConversationRepository(this._prefs) {
    _historyCache = _prefs.getString(_keyHistory) ?? '';
    _interpreterCache = _prefs.getString(_keyInterpreter);
  }

  Future<void> setInterpreterContext(String context) async {
    _interpreterCache = context;
    await _prefs.setString(_keyInterpreter, context);
  }

  Future<void> clearInterpreterContext() async {
    _interpreterCache = null;
    await _prefs.remove(_keyInterpreter);
  }

  Future<void> appendUser(String userText) async {
    final ut = userText.trim();
    if (ut.isNotEmpty) {
      _historyCache = _appendAndTrim(_historyCache, 'User: $ut\n');
      await _saveHistory();
    }
  }

  Future<void> appendAssistant(String assistantText) async {
    final at = assistantText.trim();
    if (at.isNotEmpty) {
      _historyCache = _appendAndTrim(_historyCache, 'Assistant: $at\n');
      await _saveHistory();
    }
  }

  Future<void> clearHistory() async {
    _historyCache = '';
    await _saveHistory();
  }

  Future<void> clearAll() async {
    _historyCache = '';
    _interpreterCache = null;
    await _prefs.remove(_keyHistory);
    await _prefs.remove(_keyInterpreter);
  }

  String buildPromptForSend(String userPrompt) {
    final sb = StringBuffer();
    if (_interpreterCache != null && _interpreterCache!.isNotEmpty) {
      String ctxText = _interpreterCache!.trim();
      if (ctxText.length > 6000) {
        ctxText = '${ctxText.substring(0, 6000)}\n...[truncated]';
      }
      sb.write('Context from content interpreter:\n$ctxText\n\n');
    }
    
    if (_historyCache != null && _historyCache!.isNotEmpty) {
      sb.write('${_historyCache!.trim()}\n\n');
    }
    
    final up = userPrompt.trim();
    if (up.isNotEmpty) {
      sb.write('User: $up\nAssistant:');
    }
    return sb.toString();
  }

  String _appendAndTrim(String? base, String add) {
    base ??= '';
    String combined = base + add;
    const max = 4000;
    if (combined.length > max) {
      return combined.substring(combined.length - max);
    }
    return combined;
  }

  Future<void> _saveHistory() async {
    await _prefs.setString(_keyHistory, _historyCache ?? '');
  }
}
