import 'package:dio/dio.dart';

/// A single meal returned from TheMealDB API.
class MealDbMeal {
  final String id;
  final String name;
  final String category;
  final String area;
  final List<String> ingredients; // formatted as "measure ingredient"

  const MealDbMeal({
    required this.id,
    required this.name,
    required this.category,
    required this.area,
    required this.ingredients,
  });

  /// Compact text representation sent to Gemini.
  String toPromptText(int index) {
    final ingredientList = ingredients.take(12).join(', ');
    return 'RECIPE $index: $name (${category.isNotEmpty ? category : "General"}'
        '${area.isNotEmpty ? ", $area" : ""})\n'
        'Ingredients: $ingredientList';
  }
}

/// Client for TheMealDB free API (https://www.themealdb.com/api.php).
/// No API key required with the free tier (key = "1").
class MealDbService {
  static const String _base = 'https://www.themealdb.com/api/json/v1/1';

  final Dio _dio;

  MealDbService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
            ));

  // ─── Keyword→goal mapping ─────────────────────────────────────

  /// Keywords used to search TheMealDB by meal name per goal.
  static const Map<String, List<String>> _goalKeywords = {
    'lose_weight': ['chicken', 'fish', 'prawn'],
    'gain_muscle': ['beef', 'chicken', 'lamb'],
    'eat_clean': ['salad', 'vegetable', 'fish'],
    'maintain': ['chicken', 'pasta', 'pork'],
    'endurance': ['pasta', 'rice', 'chicken'],
    'vegetarian': ['vegetable', 'potato', 'lentil'],
  };

  // ─── Public API ───────────────────────────────────────────────

  /// Fetches up to [maxMeals] full meal details suited to [goalId].
  /// Returns an empty list (does not throw) on network failure so the
  /// caller can gracefully fall back to pure Gemini generation.
  Future<List<MealDbMeal>> fetchMealsForGoal(
    String goalId, {
    int maxMeals = 20,
  }) async {
    final keywords = _goalKeywords[goalId] ?? ['chicken', 'vegetable'];
    final seen = <String>{};
    final meals = <MealDbMeal>[];
    final perKeyword = (maxMeals / keywords.length).ceil();

    for (final keyword in keywords) {
      if (meals.length >= maxMeals) break;
      try {
        final results = await _searchByKeyword(keyword, limit: perKeyword);
        for (final m in results) {
          if (!seen.contains(m.id)) {
            seen.add(m.id);
            meals.add(m);
            if (meals.length >= maxMeals) break;
          }
        }
      } catch (_) {
        // Silently skip failed keywords; partial results are still useful.
      }
    }
    return meals;
  }

  // ─── Private helpers ──────────────────────────────────────────

  Future<List<MealDbMeal>> _searchByKeyword(
    String keyword, {
    int limit = 8,
  }) async {
    final response = await _dio.get(
      '$_base/search.php',
      queryParameters: {'s': keyword},
    );

    final raw = response.data['meals'];
    if (raw == null) return [];

    final list = raw as List<dynamic>;
    return list
        .take(limit)
        .map((m) => _parse(m as Map<String, dynamic>))
        .toList();
  }

  MealDbMeal _parse(Map<String, dynamic> m) {
    final ingredients = <String>[];
    for (int i = 1; i <= 20; i++) {
      final ingredient =
          (m['strIngredient$i'] as String?)?.trim() ?? '';
      final measure = (m['strMeasure$i'] as String?)?.trim() ?? '';
      if (ingredient.isNotEmpty) {
        ingredients.add(
          measure.isNotEmpty ? '$measure $ingredient' : ingredient,
        );
      }
    }
    return MealDbMeal(
      id: m['idMeal']?.toString() ?? '',
      name: (m['strMeal'] as String?)?.trim() ?? 'Unknown',
      category: (m['strCategory'] as String?)?.trim() ?? '',
      area: (m['strArea'] as String?)?.trim() ?? '',
      ingredients: ingredients,
    );
  }
}
