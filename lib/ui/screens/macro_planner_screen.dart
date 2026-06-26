import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/llm_service.dart';
import '../../data/services/meal_db_service.dart';
import '../../data/services/plan_storage_service.dart';
import 'saved_plans_screen.dart';

// ─── Data Models ─────────────────────────────────────────────

class _MealItem {
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

  const _MealItem({
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
}

class _DayPlan {
  final int day;
  final List<_MealItem> meals;
  const _DayPlan({required this.day, required this.meals});
}

class _WeeklyPlan {
  final String title;
  final String dailyCalories;
  final Map<String, String> macros;
  final String validationNote;
  final List<_DayPlan> days;

  const _WeeklyPlan({
    required this.title,
    required this.dailyCalories,
    required this.macros,
    required this.validationNote,
    required this.days,
  });
}

// ─── Goal Option ─────────────────────────────────────────────

class _GoalOption {
  final String id;
  final String label;
  final IconData icon;
  final Color color;
  final String description;

  const _GoalOption({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    required this.description,
  });
}

// ─── Planner Steps ────────────────────────────────────────────

enum _PlannerStep { selecting, fetching, validating, result, error }

// ─── Screen ──────────────────────────────────────────────────

class MacroPlannerScreen extends ConsumerStatefulWidget {
  const MacroPlannerScreen({super.key});

  @override
  ConsumerState<MacroPlannerScreen> createState() =>
      _MacroPlannerScreenState();
}

class _MacroPlannerScreenState extends ConsumerState<MacroPlannerScreen> {
  _PlannerStep _step = _PlannerStep.selecting;
  String? _selectedGoalId;
  final _prefsController = TextEditingController();
  _WeeklyPlan? _plan;
  String _errorMessage = '';
  int _fetchedRecipeCount = 0;
  bool _isSaved = false;
  bool _isSaving = false;

  static const _goals = [
    _GoalOption(
      id: 'lose_weight',
      label: 'Lose Weight',
      icon: Icons.directions_run_rounded,
      color: Color(0xFFE53935),
      description: 'Calorie deficit with balanced macros',
    ),
    _GoalOption(
      id: 'gain_muscle',
      label: 'Gain Muscle',
      icon: Icons.fitness_center_rounded,
      color: Color(0xFF1E88E5),
      description: 'High protein for muscle growth',
    ),
    _GoalOption(
      id: 'eat_clean',
      label: 'Eat Clean',
      icon: Icons.eco_rounded,
      color: Color(0xFF43A047),
      description: 'Whole foods, no processed items',
    ),
    _GoalOption(
      id: 'maintain',
      label: 'Maintain Weight',
      icon: Icons.balance_rounded,
      color: Color(0xFF8E24AA),
      description: 'Balanced macros for maintenance',
    ),
    _GoalOption(
      id: 'endurance',
      label: 'Build Endurance',
      icon: Icons.directions_bike_rounded,
      color: Color(0xFFFF6F00),
      description: 'Carb-focused for sustained energy',
    ),
    _GoalOption(
      id: 'vegetarian',
      label: 'Vegetarian',
      icon: Icons.grass_rounded,
      color: Color(0xFF00897B),
      description: 'Plant-based complete nutrition',
    ),
  ];

  static const Color _themeColor = Color(0xFF1B5E20);

  _GoalOption? get _selectedGoal => _selectedGoalId == null
      ? null
      : _goals.firstWhere((g) => g.id == _selectedGoalId);

  @override
  void dispose() {
    _prefsController.dispose();
    super.dispose();
  }

  // ─── Pipeline ────────────────────────────────────────────────

  Future<void> _generatePlan() async {
    final goal = _selectedGoal!;
    final preferences = _prefsController.text.trim();

    // Step 1 — fetch real recipes from TheMealDB
    setState(() {
      _step = _PlannerStep.fetching;
      _fetchedRecipeCount = 0;
    });

    List<MealDbMeal> recipes = [];
    try {
      recipes = await MealDbService().fetchMealsForGoal(
        goal.id,
        maxMeals: 20,
      );
      _fetchedRecipeCount = recipes.length;
    } catch (_) {
      // Network unavailable — Gemini will generate meals from scratch.
    }

    // Step 2 — validate & build plan with Gemini
    setState(() => _step = _PlannerStep.validating);

    final prompt = _buildPrompt(goal.label, preferences, recipes);

    try {
      final response = await LlmService().generateGeminiText(prompt);
      final plan = _parsePlan(response);
    setState(() {
      _plan = plan;
      _step = _PlannerStep.result;
      _isSaved = false;
    });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _step = _PlannerStep.error;
      });
    }
  }

  // ─── Prompt builder ──────────────────────────────────────────

  String _buildPrompt(
    String goal,
    String preferences,
    List<MealDbMeal> recipes,
  ) {
    final recipeBlock = recipes.isEmpty
        ? '(No recipes available from database — create appropriate meals from scratch.)'
        : recipes
            .asMap()
            .entries
            .map((e) => e.value.toPromptText(e.key + 1))
            .join('\n---\n');

    return '''
You are a professional nutritionist and chef. Build a 7-day macronutrient meal plan.

USER GOAL: $goal
${preferences.isNotEmpty ? 'DIETARY PREFERENCES / RESTRICTIONS: $preferences' : ''}

REAL RECIPES FROM DATABASE (use these for main meals where they fit):
$recipeBlock

INSTRUCTIONS:
- Assign Breakfast, Lunch, Dinner, and 1 Snack for each of the 7 days.
- For MAIN MEALS (Breakfast/Lunch/Dinner): prefer recipes from the list above. Use the recipe name exactly.
- For SNACKS: create simple, goal-appropriate snacks (e.g. "Greek Yogurt with Berries").
- VALIDATE every selected recipe: if any recipe does NOT match the user goal or violates a stated preference/restriction, REPLACE it with a better recipe or a self-created alternative.
- Estimate realistic macronutrients per serving.
- For each meal explain WHY it fits the goal.
- For each meal list 2–3 ingredient alternatives that are easy to find.
- For each meal provide a Chinese translation of the meal name in the "name_zh" field.

Return ONLY valid JSON (no markdown fences) with exactly this structure:
{
  "plan_title": "7-Day $goal Meal Plan",
  "daily_calories": "XXXX kcal",
  "macros": {"protein": "XXg", "carbs": "XXg", "fat": "XXg"},
  "validation_note": "One sentence summarising how meals were validated against the goal.",
  "days": [
    {
      "day": 1,
      "meals": [
        {
          "type": "Breakfast",
          "name": "Meal Name",
          "name_zh": "餐点中文名称",
          "ingredients": ["measure ingredient", "measure ingredient"],
          "calories": "XXX kcal",
          "protein": "XXg",
          "carbs": "XXg",
          "fat": "XXg",
          "why": "Reason this meal fits the goal.",
          "alternatives": ["Alternative ingredient 1", "Alternative ingredient 2"]
        }
      ]
    }
  ]
}
''';
  }

  // ─── JSON parser ─────────────────────────────────────────────

  _WeeklyPlan _parsePlan(String response) {
    String s = response
        .trim()
        .replaceAll(RegExp(r'```json\s*'), '')
        .replaceAll(RegExp(r'```\s*'), '');

    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start == -1 || end <= start) {
      throw const FormatException('No valid JSON in Gemini response');
    }
    s = s.substring(start, end + 1);

    final data = jsonDecode(s) as Map<String, dynamic>;

    final days = (data['days'] as List).map((d) {
      final meals = (d['meals'] as List).map((m) {
        return _MealItem(
          type: m['type']?.toString() ?? '',
          name: m['name']?.toString() ?? '',
          nameZh: m['name_zh']?.toString() ?? '',
          ingredients: List<String>.from(m['ingredients'] ?? []),
          calories: m['calories']?.toString() ?? '',
          protein: m['protein']?.toString() ?? '',
          carbs: m['carbs']?.toString() ?? '',
          fat: m['fat']?.toString() ?? '',
          why: m['why']?.toString() ?? '',
          alternatives: List<String>.from(m['alternatives'] ?? []),
        );
      }).toList();
      return _DayPlan(day: (d['day'] as num?)?.toInt() ?? 0, meals: meals);
    }).toList();

    final rawMacros = (data['macros'] as Map<String, dynamic>?) ?? {};

    return _WeeklyPlan(
      title: data['plan_title']?.toString() ?? '7-Day Meal Plan',
      dailyCalories: data['daily_calories']?.toString() ?? '',
      macros: rawMacros.map((k, v) => MapEntry(k, v.toString())),
      validationNote: data['validation_note']?.toString() ?? '',
      days: days,
    );
  }

  // ─── Build ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return switch (_step) {
      _PlannerStep.selecting => _buildSelectionView(),
      _PlannerStep.fetching => _buildLoadingView(
          icon: Icons.cloud_download_rounded,
          title: 'Fetching Recipes…',
          subtitle: 'Loading real recipes from TheMealDB',
        ),
      _PlannerStep.validating => _buildLoadingView(
          icon: Icons.auto_awesome_rounded,
          title: 'Validating with Gemini…',
          subtitle: _fetchedRecipeCount > 0
              ? 'Checking $_fetchedRecipeCount recipes against your goal'
              : 'Building your personalised plan',
        ),
      _PlannerStep.result => _buildResultView(),
      _PlannerStep.error => _buildErrorView(),
    };
  }

  // ─── Goal Selection ──────────────────────────────────────────

  Widget _buildSelectionView() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('7-Day Macro Planner'),
        backgroundColor: _themeColor,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Data source badge
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.api_rounded,
                      size: 16, color: Colors.blue.shade700),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Recipes from TheMealDB · Validated by Gemini',
                      style: TextStyle(
                          fontSize: 12, color: Colors.blue.shade700),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'What is your goal?',
              style:
                  TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Select the option that best fits your nutrition needs.',
              style:
                  TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.45,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: _goals.map(_buildGoalButton).toList(),
            ),
            const SizedBox(height: 24),
            const Text(
              'Additional Preferences',
              style:
                  TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Optional — dietary restrictions, cuisine, calorie target, allergies…',
              style:
                  TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _prefsController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText:
                    'e.g. No dairy, prefer Asian cuisine, 1800 kcal, no pork…',
                hintStyle: TextStyle(
                    color: Colors.grey.shade400, fontSize: 13),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: _themeColor, width: 2),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed:
                    _selectedGoalId == null ? null : _generatePlan,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text(
                  'Generate My 7-Day Plan',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _themeColor,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade200,
                  disabledForegroundColor: Colors.grey.shade400,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            if (_selectedGoalId == null) ...[
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Please select a goal above to continue',
                  style: TextStyle(
                      color: Colors.grey.shade400, fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGoalButton(_GoalOption goal) {
    final selected = _selectedGoalId == goal.id;
    return GestureDetector(
      onTap: () => setState(() => _selectedGoalId = goal.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: selected ? goal.color : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: goal.color, width: selected ? 0 : 2),
          boxShadow: [
            BoxShadow(
              color: selected
                  ? goal.color.withValues(alpha: 0.35)
                  : Colors.black.withValues(alpha: 0.05),
              blurRadius: selected ? 12 : 6,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(goal.icon,
                  size: 28,
                  color: selected ? Colors.white : goal.color),
              const SizedBox(height: 5),
              Text(
                goal.label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color:
                      selected ? Colors.white : Colors.black87,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Flexible(
                child: Text(
                  goal.description,
                  style: TextStyle(
                    fontSize: 10,
                    color: selected
                        ? Colors.white70
                        : Colors.grey.shade500,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Loading ─────────────────────────────────────────────────

  Widget _buildLoadingView({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('7-Day Macro Planner'),
        backgroundColor: _themeColor,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 90,
                    height: 90,
                    child: CircularProgressIndicator(
                      color: _themeColor.withValues(alpha: 0.3),
                      strokeWidth: 6,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: _themeColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 34, color: _themeColor),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Text(
                title,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.grey.shade600, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Text(
                'This may take up to 30 seconds',
                style: TextStyle(
                    color: Colors.grey.shade400, fontSize: 12),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _stepDot(
                    label: 'Fetch Recipes',
                    active: _step == _PlannerStep.fetching,
                    done: _step == _PlannerStep.validating ||
                        _step == _PlannerStep.result,
                  ),
                  _stepLine(),
                  _stepDot(
                    label: 'Gemini Validates',
                    active: _step == _PlannerStep.validating,
                    done: _step == _PlannerStep.result,
                  ),
                  _stepLine(),
                  _stepDot(
                    label: 'Build Plan',
                    active: false,
                    done: _step == _PlannerStep.result,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepDot(
      {required String label,
      required bool active,
      required bool done}) {
    final color = done
        ? _themeColor
        : active
            ? Colors.blue.shade600
            : Colors.grey.shade300;
    return Column(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: done
              ? const Icon(Icons.check, color: Colors.white, size: 14)
              : active
                  ? const Icon(Icons.sync_rounded,
                      color: Colors.white, size: 14)
                  : null,
        ),
        const SizedBox(height: 4),
        Text(label,
            style:
                TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _stepLine() => Container(
        width: 32,
        height: 2,
        margin: const EdgeInsets.only(bottom: 18),
        color: Colors.grey.shade300,
      );

  // ─── Result ──────────────────────────────────────────────────

  Widget _buildResultView() {
    final plan = _plan!;
    final goal = _selectedGoal!;

    return Scaffold(
      body: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  goal.color,
                  Color.lerp(goal.color, Colors.black, 0.3)!
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back,
                            color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Text(
                          plan.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Save button
                      IconButton(
                        icon: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ))
                            : Icon(
                                _isSaved
                                    ? Icons.bookmark_rounded
                                    : Icons.bookmark_border_rounded,
                                color: Colors.white,
                              ),
                        tooltip: _isSaved ? 'Saved' : 'Save Plan',
                        onPressed: (_isSaved || _isSaving)
                            ? null
                            : _savePlan,
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded,
                            color: Colors.white),
                        tooltip: 'Regenerate',
                        onPressed: () => setState(
                            () => _step = _PlannerStep.selecting),
                      ),
                    ],
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (plan.dailyCalories.isNotEmpty)
                          _macroPill('🔥 ${plan.dailyCalories}'),
                        if (plan.macros['protein'] != null)
                          _macroPill('P ${plan.macros['protein']}'),
                        if (plan.macros['carbs'] != null)
                          _macroPill('C ${plan.macros['carbs']}'),
                        if (plan.macros['fat'] != null)
                          _macroPill('F ${plan.macros['fat']}'),
                      ],
                    ),
                  ),
                  if (plan.validationNote.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.verified_rounded,
                              color: Colors.white, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              plan.validationNote,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              itemCount: plan.days.length + 1,
              itemBuilder: (context, index) {
                if (index == plan.days.length) {
                  return Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.stretch,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => setState(() {
                            _step = _PlannerStep.selecting;
                            _plan = null;
                          }),
                          icon: const Icon(Icons.tune_rounded),
                          label: const Text(
                              'Change Goal & Regenerate'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: goal.color,
                            side: BorderSide(color: goal.color),
                            padding: const EdgeInsets.symmetric(
                                vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () => showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('Quit Plan?'),
                              content: const Text(
                                  'This will discard the current plan. Are you sure?'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    Navigator.pop(context);
                                  },
                                  child: const Text(
                                    'Quit',
                                    style: TextStyle(
                                        color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          icon: const Icon(
                              Icons.exit_to_app_rounded),
                          label: const Text('Quit Plan'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade400,
                            side: BorderSide(
                                color: Colors.red.shade300),
                            padding: const EdgeInsets.symmetric(
                                vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return _DayCard(
                    day: plan.days[index],
                    goalColor: goal.color);
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _savePlan() async {
    final plan = _plan!;
    final goal = _selectedGoal!;
    setState(() => _isSaving = true);
    try {
      final saved = _toSavedPlan(plan, goal);
      await PlanStorageService().save(saved);
      setState(() {
        _isSaved = true;
        _isSaving = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Plan saved! View it in My Plans.'),
            backgroundColor: goal.color,
            action: SnackBarAction(
              label: 'View',
              textColor: Colors.white,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SavedPlansScreen()),
              ),
            ),
          ),
        );
      }
    } catch (_) {
      setState(() => _isSaving = false);
    }
  }

  SavedPlan _toSavedPlan(_WeeklyPlan plan, _GoalOption goal) {
    final id =
        DateTime.now().millisecondsSinceEpoch.toString();
    return SavedPlan(
      id: id,
      goalId: goal.id,
      goalLabel: goal.label,
      goalColor: goal.color.toARGB32(),
      savedAt: DateTime.now(),
      planTitle: plan.title,
      dailyCalories: plan.dailyCalories,
      macros: plan.macros,
      validationNote: plan.validationNote,
      days: plan.days
          .map((d) => SavedDay(
                day: d.day,
                meals: d.meals
                    .map((m) => SavedMeal(
                          type: m.type,
                          name: m.name,
                          nameZh: m.nameZh,
                          ingredients: m.ingredients,
                          calories: m.calories,
                          protein: m.protein,
                          carbs: m.carbs,
                          fat: m.fat,
                          why: m.why,
                          alternatives: m.alternatives,
                        ))
                    .toList(),
              ))
          .toList(),
    );
  }

  Widget _macroPill(String text) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600)),
    );
  }

  // ─── Error ───────────────────────────────────────────────────

  Widget _buildErrorView() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('7-Day Macro Planner'),
        backgroundColor: _themeColor,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle),
                child: Icon(Icons.error_outline_rounded,
                    size: 60, color: Colors.red.shade400),
              ),
              const SizedBox(height: 24),
              const Text('Failed to Generate Plan',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.grey.shade600, fontSize: 13),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
              if (_errorMessage.toLowerCase().contains('api key') ||
                  _errorMessage.toLowerCase().contains('gemini')) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color: Colors.amber.shade700, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Go to Settings and add your Gemini API key to use this feature.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 28),
              ElevatedButton.icon(
                onPressed: _generatePlan,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _themeColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () =>
                    setState(() => _step = _PlannerStep.selecting),
                child: const Text('Change Goal'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Day Card ────────────────────────────────────────────────

class _DayCard extends StatelessWidget {
  final _DayPlan day;
  final Color goalColor;

  const _DayCard({required this.day, required this.goalColor});

  static const _dayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    final dayName = (day.day >= 1 && day.day <= 7)
        ? _dayNames[day.day - 1]
        : 'Day ${day.day}';

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      elevation: 2,
      shadowColor: goalColor.withValues(alpha: 0.15),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        tilePadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding:
            const EdgeInsets.fromLTRB(12, 0, 12, 12),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: goalColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              '${day.day}',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: goalColor),
            ),
          ),
        ),
        title: Text(dayName,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Text('${day.meals.length} meals',
            style: TextStyle(
                color: Colors.grey.shade500, fontSize: 12)),
        iconColor: goalColor,
        collapsedIconColor: Colors.grey.shade400,
        children: day.meals
            .map((m) =>
                _MealCard(meal: m, accentColor: goalColor))
            .toList(),
      ),
    );
  }
}

// ─── Meal Card ───────────────────────────────────────────────

class _MealCard extends StatefulWidget {
  final _MealItem meal;
  final Color accentColor;

  const _MealCard({required this.meal, required this.accentColor});

  @override
  State<_MealCard> createState() => _MealCardState();
}

class _MealCardState extends State<_MealCard> {
  bool _expanded = false;

  static const _bgColors = {
    'Breakfast': Color(0xFFFFF8E1),
    'Lunch': Color(0xFFE3F2FD),
    'Dinner': Color(0xFFF3E5F5),
    'Snack': Color(0xFFE8F5E9),
  };

  static const _typeIcons = {
    'Breakfast': Icons.free_breakfast_rounded,
    'Lunch': Icons.lunch_dining_rounded,
    'Dinner': Icons.dinner_dining_rounded,
    'Snack': Icons.apple_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final bg = _bgColors[widget.meal.type] ?? Colors.grey.shade50;
    final icon =
        _typeIcons[widget.meal.type] ?? Icons.restaurant_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon,
                          size: 16,
                          color: widget.accentColor),
                      const SizedBox(width: 5),
                      Text(
                        widget.meal.type,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: widget.accentColor,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: Colors.grey.shade400,
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  // Bilingual meal title: English bold + Chinese smaller
                  Text(
                    widget.meal.name,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold),
                  ),
                  if (widget.meal.nameZh.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.meal.nameZh,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        height: 1.3,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: [
                      _chip(
                          '🔥 ${widget.meal.calories}',
                          Colors.orange.shade100,
                          Colors.orange.shade800),
                      _chip('P ${widget.meal.protein}',
                          Colors.blue.shade100,
                          Colors.blue.shade800),
                      _chip('C ${widget.meal.carbs}',
                          Colors.amber.shade100,
                          Colors.amber.shade900),
                      _chip('F ${widget.meal.fat}',
                          Colors.green.shade100,
                          Colors.green.shade800),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(height: 1, color: Colors.grey.shade200),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('Ingredients',
                      Icons.format_list_bulleted_rounded),
                  const SizedBox(height: 6),
                  ...widget.meal.ingredients.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text('• ',
                              style: TextStyle(
                                  color: widget.accentColor,
                                  fontWeight: FontWeight.bold)),
                          Expanded(
                              child: Text(item,
                                  style: const TextStyle(
                                      fontSize: 13))),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _sectionTitle('Why eat this?',
                      Icons.lightbulb_rounded),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: widget.accentColor
                          .withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: widget.accentColor
                              .withValues(alpha: 0.2)),
                    ),
                    child: Text(widget.meal.why,
                        style: const TextStyle(
                            fontSize: 13, height: 1.5)),
                  ),
                  if (widget.meal.alternatives.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _sectionTitle(
                        "Can't find it? Alternatives:",
                        Icons.swap_horiz_rounded),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children:
                          widget.meal.alternatives.map((alt) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius:
                                BorderRadius.circular(20),
                            border: Border.all(
                                color: widget.accentColor
                                    .withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            alt,
                            style: TextStyle(
                              fontSize: 12,
                              color: widget.accentColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String label, Color bg, Color fg) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg)),
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 15, color: widget.accentColor),
        const SizedBox(width: 6),
        Text(title,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: widget.accentColor)),
      ],
    );
  }
}
