import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Public meal models (mirrors _MealItem / _DayPlan / _WeeklyPlan) ─────────

class SavedMeal {
  final String type;
  final String name;
  final String nameZh;
  final List<String> ingredients;
  final String calories;
  final String protein;
  final String carbs;
  final String fat;
  final String why;
  final List<String> alternatives;

  const SavedMeal({
    required this.type,
    required this.name,
    this.nameZh = '',
    required this.ingredients,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.why,
    required this.alternatives,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'name': name,
        'name_zh': nameZh,
        'ingredients': ingredients,
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'why': why,
        'alternatives': alternatives,
      };

  factory SavedMeal.fromJson(Map<String, dynamic> j) => SavedMeal(
        type: j['type']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        nameZh: j['name_zh']?.toString() ?? '',
        ingredients: List<String>.from(j['ingredients'] ?? []),
        calories: j['calories']?.toString() ?? '',
        protein: j['protein']?.toString() ?? '',
        carbs: j['carbs']?.toString() ?? '',
        fat: j['fat']?.toString() ?? '',
        why: j['why']?.toString() ?? '',
        alternatives: List<String>.from(j['alternatives'] ?? []),
      );
}

class SavedDay {
  final int day;
  final List<SavedMeal> meals;

  const SavedDay({required this.day, required this.meals});

  Map<String, dynamic> toJson() => {
        'day': day,
        'meals': meals.map((m) => m.toJson()).toList(),
      };

  factory SavedDay.fromJson(Map<String, dynamic> j) => SavedDay(
        day: (j['day'] as num?)?.toInt() ?? 0,
        meals: (j['meals'] as List? ?? [])
            .map((m) => SavedMeal.fromJson(m as Map<String, dynamic>))
            .toList(),
      );
}

// ─── Food Analysis ────────────────────────────────────────────────────────────

class FoodAnalysis {
  final String detectedFood;
  final String calories;
  final String protein;
  final String carbs;
  final String fibre;
  final String fat;
  final bool alignsWithGoal;
  final String feedback;

  const FoodAnalysis({
    required this.detectedFood,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fibre,
    required this.fat,
    required this.alignsWithGoal,
    required this.feedback,
  });

  Map<String, dynamic> toJson() => {
        'detected_food': detectedFood,
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fibre': fibre,
        'fat': fat,
        'aligns_with_goal': alignsWithGoal,
        'feedback': feedback,
      };

  factory FoodAnalysis.fromJson(Map<String, dynamic> j) => FoodAnalysis(
        detectedFood: j['detected_food']?.toString() ?? '',
        calories: j['calories']?.toString() ?? '',
        protein: j['protein']?.toString() ?? '',
        carbs: j['carbs']?.toString() ?? '',
        fibre: j['fibre']?.toString() ?? '',
        fat: j['fat']?.toString() ?? '',
        alignsWithGoal: j['aligns_with_goal'] as bool? ?? true,
        feedback: j['feedback']?.toString() ?? '',
      );
}

// ─── Check-in ─────────────────────────────────────────────────────────────────

class MealCheckIn {
  bool isChecked;
  String? photoPath;
  FoodAnalysis? analysis;
  DateTime? checkedAt;

  /// True when the user indicates they did NOT follow the planned meal.
  bool didntFollow;
  /// Photo of what they actually ate instead.
  String? deviationPhotoPath;
  /// Gemini nutritional analysis of the deviation photo.
  FoodAnalysis? deviationAnalysis;

  MealCheckIn({
    this.isChecked = false,
    this.photoPath,
    this.analysis,
    this.checkedAt,
    this.didntFollow = false,
    this.deviationPhotoPath,
    this.deviationAnalysis,
  });

  Map<String, dynamic> toJson() => {
        'is_checked': isChecked,
        'photo_path': photoPath,
        'analysis': analysis?.toJson(),
        'checked_at': checkedAt?.toIso8601String(),
        'didnt_follow': didntFollow,
        'deviation_photo_path': deviationPhotoPath,
        'deviation_analysis': deviationAnalysis?.toJson(),
      };

  factory MealCheckIn.fromJson(Map<String, dynamic> j) => MealCheckIn(
        isChecked: j['is_checked'] as bool? ?? false,
        photoPath: j['photo_path'] as String?,
        analysis: j['analysis'] == null
            ? null
            : FoodAnalysis.fromJson(j['analysis'] as Map<String, dynamic>),
        checkedAt: j['checked_at'] == null
            ? null
            : DateTime.tryParse(j['checked_at'] as String),
        didntFollow: j['didnt_follow'] as bool? ?? false,
        deviationPhotoPath: j['deviation_photo_path'] as String?,
        deviationAnalysis: j['deviation_analysis'] == null
            ? null
            : FoodAnalysis.fromJson(
                j['deviation_analysis'] as Map<String, dynamic>),
      );
}

// ─── Saved Plan ───────────────────────────────────────────────────────────────

class SavedPlan {
  final String id;
  final String goalId;
  final String goalLabel;
  final int goalColor;
  final DateTime savedAt;
  bool isActive;
  DateTime? startDate;
  final String planTitle;
  final String dailyCalories;
  final Map<String, String> macros;
  final String validationNote;
  final List<SavedDay> days;
  // key: "${day}_${mealType}" e.g. "1_Breakfast"
  Map<String, MealCheckIn> checkIns;

  SavedPlan({
    required this.id,
    required this.goalId,
    required this.goalLabel,
    required this.goalColor,
    required this.savedAt,
    this.isActive = true,
    this.startDate,
    required this.planTitle,
    required this.dailyCalories,
    required this.macros,
    required this.validationNote,
    required this.days,
    Map<String, MealCheckIn>? checkIns,
  }) : checkIns = checkIns ?? {};

  /// Returns the calendar date for [day] (1-based) if startDate is set.
  DateTime? dateForDay(int day) =>
      startDate?.add(Duration(days: day - 1));

  int get totalMeals =>
      days.fold(0, (sum, d) => sum + d.meals.length);

  int get checkedMeals =>
      checkIns.values.where((c) => c.isChecked).length;

  String checkInKey(int day, String mealType) => '${day}_$mealType';

  Map<String, dynamic> toJson() => {
        'id': id,
        'goal_id': goalId,
        'goal_label': goalLabel,
        'goal_color': goalColor,
        'saved_at': savedAt.toIso8601String(),
        'is_active': isActive,
        'start_date': startDate?.toIso8601String(),
        'plan_title': planTitle,
        'daily_calories': dailyCalories,
        'macros': macros,
        'validation_note': validationNote,
        'days': days.map((d) => d.toJson()).toList(),
        'check_ins': checkIns
            .map((k, v) => MapEntry(k, v.toJson())),
      };

  factory SavedPlan.fromJson(Map<String, dynamic> j) {
    final rawCheckIns =
        (j['check_ins'] as Map<String, dynamic>?) ?? {};
    return SavedPlan(
      id: j['id']?.toString() ?? '',
      goalId: j['goal_id']?.toString() ?? '',
      goalLabel: j['goal_label']?.toString() ?? '',
      goalColor: (j['goal_color'] as num?)?.toInt() ?? 0xFF1B5E20,
      savedAt: DateTime.tryParse(j['saved_at'] as String? ?? '') ??
          DateTime.now(),
      isActive: j['is_active'] as bool? ?? true,
      startDate: j['start_date'] == null
          ? null
          : DateTime.tryParse(j['start_date'] as String),
      planTitle: j['plan_title']?.toString() ?? '',
      dailyCalories: j['daily_calories']?.toString() ?? '',
      macros: Map<String, String>.from(
          (j['macros'] as Map<String, dynamic>?)?.map(
                (k, v) => MapEntry(k, v.toString()),
              ) ??
              {}),
      validationNote: j['validation_note']?.toString() ?? '',
      days: (j['days'] as List? ?? [])
          .map((d) => SavedDay.fromJson(d as Map<String, dynamic>))
          .toList(),
      checkIns: rawCheckIns.map(
          (k, v) => MapEntry(k, MealCheckIn.fromJson(v as Map<String, dynamic>))),
    );
  }
}

// ─── Storage Service ──────────────────────────────────────────────────────────

class PlanStorageService {
  static const _indexKey = 'macro_plan_ids';
  static const _planPrefix = 'macro_plan_';

  Future<List<SavedPlan>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_indexKey) ?? [];
    final plans = <SavedPlan>[];
    for (final id in ids) {
      final raw = prefs.getString('$_planPrefix$id');
      if (raw != null) {
        try {
          plans.add(SavedPlan.fromJson(
              jsonDecode(raw) as Map<String, dynamic>));
        } catch (_) {
          // Skip corrupted entries.
        }
      }
    }
    plans.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return plans;
  }

  Future<SavedPlan?> load(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_planPrefix$id');
    if (raw == null) return null;
    try {
      return SavedPlan.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(SavedPlan plan) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_indexKey) ?? [];
    if (!ids.contains(plan.id)) {
      ids.add(plan.id);
      await prefs.setStringList(_indexKey, ids);
    }
    await prefs.setString('$_planPrefix${plan.id}', jsonEncode(plan.toJson()));
  }

  Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_indexKey) ?? [];
    ids.remove(id);
    await prefs.setStringList(_indexKey, ids);
    await prefs.remove('$_planPrefix$id');
  }

  Future<void> updateCheckIn(
      String planId, String key, MealCheckIn checkIn) async {
    final plan = await load(planId);
    if (plan == null) return;
    plan.checkIns[key] = checkIn;
    await save(plan);
  }

  Future<void> quitPlan(String planId) async {
    final plan = await load(planId);
    if (plan == null) return;
    plan.isActive = false;
    await save(plan);
  }
}
