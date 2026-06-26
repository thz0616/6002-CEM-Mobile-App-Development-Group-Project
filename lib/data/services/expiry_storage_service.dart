import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Category fallback days ───────────────────────────────────────────────────

/// Days to add from today when no expiry date can be read from the package.
const Map<String, int> categoryFallbackDays = {
  'dairy': 7,
  'meat': 3,
  'bread': 5,
  'beverage': 30,
  'canned': 365,
  'frozen': 90,
  'produce': 7,
  'condiment': 180,
  'snack': 60,
  'other': 14,
};

// ─── Model ────────────────────────────────────────────────────────────────────

class ExpiryItem {
  final String id;
  String name;
  String category;
  DateTime expiryDate;
  String? photoPath;
  String storageAdvice;
  final DateTime addedAt;

  ExpiryItem({
    required this.id,
    required this.name,
    required this.category,
    required this.expiryDate,
    this.photoPath,
    this.storageAdvice = '',
    required this.addedAt,
  });

  /// Days until expiry (negative = already expired).
  int get daysUntilExpiry {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final exp = DateTime(
        expiryDate.year, expiryDate.month, expiryDate.day);
    return exp.difference(today).inDays;
  }

  bool get isExpired => daysUntilExpiry < 0;

  /// Human-readable label for expiry status.
  String get statusLabel {
    final d = daysUntilExpiry;
    if (d < 0) return 'Expired ${-d}d ago';
    if (d == 0) return 'Expires today!';
    if (d == 1) return 'Expires tomorrow';
    return 'Expires in ${d}d';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'expiry_date': expiryDate.toIso8601String(),
        'photo_path': photoPath,
        'storage_advice': storageAdvice,
        'added_at': addedAt.toIso8601String(),
      };

  factory ExpiryItem.fromJson(Map<String, dynamic> j) => ExpiryItem(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? 'Unknown',
        category: j['category']?.toString() ?? 'other',
        expiryDate:
            DateTime.tryParse(j['expiry_date'] as String? ?? '') ??
                DateTime.now(),
        photoPath: j['photo_path'] as String?,
        storageAdvice: j['storage_advice']?.toString() ?? '',
        addedAt:
            DateTime.tryParse(j['added_at'] as String? ?? '') ??
                DateTime.now(),
      );
}

// ─── Storage service ──────────────────────────────────────────────────────────

class ExpiryStorageService {
  static const _key = 'expiry_items';

  Future<List<ExpiryItem>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    final items = <ExpiryItem>[];
    for (final s in raw) {
      try {
        items.add(ExpiryItem.fromJson(
            jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {}
    }
    // Sort: soonest expiry first (expired items float to top in red)
    items.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
    return items;
  }

  Future<void> save(ExpiryItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    // Replace if exists, else append
    final idx = raw.indexWhere((s) {
      try {
        return (jsonDecode(s) as Map<String, dynamic>)['id'] == item.id;
      } catch (_) {
        return false;
      }
    });
    final encoded = jsonEncode(item.toJson());
    if (idx >= 0) {
      raw[idx] = encoded;
    } else {
      raw.add(encoded);
    }
    await prefs.setStringList(_key, raw);
  }

  Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    raw.removeWhere((s) {
      try {
        return (jsonDecode(s) as Map<String, dynamic>)['id'] == id;
      } catch (_) {
        return false;
      }
    });
    await prefs.setStringList(_key, raw);
  }
}
