import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../data/services/llm_service.dart';
import '../../data/services/plan_storage_service.dart';

class PlanCheckInScreen extends StatefulWidget {
  final String planId;
  const PlanCheckInScreen({super.key, required this.planId});

  @override
  State<PlanCheckInScreen> createState() => _PlanCheckInScreenState();
}

class _PlanCheckInScreenState extends State<PlanCheckInScreen> {
  final _storage = PlanStorageService();
  SavedPlan? _plan;
  bool _loading = true;
  bool _settingDate = false;
  // key → is currently analysing (checked photo or deviation)
  final Map<String, bool> _analyzing = {};

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final plan = await _storage.load(widget.planId);
    setState(() {
      _plan = plan;
      _loading = false;
    });
  }

  Future<void> _persist() async {
    if (_plan == null) return;
    await _storage.save(_plan!);
  }

  Color get _goalColor => Color(_plan?.goalColor ?? 0xFF1B5E20);

  String _key(int day, String type) => '${day}_$type';

  MealCheckIn _checkIn(int day, String type) =>
      _plan!.checkIns[_key(day, type)] ?? MealCheckIn();

  bool _isToday(int dayNumber) {
    final start = _plan?.startDate;
    if (start == null) return false;
    final d = start.add(Duration(days: dayNumber - 1));
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  String _fmtDate(DateTime dt) =>
      '${dt.day} ${_months[dt.month - 1]} ${dt.year}';

  // ─── Set start date (one-time) ────────────────────────────────

  Future<void> _setStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Select Start Date (Day 1)',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme:
              ColorScheme.light(primary: _goalColor),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Start Date'),
        content: Text(
          'Start: ${_fmtDate(picked)}\nEnd: ${_fmtDate(picked.add(const Duration(days: 6)))}\n\nThis cannot be changed later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: _goalColor,
                foregroundColor: Colors.white),
            child: const Text('Confirm & Lock'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _settingDate = true);
    _plan!.startDate = picked;
    await _persist();
    setState(() => _settingDate = false);
  }

  // ─── Check meal (tick = "I followed the plan") ───────────────

  Future<void> _onCheckTap(SavedMeal meal, int day) async {
    final key = _key(day, meal.type);
    final ci = _checkIn(day, meal.type);

    if (ci.isChecked) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Uncheck Meal?'),
          content:
              const Text('This will remove the check-in for this meal.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Uncheck',
                    style: TextStyle(color: Colors.red))),
          ],
        ),
      );
      if (confirm != true) return;
      ci.isChecked = false;
      _plan!.checkIns[key] = ci;
      await _persist();
      setState(() {});
      return;
    }

    // Checking → photo or skip
    if (!mounted) return;
    final source = await _showPhotoSourceSheet(meal);
    if (source == null) return;

    ci.isChecked = true;
    ci.checkedAt = DateTime.now();
    _plan!.checkIns[key] = ci;
    await _persist();
    setState(() {});

    if (source == 'skip') return;
    await _addPhoto(meal, day, source, isDeviation: false);
  }

  // ─── "Didn't follow" icon tap ────────────────────────────────

  Future<void> _onDidntFollowTap(SavedMeal meal, int day) async {
    final key = _key(day, meal.type);
    final ci = _checkIn(day, meal.type);

    if (ci.didntFollow) {
      // Already marked — offer to clear
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Clear Deviation?'),
          content:
              const Text('Remove the "didn\'t follow" record for this meal?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Clear',
                    style: TextStyle(color: Colors.red))),
          ],
        ),
      );
      if (confirm != true) return;
      ci.didntFollow = false;
      ci.deviationPhotoPath = null;
      ci.deviationAnalysis = null;
      _plan!.checkIns[key] = ci;
      await _persist();
      setState(() {});
      return;
    }

    // Not yet marked — pick photo of what they ate
    if (!mounted) return;
    final source = await _showDeviationPhotoSheet(meal);
    if (source == null) return;

    ci.didntFollow = true;
    _plan!.checkIns[key] = ci;
    await _persist();
    setState(() {});

    await _addPhoto(meal, day, source, isDeviation: true);
  }

  // ─── Photo source sheets ──────────────────────────────────────

  Future<String?> _showPhotoSourceSheet(SavedMeal meal) =>
      showModalBottomSheet<String>(
        context: context,
        shape: const RoundedRectangleBorder(
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(meal.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                if (meal.nameZh.isNotEmpty)
                  Text(meal.nameZh,
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade500)),
                const SizedBox(height: 4),
                Text(
                  'Submit a proof photo (optional) — Gemini will check if it matches your goal.',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                _photoTile(Icons.camera_alt_rounded, _goalColor,
                    'Take a photo', 'Gemini will analyse it',
                    () => Navigator.pop(context, 'camera')),
                _photoTile(Icons.photo_library_rounded, _goalColor,
                    'Choose from gallery', 'Gemini will analyse it',
                    () => Navigator.pop(context, 'gallery')),
                _photoTile(Icons.skip_next_rounded,
                    Colors.grey.shade500, 'Skip — no photo',
                    'Just mark as done',
                    () => Navigator.pop(context, 'skip')),
              ],
            ),
          ),
        ),
      );

  Future<String?> _showDeviationPhotoSheet(SavedMeal meal) =>
      showModalBottomSheet<String>(
        context: context,
        shape: const RoundedRectangleBorder(
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('What did you eat instead?',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text(
                  'Upload a photo of what you actually ate — Gemini will calculate the calories, protein, carbs and fibre.',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                _photoTile(Icons.camera_alt_rounded, Colors.red.shade400,
                    'Take a photo now', 'Analyse actual food eaten',
                    () => Navigator.pop(context, 'camera')),
                _photoTile(Icons.photo_library_rounded,
                    Colors.red.shade400, 'Choose from gallery',
                    'Analyse actual food eaten',
                    () => Navigator.pop(context, 'gallery')),
              ],
            ),
          ),
        ),
      );

  ListTile _photoTile(IconData icon, Color color, String title,
      String subtitle, VoidCallback onTap) =>
      ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle),
          child: Icon(icon, color: color),
        ),
        title: Text(title),
        subtitle: Text(subtitle,
            style: const TextStyle(fontSize: 12)),
        onTap: onTap,
      );

  // ─── Image pick + Gemini analyse ─────────────────────────────

  Future<void> _addPhoto(SavedMeal meal, int day, String source,
      {required bool isDeviation}) async {
    final picker = ImagePicker();
    final picked = source == 'camera'
        ? await picker.pickImage(
            source: ImageSource.camera, imageQuality: 80)
        : await picker.pickImage(
            source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;

    final key = _key(day, meal.type);
    final analyzeKey = isDeviation ? '${key}_dev' : key;
    setState(() => _analyzing[analyzeKey] = true);

    final ci = _checkIn(day, meal.type);
    if (isDeviation) {
      ci.deviationPhotoPath = picked.path;
    } else {
      ci.photoPath = picked.path;
      ci.isChecked = true;
      ci.checkedAt ??= DateTime.now();
    }
    _plan!.checkIns[key] = ci;
    await _persist();
    setState(() {});

    try {
      final rawJson = await LlmService().analyzeFoodImage(
        picked.path,
        goalLabel: isDeviation
            ? 'N/A — user deviated from plan, just estimate nutritional values'
            : _plan!.goalLabel,
        mealType: meal.type,
        plannedMealName:
            isDeviation ? 'unknown (user deviated)' : meal.name,
      );
      final analysis = _parseAnalysis(rawJson);
      if (isDeviation) {
        ci.deviationAnalysis = analysis;
      } else {
        ci.analysis = analysis;
      }
      _plan!.checkIns[key] = ci;
      await _persist();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Analysis failed: $e'),
          backgroundColor: Colors.red.shade400,
        ));
      }
    } finally {
      setState(() => _analyzing.remove(analyzeKey));
    }
  }

  FoodAnalysis _parseAnalysis(String raw) {
    String s = raw
        .trim()
        .replaceAll(RegExp(r'```json\s*'), '')
        .replaceAll(RegExp(r'```\s*'), '');
    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start == -1 || end <= start) {
      throw const FormatException('No valid JSON');
    }
    return FoodAnalysis.fromJson(
        jsonDecode(s.substring(start, end + 1)) as Map<String, dynamic>);
  }

  // ─── Quit ─────────────────────────────────────────────────────

  Future<void> _quitPlan() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Quit Plan?'),
        content: const Text(
            'Progress will be saved, but the plan will be marked as quit.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Quit',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await _storage.quitPlan(widget.planId);
      Navigator.pop(context);
    }
  }

  // ─── Build ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }
    if (_plan == null) {
      return Scaffold(
          appBar: AppBar(title: const Text('Plan Not Found')),
          body: const Center(
              child: Text('This plan could not be loaded.')));
    }

    // Gate: must set start date first
    if (_plan!.startDate == null) {
      return _buildStartDateGate();
    }

    return _buildCheckInView();
  }

  // ─── Start Date Gate ─────────────────────────────────────────

  Widget _buildStartDateGate() {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _goalColor,
              Color.lerp(_goalColor, Colors.black, 0.3)!,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back,
                        color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                              Icons.event_available_rounded,
                              size: 60,
                              color: Colors.white),
                        ),
                        const SizedBox(height: 28),
                        const Text(
                          'Set Your Start Date',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Choose when Day 1 begins.\nYou can only check in meals on their scheduled day.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color:
                                Colors.white.withValues(alpha: 0.85),
                            fontSize: 14,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color:
                                Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.lock_rounded,
                                  color: Colors.white70, size: 14),
                              const SizedBox(width: 6),
                              Text(
                                'Start date cannot be changed once set',
                                style: TextStyle(
                                  color: Colors.white
                                      .withValues(alpha: 0.8),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 36),
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton.icon(
                            onPressed:
                                _settingDate ? null : _setStartDate,
                            icon: _settingDate
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white))
                                : const Icon(
                                    Icons.calendar_today_rounded),
                            label: Text(
                              _settingDate
                                  ? 'Saving…'
                                  : 'Choose Start Date',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: _goalColor,
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Main Check-In View ───────────────────────────────────────

  Widget _buildCheckInView() {
    final plan = _plan!;
    final progress =
        plan.totalMeals == 0 ? 0.0 : plan.checkedMeals / plan.totalMeals;

    return Scaffold(
      body: Column(
        children: [
          // Header
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _goalColor,
                  Color.lerp(_goalColor, Colors.black, 0.3)!,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Column(
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
                          plan.planTitle,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (plan.isActive)
                        TextButton.icon(
                          onPressed: _quitPlan,
                          icon: const Icon(Icons.exit_to_app_rounded,
                              color: Colors.white70, size: 18),
                          label: const Text('Quit',
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13)),
                        ),
                    ],
                  ),
                  // Locked start date info
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 0, 16, 6),
                    child: Row(
                      children: [
                        const Icon(Icons.lock_rounded,
                            color: Colors.white54, size: 12),
                        const SizedBox(width: 5),
                        Text(
                          '${_fmtDate(plan.startDate!)} → ${_fmtDate(plan.startDate!.add(const Duration(days: 6)))}',
                          style: TextStyle(
                              color:
                                  Colors.white.withValues(alpha: 0.7),
                              fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  // Progress bar
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 4, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${plan.checkedMeals} / ${plan.totalMeals} meals checked',
                              style: TextStyle(
                                  color: Colors.white
                                      .withValues(alpha: 0.9),
                                  fontSize: 12),
                            ),
                            Text(
                              '${(progress * 100).round()}%',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.25),
                            color: Colors.white,
                            minHeight: 8,
                          ),
                        ),
                        if (progress >= 1.0) ...[
                          const SizedBox(height: 8),
                          const Row(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              Icon(Icons.emoji_events_rounded,
                                  color: Colors.amber, size: 18),
                              SizedBox(width: 6),
                              Text('Plan Complete! Great work! 🎉',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Day list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 32),
              itemCount: plan.days.length,
              itemBuilder: (_, i) {
                final d = plan.days[i];
                return _DaySection(
                  day: d,
                  startDate: plan.startDate!,
                  isToday: _isToday(d.day),
                  goalColor: _goalColor,
                  checkIns: plan.checkIns,
                  analyzing: _analyzing,
                  onCheckTap: _onCheckTap,
                  onDidntFollowTap: _onDidntFollowTap,
                  onAddPhoto: _addPhoto,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Day Section ─────────────────────────────────────────────

class _DaySection extends StatelessWidget {
  final SavedDay day;
  final DateTime startDate;
  final bool isToday;
  final Color goalColor;
  final Map<String, MealCheckIn> checkIns;
  final Map<String, bool> analyzing;
  final Future<void> Function(SavedMeal meal, int day) onCheckTap;
  final Future<void> Function(SavedMeal meal, int day) onDidntFollowTap;
  final Future<void> Function(SavedMeal meal, int day, String source,
      {required bool isDeviation}) onAddPhoto;

  static const _dayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  const _DaySection({
    required this.day,
    required this.startDate,
    required this.isToday,
    required this.goalColor,
    required this.checkIns,
    required this.analyzing,
    required this.onCheckTap,
    required this.onDidntFollowTap,
    required this.onAddPhoto,
  });

  String _key(String type) => '${day.day}_$type';

  String get _dayDate {
    final d = startDate.add(Duration(days: day.day - 1));
    return '${d.day} ${_months[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final name = (day.day >= 1 && day.day <= 7)
        ? _dayNames[day.day - 1]
        : 'Day ${day.day}';
    final allChecked = day.meals
        .every((m) => checkIns[_key(m.type)]?.isChecked == true);
    final checkedCount = day.meals
        .where((m) => checkIns[_key(m.type)]?.isChecked == true)
        .length;

    // Days in the past are viewable but locked for new check-ins
    final now = DateTime.now();
    final dayDate = startDate.add(Duration(days: day.day - 1));
    final isPast = dayDate.isBefore(DateTime(now.year, now.month, now.day));
    final isFuture = dayDate.isAfter(DateTime(now.year, now.month, now.day));

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      elevation: isToday ? 4 : 2,
      shadowColor: isToday
          ? goalColor.withValues(alpha: 0.3)
          : Colors.black.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isToday
            ? BorderSide(color: goalColor, width: 2)
            : BorderSide.none,
      ),
      child: Theme(
        data: Theme.of(context)
            .copyWith(dividerColor: Colors.transparent),
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
              color: allChecked
                  ? goalColor
                  : isFuture
                      ? Colors.grey.shade200
                      : goalColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: allChecked
                  ? const Icon(Icons.check_rounded,
                      color: Colors.white, size: 22)
                  : isFuture
                      ? Icon(Icons.lock_rounded,
                          color: Colors.grey.shade400, size: 18)
                      : Text('${day.day}',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: goalColor)),
            ),
          ),
          title: Row(
            children: [
              Text(name,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isFuture
                          ? Colors.grey.shade400
                          : Colors.black87)),
              if (isToday) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: goalColor,
                      borderRadius: BorderRadius.circular(8)),
                  child: const Text('Today',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
          subtitle: Row(
            children: [
              Text(
                '$checkedCount/${day.meals.length} done',
                style: TextStyle(
                    color: isFuture
                        ? Colors.grey.shade400
                        : Colors.grey.shade500,
                    fontSize: 12),
              ),
              Text('  ·  ',
                  style: TextStyle(
                      color: Colors.grey.shade400, fontSize: 12)),
              Text(
                _dayDate,
                style: TextStyle(
                  color: isToday
                      ? goalColor
                      : isPast
                          ? Colors.grey.shade500
                          : Colors.grey.shade400,
                  fontSize: 12,
                  fontWeight: isToday
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
              if (isFuture) ...[
                const SizedBox(width: 6),
                Icon(Icons.lock_rounded,
                    size: 11, color: Colors.grey.shade400),
              ],
            ],
          ),
          iconColor: isFuture ? Colors.grey.shade400 : goalColor,
          collapsedIconColor: Colors.grey.shade400,
          children: day.meals
              .map((m) => _MealCheckInTile(
                    meal: m,
                    checkIn:
                        checkIns[_key(m.type)] ?? MealCheckIn(),
                    isAnalyzingChecked:
                        analyzing[_key(m.type)] ?? false,
                    isAnalyzingDeviation:
                        analyzing['${_key(m.type)}_dev'] ?? false,
                    goalColor: goalColor,
                    isLocked: isFuture,
                    onCheckTap: () => onCheckTap(m, day.day),
                    onDidntFollowTap: () =>
                        onDidntFollowTap(m, day.day),
                    onChangePhoto: (src) => onAddPhoto(m, day.day, src,
                        isDeviation: false),
                    onChangeDeviationPhoto: (src) =>
                        onAddPhoto(m, day.day, src, isDeviation: true),
                  ))
              .toList(),
        ),
      ),
    );
  }
}

// ─── Meal Check-In Tile ──────────────────────────────────────

class _MealCheckInTile extends StatefulWidget {
  final SavedMeal meal;
  final MealCheckIn checkIn;
  final bool isAnalyzingChecked;
  final bool isAnalyzingDeviation;
  final Color goalColor;
  final bool isLocked;
  final VoidCallback onCheckTap;
  final VoidCallback onDidntFollowTap;
  final void Function(String source) onChangePhoto;
  final void Function(String source) onChangeDeviationPhoto;

  const _MealCheckInTile({
    required this.meal,
    required this.checkIn,
    required this.isAnalyzingChecked,
    required this.isAnalyzingDeviation,
    required this.goalColor,
    required this.isLocked,
    required this.onCheckTap,
    required this.onDidntFollowTap,
    required this.onChangePhoto,
    required this.onChangeDeviationPhoto,
  });

  @override
  State<_MealCheckInTile> createState() => _MealCheckInTileState();
}

class _MealCheckInTileState extends State<_MealCheckInTile> {
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

  void _showChangePhoto(bool isDeviation) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  isDeviation ? 'Replace deviation photo' : 'Replace proof photo',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 16),
              ListTile(
                leading: Icon(Icons.camera_alt_rounded,
                    color: isDeviation
                        ? Colors.red.shade400
                        : widget.goalColor),
                title: const Text('Take a new photo'),
                onTap: () {
                  Navigator.pop(context);
                  isDeviation
                      ? widget.onChangeDeviationPhoto('camera')
                      : widget.onChangePhoto('camera');
                },
              ),
              ListTile(
                leading: Icon(Icons.photo_library_rounded,
                    color: isDeviation
                        ? Colors.red.shade400
                        : widget.goalColor),
                title: const Text('Choose from gallery'),
                onTap: () {
                  Navigator.pop(context);
                  isDeviation
                      ? widget.onChangeDeviationPhoto('gallery')
                      : widget.onChangePhoto('gallery');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = _bgColors[widget.meal.type] ?? Colors.grey.shade50;
    final icon =
        _typeIcons[widget.meal.type] ?? Icons.restaurant_rounded;
    final ci = widget.checkIn;
    final hasPhoto = ci.photoPath?.isNotEmpty == true;
    final hasDeviationPhoto = ci.deviationPhotoPath?.isNotEmpty == true;

    return Opacity(
      opacity: widget.isLocked ? 0.5 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Main row ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Checkbox
                  GestureDetector(
                    onTap:
                        widget.isLocked ? null : widget.onCheckTap,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: ci.isChecked
                            ? widget.goalColor
                            : Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: ci.isChecked
                              ? widget.goalColor
                              : Colors.grey.shade300,
                          width: 2,
                        ),
                      ),
                      child: ci.isChecked
                          ? const Icon(Icons.check_rounded,
                              color: Colors.white, size: 16)
                          : widget.isLocked
                              ? Icon(Icons.lock_rounded,
                                  color: Colors.grey.shade400,
                                  size: 14)
                              : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Meal info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(icon,
                                size: 13,
                                color: widget.goalColor),
                            const SizedBox(width: 4),
                            Text(
                              widget.meal.type,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: widget.goalColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(widget.meal.name,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold)),
                        if (widget.meal.nameZh.isNotEmpty)
                          Text(widget.meal.nameZh,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 3,
                          children: [
                            _chip('🔥 ${widget.meal.calories}',
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
                  // Right-side icons column
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Proof photo / loading
                      if (widget.isAnalyzingChecked)
                        const Padding(
                          padding: EdgeInsets.all(6),
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2),
                          ),
                        )
                      else if (hasPhoto)
                        IconButton(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.camera_alt_rounded,
                              color: widget.goalColor, size: 20),
                          tooltip: 'Change proof photo',
                          onPressed: widget.isLocked
                              ? null
                              : () => _showChangePhoto(false),
                        ),
                      const SizedBox(height: 4),
                      // "Didn't follow" icon
                      if (!widget.isLocked)
                        Tooltip(
                          message: ci.didntFollow
                              ? 'Didn\'t follow plan (tap to clear)'
                              : 'I didn\'t follow this meal',
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            icon: widget.isAnalyzingDeviation
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.red.shade400,
                                    ),
                                  )
                                : Icon(
                                    Icons.no_meals_rounded,
                                    size: 20,
                                    color: ci.didntFollow
                                        ? Colors.red.shade500
                                        : Colors.grey.shade400,
                                  ),
                            onPressed: widget.onDidntFollowTap,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Locked notice ────────────────────────────────
            if (widget.isLocked)
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Row(
                  children: [
                    Icon(Icons.lock_clock_rounded,
                        size: 13, color: Colors.grey.shade400),
                    const SizedBox(width: 5),
                    Text('Check-in only available on this day',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade400)),
                  ],
                ),
              ),

            // ── Proof photo + analysis ────────────────────────
            if (hasPhoto && !widget.isLocked) ...[
              _photoBlock(ci.photoPath!, ci.analysis,
                  widget.isAnalyzingChecked, widget.goalColor,
                  label: 'Proof photo'),
            ],

            // ── Deviation section ────────────────────────────
            if (ci.didntFollow) ...[
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: Row(
                  children: [
                    Icon(Icons.no_meals_rounded,
                        size: 14, color: Colors.red.shade400),
                    const SizedBox(width: 6),
                    Text('Didn\'t follow this meal',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.red.shade400)),
                    const Spacer(),
                    if (hasDeviationPhoto)
                      IconButton(
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.camera_alt_rounded,
                            size: 18,
                            color: Colors.red.shade400),
                        tooltip: 'Change photo',
                        onPressed: () => _showChangePhoto(true),
                      ),
                  ],
                ),
              ),
              if (hasDeviationPhoto)
                _photoBlock(
                    ci.deviationPhotoPath!,
                    ci.deviationAnalysis,
                    widget.isAnalyzingDeviation,
                    Colors.red.shade400,
                    label: 'What I ate instead'),
              if (!hasDeviationPhoto)
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(12, 4, 12, 10),
                  child: TextButton.icon(
                    onPressed: () => _showChangePhoto(true),
                    icon: Icon(Icons.add_a_photo_outlined,
                        size: 16, color: Colors.red.shade400),
                    label: Text('Upload photo of what you ate',
                        style: TextStyle(
                            color: Colors.red.shade400,
                            fontSize: 12)),
                  ),
                ),
            ],

            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _photoBlock(String path, FoodAnalysis? analysis,
      bool isAnalyzing, Color accent,
      {required String label}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w500)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              File(path),
              height: 130,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 80,
                color: Colors.grey.shade200,
                child: const Center(
                    child: Icon(Icons.broken_image_rounded)),
              ),
            ),
          ),
        ),
        if (isAnalyzing)
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: accent),
                ),
                const SizedBox(width: 8),
                Text('Analysing with Gemini…',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600)),
              ],
            ),
          ),
        if (analysis != null) _buildAnalysisCard(analysis, accent),
      ],
    );
  }

  Widget _buildAnalysisCard(FoodAnalysis a, Color accent) {
    final aligns = a.alignsWithGoal;
    final bg = aligns ? Colors.green.shade50 : Colors.orange.shade50;
    final border =
        aligns ? Colors.green.shade200 : Colors.orange.shade200;
    final color =
        aligns ? Colors.green.shade600 : Colors.orange.shade700;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  aligns
                      ? Icons.check_circle_rounded
                      : Icons.warning_amber_rounded,
                  color: color,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(a.detectedFood,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: color)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _pill('🔥 ${a.calories}', Colors.orange.shade100,
                    Colors.orange.shade800),
                _pill('P ${a.protein}', Colors.blue.shade100,
                    Colors.blue.shade800),
                _pill('C ${a.carbs}', Colors.amber.shade100,
                    Colors.amber.shade900),
                if (a.fibre.isNotEmpty)
                  _pill('Fibre ${a.fibre}', Colors.teal.shade50,
                      Colors.teal.shade700),
                _pill('F ${a.fat}', Colors.green.shade100,
                    Colors.green.shade800),
              ],
            ),
            if (a.feedback.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline_rounded,
                      size: 13, color: color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(a.feedback,
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                            height: 1.5)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color bg, Color fg) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: fg)),
      );

  Widget _pill(String label, Color bg, Color fg) => Container(
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
