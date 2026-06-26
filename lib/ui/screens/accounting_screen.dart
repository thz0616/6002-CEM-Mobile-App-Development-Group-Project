import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/repositories/accounting_repository.dart';
import '../../data/repositories/llm_repository.dart';
import '../../data/services/screen_capture_service.dart';
import '../../domain/models/account_transaction.dart';

class AccountingScreen extends ConsumerStatefulWidget {
  const AccountingScreen({super.key});

  @override
  ConsumerState<AccountingScreen> createState() => _AccountingScreenState();
}

class _AccountingScreenState extends ConsumerState<AccountingScreen>
    with WidgetsBindingObserver {
  static const Color _financeOrange = Color(0xFFFFA726);
  static const Color _financeButtonOrange = Color(0xFFFFA000);
  final ScreenCaptureService _captureService = ScreenCaptureService();
  final List<AccountTransaction> _transactions = [];
  AccountingSummary _summary = const AccountingSummary(income: 0, expense: 0);
  String _typeFilter = 'all';
  String _dateFilter = 'thisMonth';
  DateTimeRange? _customRange;
  bool _isCaptureModeActive = false;
  bool _isProcessing = false;
  String _status = 'Capture mode is inactive';

  static const List<String> _categories = [
    'food',
    'transport',
    'shopping',
    'bills',
    'entertainment',
    'health',
    'education',
    'salary',
    'other',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadTransactions();
    _consumePendingCapture();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _consumePendingCapture();
    }
  }

  Future<void> _loadTransactions() async {
    final filter = _activeFilter();
    final range = _currentDateRange();
    final repository = ref.read(accountingRepositoryProvider);
    final rows = await repository.list(filter: filter);
    final summary = await repository.summary(
      filter: AccountingFilter(startDate: range?.start, endDate: range?.end),
    );
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _transactions
        ..clear()
        ..addAll(rows);
    });
  }

  Future<void> _showAllTransactions() async {
    setState(() {
      _typeFilter = 'all';
      _dateFilter = 'all';
      _customRange = null;
    });
    await _loadTransactions();
  }

  AccountingFilter _activeFilter() {
    final range = _currentDateRange();
    return AccountingFilter(
      type: _typeFilter,
      startDate: range?.start,
      endDate: range?.end,
    );
  }

  DateTimeRange? _currentDateRange() {
    final now = DateTime.now();
    switch (_dateFilter) {
      case 'today':
        final start = DateTime(now.year, now.month, now.day);
        return DateTimeRange(
          start: start,
          end: start.add(const Duration(days: 1)),
        );
      case 'thisWeek':
        final startOfDay = DateTime(now.year, now.month, now.day);
        final start = startOfDay.subtract(Duration(days: now.weekday - 1));
        return DateTimeRange(
          start: start,
          end: start.add(const Duration(days: 7)),
        );
      case 'thisMonth':
        final start = DateTime(now.year, now.month);
        final end = DateTime(now.year, now.month + 1);
        return DateTimeRange(start: start, end: end);
      case 'lastMonth':
        final start = DateTime(now.year, now.month - 1);
        final end = DateTime(now.year, now.month);
        return DateTimeRange(start: start, end: end);
      case 'custom':
        if (_customRange == null) return null;
        final start = DateTime(
          _customRange!.start.year,
          _customRange!.start.month,
          _customRange!.start.day,
        );
        final endBase = _customRange!.end;
        final end = DateTime(
          endBase.year,
          endBase.month,
          endBase.day,
        ).add(const Duration(days: 1));
        return DateTimeRange(start: start, end: end);
      default:
        return null;
    }
  }

  String _dateFilterLabel() {
    switch (_dateFilter) {
      case 'today':
        return 'Today';
      case 'thisWeek':
        return 'This Week';
      case 'thisMonth':
        return 'This Month';
      case 'lastMonth':
        return 'Last Month';
      case 'custom':
        if (_customRange == null) return 'Custom';
        return 'Custom: ${_formatDate(_customRange!.start)} - ${_formatDate(_customRange!.end)}';
      default:
        return 'All Time';
    }
  }

  String _formatDate(DateTime value) {
    return value.toIso8601String().split('T').first;
  }

  Future<void> _startCaptureMode() async {
    if (Platform.isAndroid) {
      await Permission.notification.request();
      final canDrawOverlays = await _captureService.canDrawOverlays();
      if (!canDrawOverlays) {
        if (!mounted) return;
        final openSettings = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Overlay Permission Required'),
            content: const Text(
              'Accounting needs permission to display a floating capture button over other apps.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
        if (openSettings == true) {
          await _captureService.openOverlaySettings();
          if (!mounted) return;
          setState(
            () => _status =
                'Enable Display over other apps, then return and start capture mode again.',
          );
        }
        return;
      }
    }

    try {
      final started = await _captureService.startCaptureMode();
      if (!mounted) return;
      setState(() {
        _isCaptureModeActive = started;
        _status = started
            ? 'Capture mode is active. Use the floating CAP button.'
            : 'Capture mode did not start';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Failed to start capture mode: $e');
    }
  }

  Future<void> _stopCaptureMode() async {
    await _captureService.stopCaptureMode();
    if (!mounted) return;
    setState(() {
      _isCaptureModeActive = false;
      _status = 'Capture mode is inactive';
    });
  }

  Future<void> _uploadReceiptImage() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null) return;
    await _processCapture(image.path);
  }

  Future<void> _addManualTransaction() async {
    final today = DateTime.now().toIso8601String().split('T').first;
    final saved = await _showConfirmationDialog(
      {
        'type': 'expense',
        'amount': 0,
        'currency': 'MYR',
        'category': 'other',
        'merchant': '',
        'transactionDate': today,
        'note': '',
      },
      null,
      null,
      title: 'Add Transaction',
    );

    if (saved == true) {
      await _showAllTransactions();
      if (!mounted) return;
      setState(() => _status = 'Transaction saved. Showing all records.');
    }
  }

  Future<void> _editTransaction(AccountTransaction transaction) async {
    final saved = await _showConfirmationDialog(
      _draftFromTransaction(transaction),
      transaction.sourceImagePath,
      transaction.rawLlmJson,
      existing: transaction,
      title: 'Edit Transaction',
    );

    if (saved == true) {
      await _showAllTransactions();
      if (!mounted) return;
      setState(() => _status = 'Transaction updated. Showing all records.');
    }
  }

  Map<String, dynamic> _draftFromTransaction(AccountTransaction transaction) {
    return {
      'type': transaction.type,
      'amount': transaction.amount,
      'currency': transaction.currency,
      'category': transaction.category,
      'merchant': transaction.merchant,
      'transactionDate': _formatDate(transaction.transactionDate),
      'note': transaction.note,
    };
  }

  Future<void> _consumePendingCapture() async {
    if (_isProcessing) return;
    final path = await _captureService.consumePendingCapture();
    if (path == null || path.isEmpty) return;
    await _processCapture(path);
  }

  Future<void> _processCapture(String imagePath) async {
    final llmRepository = ref.read(llmRepositoryProvider);
    final modelName = llmRepository.model;
    if (!mounted) return;
    setState(() {
      _isProcessing = true;
      _status = 'Analyzing screenshot with $modelName...';
    });

    try {
      final shouldAnalyze = await _showCapturedImageDialog(imagePath);
      if (shouldAnalyze != true) {
        if (!mounted) return;
        setState(() => _status = 'Screenshot review cancelled');
        return;
      }

      final bytes = await File(imagePath).readAsBytes();
      final base64Image = base64Encode(bytes);
      final raw = await llmRepository.generateWithImages(
        _accountingPrompt(),
        [base64Image],
      );

      final draft = _parseDraft(raw);

      if (!mounted) return;
      final saved = await _showConfirmationDialog(draft, imagePath, raw);
      if (saved == true) {
        await _showAllTransactions();
        if (!mounted) return;
        setState(() => _status = 'Transaction saved. Showing all records.');
      } else {
        setState(() => _status = 'Capture ignored');
      }
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      setState(() => _status = 'Failed to analyze screenshot: $message');
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<bool?> _showCapturedImageDialog(String imagePath) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Captured Screenshot'),
          content: SizedBox(
            width: double.maxFinite,
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Image.file(File(imagePath), fit: BoxFit.contain),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Analyze'),
            ),
          ],
        );
      },
    );
  }

  String _accountingPrompt() {
    final today = DateTime.now().toIso8601String().split('T').first;
    return '''
Analyze this screenshot as a personal accounting entry.

Return ONLY one valid JSON object. Do not include markdown, comments, explanations, or extra text.

Required schema:
{
  "type": "expense",
  "amount": 12.50,
  "currency": "MYR",
  "category": "food",
  "merchant": "McDonald's",
  "transactionDate": "2026-05-27",
  "note": "Lunch payment"
}

Rules:
- Output exactly one JSON object with exactly these keys: type, amount, currency, category, merchant, transactionDate, note.
- type must be exactly "income" or "expense".
- amount must be a JSON number, not a string. Example: 12.50
- currency must be a 3-letter uppercase code. Example: "MYR"
- category must be exactly one of: food, transport, shopping, bills, entertainment, health, education, salary, other.
- merchant must be a short string. Example: "Touch 'n Go" or "Grab".
- transactionDate must be ISO date format YYYY-MM-DD only. Example: "2026-05-27". Do not use DD/MM/YYYY, MM/DD/YYYY, words, slashes, or timestamps.
- note must be a short English string. Example: "Receipt payment".
- Use "expense" unless the screenshot clearly shows money received.
- Default currency to "MYR" if no currency is visible.
- Use "$today" if no transaction date is visible.
- If the amount is unclear, set amount to 0.
- Keep all text in English.

Valid output example:
{"type":"expense","amount":12.50,"currency":"MYR","category":"food","merchant":"McDonald's","transactionDate":"2026-05-27","note":"Lunch payment"}
''';
  }

  Map<String, dynamic> _parseDraft(String raw) {
    final cleaned = _extractJson(raw);
    final decoded = jsonDecode(cleaned);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('LLM response is not a JSON object');
    }
    return decoded;
  }

  String _extractJson(String raw) {
    var text = raw.trim();
    if (text.startsWith('```json')) {
      text = text.substring(7);
    } else if (text.startsWith('```')) {
      text = text.substring(3);
    }
    if (text.endsWith('```')) {
      text = text.substring(0, text.length - 3);
    }

    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) {
      throw const FormatException('No JSON object found in LLM response');
    }
    return text.substring(start, end + 1);
  }

  DateTime? _parseTransactionDate(String input) {
    final value = input.trim();
    final iso = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (iso.hasMatch(value)) {
      return DateTime.tryParse(value);
    }

    final slashDate = RegExp(
      r'^(\d{1,2})/(\d{1,2})/(\d{4})$',
    ).firstMatch(value);
    if (slashDate != null) {
      final first = int.tryParse(slashDate.group(1)!);
      final second = int.tryParse(slashDate.group(2)!);
      final year = int.tryParse(slashDate.group(3)!);
      if (first != null && second != null && year != null) {
        final day = first > 12 ? first : second;
        final month = first > 12 ? second : first;
        return DateTime.tryParse(
          '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
        );
      }
    }

    return DateTime.tryParse(value);
  }

  Future<bool?> _showConfirmationDialog(
    Map<String, dynamic> draft,
    String? imagePath,
    String? rawLlmJson, {
    AccountTransaction? existing,
    String title = 'Confirm Transaction',
  }) {
    String type = draft['type'] == 'income' ? 'income' : 'expense';
    String category = _categories.contains(draft['category'])
        ? draft['category']
        : 'other';
    final amountController = TextEditingController(
      text: (draft['amount'] is num)
          ? (draft['amount'] as num).toString()
          : draft['amount']?.toString() ?? '0',
    );
    final currencyController = TextEditingController(
      text: draft['currency']?.toString().isNotEmpty == true
          ? draft['currency'].toString()
          : 'MYR',
    );
    final merchantController = TextEditingController(
      text: draft['merchant']?.toString() ?? '',
    );
    final dateController = TextEditingController(
      text: draft['transactionDate']?.toString().isNotEmpty == true
          ? draft['transactionDate'].toString()
          : DateTime.now().toIso8601String().split('T').first,
    );
    final noteController = TextEditingController(
      text: draft['note']?.toString() ?? '',
    );

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(title),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'expense', label: Text('Expense')),
                        ButtonSegment(value: 'income', label: Text('Income')),
                      ],
                      selected: {type},
                      onSelectionChanged: (values) {
                        setDialogState(() => type = values.first);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Amount'),
                    ),
                    TextField(
                      controller: currencyController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(labelText: 'Currency'),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: category,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: _categories
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => category = value);
                        }
                      },
                    ),
                    TextField(
                      controller: merchantController,
                      decoration: const InputDecoration(labelText: 'Merchant'),
                    ),
                    TextField(
                      controller: dateController,
                      decoration: const InputDecoration(labelText: 'Date'),
                    ),
                    TextField(
                      controller: noteController,
                      decoration: const InputDecoration(labelText: 'Note'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final amount = double.tryParse(
                      amountController.text.trim(),
                    );
                    final date = _parseTransactionDate(dateController.text);
                    if (amount == null || date == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Enter a valid amount and date.'),
                        ),
                      );
                      return;
                    }

                    final now = DateTime.now();
                    final transaction = AccountTransaction(
                      id: existing?.id,
                      type: type,
                      amount: amount,
                      currency: currencyController.text.trim().isEmpty
                          ? 'MYR'
                          : currencyController.text.trim().toUpperCase(),
                      category: category,
                      merchant: merchantController.text.trim(),
                      transactionDate: date,
                      note: noteController.text.trim(),
                      sourceImagePath: imagePath,
                      rawLlmJson: rawLlmJson,
                      createdAt: existing?.createdAt ?? now,
                      updatedAt: now,
                    );
                    final repository = ref.read(accountingRepositoryProvider);
                    if (existing == null) {
                      await repository.insert(transaction);
                    } else {
                      await repository.update(transaction);
                    }
                    if (context.mounted) {
                      Navigator.pop(context, true);
                    }
                  },
                  child: Text(existing == null ? 'Save' : 'Update'),
                ),
                if (existing != null)
                  TextButton(
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Delete Transaction'),
                          content: const Text(
                            'This transaction will be permanently deleted.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true && existing.id != null) {
                        await ref
                            .read(accountingRepositoryProvider)
                            .delete(existing.id!);
                        if (context.mounted) {
                          Navigator.pop(context, true);
                        }
                      }
                    },
                    child: const Text('Delete'),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _changeDateFilter(String value) async {
    if (value == 'custom') {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 5),
        lastDate: DateTime(now.year + 1),
        initialDateRange:
            _customRange ??
            DateTimeRange(
              start: DateTime(now.year, now.month, 1),
              end: DateTime(now.year, now.month, now.day),
            ),
      );
      if (picked == null) return;
      _customRange = picked;
    }

    setState(() => _dateFilter = value);
    await _loadTransactions();
  }

  Widget _buildSummaryCards() {
    return Row(
      children: [
        _SummaryCard(
          label: 'Income',
          value: '+MYR ${_summary.income.toStringAsFixed(2)}',
          color: Colors.green,
        ),
        const SizedBox(width: 8),
        _SummaryCard(
          label: 'Expense',
          value: '-MYR ${_summary.expense.toStringAsFixed(2)}',
          color: Colors.red,
        ),
        const SizedBox(width: 8),
        _SummaryCard(
          label: 'Net',
          value: 'MYR ${_summary.net.toStringAsFixed(2)}',
          color: _summary.net >= 0 ? Colors.green : Colors.red,
        ),
      ],
    );
  }

  Widget _buildFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'all', label: Text('All')),
            ButtonSegment(value: 'expense', label: Text('Expense')),
            ButtonSegment(value: 'income', label: Text('Income')),
          ],
          selected: {_typeFilter},
          onSelectionChanged: (values) async {
            setState(() => _typeFilter = values.first);
            await _loadTransactions();
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _dateFilter,
          decoration: InputDecoration(
            labelText: 'Date Range: ${_dateFilterLabel()}',
          ),
          items: [
            const DropdownMenuItem(value: 'all', child: Text('All Time')),
            const DropdownMenuItem(value: 'today', child: Text('Today')),
            const DropdownMenuItem(value: 'thisWeek', child: Text('This Week')),
            const DropdownMenuItem(
              value: 'thisMonth',
              child: Text('This Month'),
            ),
            const DropdownMenuItem(
              value: 'lastMonth',
              child: Text('Last Month'),
            ),
            const DropdownMenuItem(
              value: 'custom',
              child: Text('Custom Range'),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              _changeDateFilter(value);
            }
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final financeTheme = theme.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _financeOrange,
        brightness: theme.brightness,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _financeButtonOrange,
          foregroundColor: Colors.white,
        ),
      ),
    );

    return Theme(
      data: financeTheme,
      child: Scaffold(
        appBar: AppBar(title: const Text('Accounting')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isProcessing || _isCaptureModeActive
                          ? null
                          : _startCaptureMode,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start Capture'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isProcessing || !_isCaptureModeActive
                          ? null
                          : _stopCaptureMode,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isProcessing ? null : _uploadReceiptImage,
                      icon: const Icon(Icons.image),
                      label: const Text('Upload Receipt'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isProcessing ? null : _addManualTransaction,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Manually'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_isProcessing) const LinearProgressIndicator(),
              Text(_status, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 16),
              _buildSummaryCards(),
              const SizedBox(height: 16),
              _buildFilters(),
              const SizedBox(height: 16),
              Text(
                'Recent Transactions',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _transactions.isEmpty
                    ? const Center(child: Text('No transactions saved yet.'))
                    : ListView.separated(
                        itemCount: _transactions.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = _transactions[index];
                          final sign = item.type == 'income' ? '+' : '-';
                          final date = item.transactionDate
                              .toIso8601String()
                              .split('T')
                              .first;
                          return ListTile(
                            onTap: () => _editTransaction(item),
                            leading: CircleAvatar(
                              backgroundColor: item.type == 'income'
                                  ? Colors.green
                                  : Colors.red,
                              child: Icon(
                                item.type == 'income'
                                    ? Icons.arrow_downward
                                    : Icons.arrow_upward,
                                color: Colors.white,
                              ),
                            ),
                            title: Text(
                              item.merchant.isEmpty
                                  ? item.category
                                  : item.merchant,
                            ),
                            subtitle: Text(
                              '$date - ${item.category}${item.note.isEmpty ? '' : ' - ${item.note}'}',
                            ),
                            trailing: Text(
                              '$sign${item.currency} ${item.amount.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: item.type == 'income'
                                    ? Colors.green
                                    : Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
