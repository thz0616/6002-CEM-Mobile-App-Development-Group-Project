import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/repositories/settings_repository.dart';
import '../../data/services/sms_scam_detection_service.dart';

class SmsScamDetectionScreen extends ConsumerStatefulWidget {
  const SmsScamDetectionScreen({super.key});

  @override
  ConsumerState<SmsScamDetectionScreen> createState() =>
      _SmsScamDetectionScreenState();
}

class _SmsScamDetectionScreenState
    extends ConsumerState<SmsScamDetectionScreen>
    with WidgetsBindingObserver {
  static const Color _financeOrange = Color(0xFFFFA726);
  static const Color _financeButtonOrange = Color(0xFFFFA000);
  final List<SmsScamDetectionRecord> _records = [];
  bool _isLoading = false;
  bool _scamOnly = false;
  bool _permissionsRequested = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadRecords();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        _loadRecords();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestRequiredPermissions();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadRecords();
    }
  }

  Future<void> _requestRequiredPermissions() async {
    if (_permissionsRequested || !mounted) return;
    _permissionsRequested = true;

    final smsStatus = await Permission.sms.status;
    final notificationStatus = await Permission.notification.status;

    final smsGranted = smsStatus.isGranted
        ? smsStatus
        : await Permission.sms.request();
    final notificationGranted =
        (notificationStatus.isGranted || notificationStatus.isLimited)
        ? notificationStatus
        : await Permission.notification.request();

    if (!mounted) return;
    if (!smsGranted.isGranted ||
        !(notificationGranted.isGranted || notificationGranted.isLimited)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SMS and Notification permissions are required'),
        ),
      );
    }
  }

  Future<void> _loadRecords() async {
    if (_isLoading || !mounted) return;
    setState(() => _isLoading = true);
    try {
      final rows = await ref.read(smsScamDetectionServiceProvider).getRecords();
      if (!mounted) return;
      setState(() {
        _records
          ..clear()
          ..addAll(rows);
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _setEnabled(bool enabled) async {
    final notifier = ref.read(settingsProvider.notifier);
    final service = ref.read(smsScamDetectionServiceProvider);

    if (!enabled) {
      notifier.setSmsScamDetectionEnabled(false);
      await service.setEnabled(false);
      return;
    }

    final smsStatus = await Permission.sms.request();
    final notifStatus = await Permission.notification.request();
    if (!smsStatus.isGranted ||
        !(notifStatus.isGranted || notifStatus.isLimited)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SMS and Notification permissions are required'),
        ),
      );
      return;
    }

    final updated = await service.setEnabled(true);
    if (!mounted) return;
    if (updated) {
      notifier.setSmsScamDetectionEnabled(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update SMS scam detection.')),
      );
    }
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _showRecordDetails(SmsScamDetectionRecord record) async {
    final result = record.isScam ? 'Scam' : 'Safe';
    final probability = '${(record.probability * 100).toStringAsFixed(1)}%';
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('SMS Detection Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _DetailRow(
                label: 'Sender',
                value: record.sender.isEmpty ? 'Unknown sender' : record.sender,
              ),
              _DetailRow(label: 'Detection Result', value: result),
              _DetailRow(label: 'Scam Probability', value: probability),
              _DetailRow(
                label: 'Detected At',
                value: _formatDate(record.detectedAt),
              ),
              const SizedBox(height: 12),
              Text('Message', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              SelectableText(record.body),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteRecord(SmsScamDetectionRecord record) async {
    final service = ref.read(smsScamDetectionServiceProvider);
    final removed = await service.deleteRecord(record);
    if (!mounted) return;
    if (!removed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete SMS message.')),
      );
      return;
    }

    setState(() {
      _records.removeWhere(
        (item) =>
            item.sender == record.sender &&
            item.body == record.body &&
            item.probability == record.probability &&
            item.isScam == record.isScam &&
            item.detectedAt == record.detectedAt,
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('SMS message deleted.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final visibleRecords = _scamOnly
        ? _records.where((item) => item.isScam).toList()
        : _records;
    final scamCount = _records.where((item) => item.isScam).length;

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
        appBar: AppBar(title: const Text('SMS Scam Detection')),
        body: RefreshIndicator(
          onRefresh: _loadRecords,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('SMS Scam Detection'),
                subtitle: const Text(
                  'Detect incoming SMS content and warn on suspicious messages',
                ),
                value: settings.smsScamDetectionEnabled,
                activeThumbColor: _financeButtonOrange,
                activeTrackColor: _financeButtonOrange.withValues(alpha: 0.45),
                inactiveThumbColor: Theme.of(context).colorScheme.outline,
                inactiveTrackColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                onChanged: _setEnabled,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _SummaryTile(
                      label: 'Total',
                      value: _records.length.toString(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SummaryTile(
                      label: 'Scam',
                      value: scamCount.toString(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => setState(() => _scamOnly = false),
                      icon: const Icon(Icons.list),
                      label: const Text('All Messages'),
                      style: _scamOnly
                          ? FilledButton.styleFrom(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.onSurface,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => setState(() => _scamOnly = true),
                      icon: const Icon(Icons.warning),
                      label: const Text('Scam Only'),
                      style: _scamOnly
                          ? null
                          : FilledButton.styleFrom(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.onSurface,
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_isLoading)
                const LinearProgressIndicator()
              else if (visibleRecords.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: Center(
                    child: Text(
                      _scamOnly
                          ? 'No scam messages detected yet.'
                          : 'No SMS detection records yet.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                )
              else
                ...visibleRecords.map(
                  (record) => Dismissible(
                    key: ValueKey(
                      '${record.sender}|${record.body}|${record.detectedAt.millisecondsSinceEpoch}',
                    ),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (_) async {
                      return await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Delete message?'),
                              content: const Text(
                                'This will remove the message from the list.',
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
                          ) ??
                          false;
                    },
                    onDismissed: (_) => _deleteRecord(record),
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.delete_outline,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                    child: Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        onTap: () => _showRecordDetails(record),
                        leading: Icon(
                          record.isScam
                              ? Icons.warning_amber
                              : Icons.check_circle_outline,
                          color: record.isScam
                              ? Theme.of(context).colorScheme.error
                              : Colors.green,
                        ),
                        title: Text(
                          record.sender.isEmpty
                              ? 'Unknown sender'
                              : record.sender,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(record.body),
                            const SizedBox(height: 8),
                            Text(
                              '${(record.probability * 100).toStringAsFixed(1)}% scam probability | ${_formatDate(record.detectedAt)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        isThreeLine: true,
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
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 2),
          SelectableText(value),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
        ],
      ),
    );
  }
}
