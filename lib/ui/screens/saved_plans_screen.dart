import 'package:flutter/material.dart';
import '../../data/services/plan_storage_service.dart';
import 'plan_checkin_screen.dart';

class SavedPlansScreen extends StatefulWidget {
  const SavedPlansScreen({super.key});

  @override
  State<SavedPlansScreen> createState() => _SavedPlansScreenState();
}

class _SavedPlansScreenState extends State<SavedPlansScreen> {
  final _storage = PlanStorageService();
  late Future<List<SavedPlan>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = _storage.loadAll();
    });
  }

  Future<void> _delete(SavedPlan plan) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Plan?'),
        content: Text(
            'Delete "${plan.planTitle}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _storage.delete(plan.id);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Meal Plans'),
        backgroundColor: const Color(0xFF1B5E20),
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<SavedPlan>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final plans = snap.data ?? [];
          if (plans.isEmpty) return _buildEmpty();
          return RefreshIndicator(
            onRefresh: () async => _reload(),
              child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: plans.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: 12),
              itemBuilder: (_, i) => _PlanCard(
                plan: plans[i],
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          PlanCheckInScreen(planId: plans[i].id),
                    ),
                  );
                  _reload();
                },
                onDelete: () => _delete(plans[i]),
                onStartDateSet: (date) async {
                  plans[i].startDate = date;
                  await _storage.save(plans[i]);
                  _reload();
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.calendar_month_rounded,
                  size: 72, color: Colors.green.shade300),
            ),
            const SizedBox(height: 28),
            const Text(
              'No Saved Plans',
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'Generate a 7-Day Macro Plan and tap the\nbookmark icon to save it here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, color: Colors.grey.shade600, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Plan Card ───────────────────────────────────────────────

class _PlanCard extends StatefulWidget {
  final SavedPlan plan;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final Future<void> Function(DateTime) onStartDateSet;

  const _PlanCard({
    required this.plan,
    required this.onTap,
    required this.onDelete,
    required this.onStartDateSet,
  });

  @override
  State<_PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<_PlanCard> {
  Future<void> _pickStartDate() async {
    // Once set, start date is locked — cannot be changed.
    if (widget.plan.startDate != null) return;

    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Select Plan Start Date (Day 1)',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: Color(widget.plan.goalColor),
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;

    // Confirm lock
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Lock Start Date?'),
        content: Text(
          'Start date will be set to ${_fmtDate(picked)}.\n\nThis cannot be changed once confirmed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(widget.plan.goalColor),
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirm == true) await widget.onStartDateSet(picked);
  }

  @override
  Widget build(BuildContext context) {
    final goalColor = Color(widget.plan.goalColor);
    final plan = widget.plan;
    final progress =
        plan.totalMeals == 0 ? 0.0 : plan.checkedMeals / plan.totalMeals;
    final progressPct = (progress * 100).round();

    return Card(
      elevation: 3,
      shadowColor: goalColor.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Colored header strip
            Container(
              decoration: BoxDecoration(
                color: goalColor,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.calendar_month_rounded,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plan.planTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${plan.goalLabel} · Saved ${_fmtDate(plan.savedAt)}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: plan.isActive
                          ? Colors.white.withValues(alpha: 0.25)
                          : Colors.black.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      plan.isActive ? 'Active' : 'Quit',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            // Body
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Start Date row ──────────────────────────
                  InkWell(
                    onTap: plan.startDate == null ? _pickStartDate : null,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: plan.startDate != null
                            ? goalColor.withValues(alpha: 0.08)
                            : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: plan.startDate != null
                              ? goalColor.withValues(alpha: 0.3)
                              : Colors.orange.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            plan.startDate != null
                                ? Icons.lock_rounded
                                : Icons.event_rounded,
                            size: 16,
                            color: plan.startDate != null
                                ? goalColor
                                : Colors.orange.shade600,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              plan.startDate != null
                                  ? 'Starts ${_fmtDate(plan.startDate!)}  →  Ends ${_fmtDate(plan.startDate!.add(const Duration(days: 6)))}'
                                  : 'Tap to set start date (required before check-in)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: plan.startDate != null
                                    ? goalColor
                                    : Colors.orange.shade700,
                              ),
                            ),
                          ),
                          if (plan.startDate == null)
                            Icon(Icons.chevron_right_rounded,
                                size: 16,
                                color: Colors.orange.shade400),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // ── Progress ──────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Progress',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '${plan.checkedMeals}/${plan.totalMeals} meals ($progressPct%)',
                        style: TextStyle(
                          fontSize: 12,
                          color: goalColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.grey.shade200,
                      color: goalColor,
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 14),
                  // ── Macro pills ───────────────────────────
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (plan.dailyCalories.isNotEmpty)
                        _pill('🔥 ${plan.dailyCalories}',
                            Colors.orange.shade50, Colors.orange.shade700),
                      if (plan.macros['protein'] != null)
                        _pill('P ${plan.macros['protein']}',
                            Colors.blue.shade50, Colors.blue.shade700),
                      if (plan.macros['carbs'] != null)
                        _pill('C ${plan.macros['carbs']}',
                            Colors.amber.shade50, Colors.amber.shade800),
                      if (plan.macros['fat'] != null)
                        _pill('F ${plan.macros['fat']}',
                            Colors.green.shade50, Colors.green.shade700),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // ── Actions ───────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: widget.onDelete,
                        icon: Icon(Icons.delete_outline_rounded,
                            size: 16, color: Colors.red.shade400),
                        label: Text('Delete',
                            style: TextStyle(
                                color: Colors.red.shade400, fontSize: 13)),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: widget.onTap,
                        icon: const Icon(Icons.checklist_rounded, size: 16),
                        label: const Text('Check In'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: goalColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          textStyle: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String label, Color bg, Color fg) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(12)),
        child: Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
      );

  String _fmtDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}
