import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'conversation_repository.dart';

class ContactItem {
  final String id;
  final String name;
  final String number;

  ContactItem({required this.id, required this.name, required this.number});

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'number': number,
      };

  factory ContactItem.fromJson(Map<String, dynamic> json) {
    return ContactItem(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      number: json['number']?.toString() ?? '',
    );
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier(ref.watch(sharedPreferencesProvider));
});

class SettingsState {
  final String geminiApiKey;
  final String openFdaApiKey;
  final bool hornEnabled;
  final bool showHornProbability;
  final bool smsScamDetectionEnabled;
  final List<ContactItem> savedContacts;
  final Set<String> favoriteContacts;
  final String preferredLanguage;
  final bool ttsEnabled;

  SettingsState({
    required this.geminiApiKey,
    required this.openFdaApiKey,
    required this.hornEnabled,
    required this.showHornProbability,
    required this.smsScamDetectionEnabled,
    required this.savedContacts,
    required this.favoriteContacts,
    required this.preferredLanguage,
    required this.ttsEnabled,
  });

  SettingsState copyWith({
    String? geminiApiKey,
    String? openFdaApiKey,
    bool? hornEnabled,
    bool? showHornProbability,
    bool? smsScamDetectionEnabled,
    List<ContactItem>? savedContacts,
    Set<String>? favoriteContacts,
    String? preferredLanguage,
    bool? ttsEnabled,
  }) {
    return SettingsState(
      geminiApiKey: geminiApiKey ?? this.geminiApiKey,
      openFdaApiKey: openFdaApiKey ?? this.openFdaApiKey,
      hornEnabled: hornEnabled ?? this.hornEnabled,
      showHornProbability: showHornProbability ?? this.showHornProbability,
      smsScamDetectionEnabled: smsScamDetectionEnabled ?? this.smsScamDetectionEnabled,
      savedContacts: savedContacts ?? this.savedContacts,
      favoriteContacts: favoriteContacts ?? this.favoriteContacts,
      preferredLanguage: preferredLanguage ?? this.preferredLanguage,
      ttsEnabled: ttsEnabled ?? this.ttsEnabled,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  final SharedPreferences _prefs;

  SettingsNotifier(this._prefs)
      : super(SettingsState(
          geminiApiKey: _prefs.getString('gemini_api_key') ?? '',
          openFdaApiKey: _prefs.getString('open_fda_api_key') ?? '',
          hornEnabled: _prefs.getBool('horn_enabled') ?? false,
          showHornProbability: _prefs.getBool('show_horn_probability') ?? true,
          smsScamDetectionEnabled: _prefs.getBool('sms_scam_detection_enabled') ?? false,
          savedContacts: _loadContacts(_prefs),
          favoriteContacts: (_prefs.getStringList('favorite_contacts') ?? []).toSet(),
          preferredLanguage: _prefs.getString('preferred_language') ?? 'en-US',
          ttsEnabled: _prefs.getBool('tts_enabled') ?? true,
        ));

  static List<ContactItem> _loadContacts(SharedPreferences prefs) {
    final str = prefs.getString('saved_contacts');
    if (str == null || str.isEmpty) return [];
    try {
      final arr = jsonDecode(str) as List;
      return arr.map((e) => ContactItem.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (_) {
      return [];
    }
  }

  void setGeminiApiKey(String key) {
    _prefs.setString('gemini_api_key', key);
    state = state.copyWith(geminiApiKey: key);
  }

  void setOpenFdaApiKey(String key) {
    _prefs.setString('open_fda_api_key', key);
    state = state.copyWith(openFdaApiKey: key);
  }

  void setSmsScamDetectionEnabled(bool enabled) {
    _prefs.setBool('sms_scam_detection_enabled', enabled);
    state = state.copyWith(smsScamDetectionEnabled: enabled);
  }

  void setHornEnabled(bool enabled) {
    _prefs.setBool('horn_enabled', enabled);
    state = state.copyWith(hornEnabled: enabled);
  }

  void setShowHornProbability(bool show) {
    _prefs.setBool('show_horn_probability', show);
    state = state.copyWith(showHornProbability: show);
  }

  void setPreferredLanguage(String lang) {
    _prefs.setString('preferred_language', lang);
    state = state.copyWith(preferredLanguage: lang);
  }

  void setTtsEnabled(bool enabled) {
    _prefs.setBool('tts_enabled', enabled);
    state = state.copyWith(ttsEnabled: enabled);
  }

  Future<void> syncContacts() async {
    final status = await FlutterContacts.permissions.request(PermissionType.read);
    if (status == PermissionStatus.granted) {
      final contacts = await FlutterContacts.getAll(properties: ContactProperties.allProperties);
      final items = <ContactItem>[];
      for (var c in contacts) {
        if (c.phones.isNotEmpty) {
          items.add(ContactItem(
            id: c.id ?? '',
            name: c.displayName ?? '',
            number: c.phones.first.normalizedNumber ?? c.phones.first.number,
          ));
        }
      }
      items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      
      final str = jsonEncode(items.map((e) => e.toJson()).toList());
      await _prefs.setString('saved_contacts', str);
      state = state.copyWith(savedContacts: items);
    }
  }

  void toggleFavorite(String number) {
    final normalized = number.replaceAll(RegExp(r'[^0-9+]'), '');
    final newFavs = Set<String>.from(state.favoriteContacts);
    if (newFavs.contains(normalized)) {
      newFavs.remove(normalized);
    } else {
      newFavs.add(normalized);
    }
    _prefs.setStringList('favorite_contacts', newFavs.toList());
    state = state.copyWith(favoriteContacts: newFavs);
  }
}
