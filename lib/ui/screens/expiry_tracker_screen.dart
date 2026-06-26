import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import '../../data/services/expiry_storage_service.dart';
import '../../data/services/llm_service.dart';

// ─── Main Screen ─────────────────────────────────────────────

class ExpiryTrackerScreen extends StatefulWidget {
  const ExpiryTrackerScreen({super.key});

  @override
  State<ExpiryTrackerScreen> createState() =>
      _ExpiryTrackerScreenState();
}

class _ExpiryTrackerScreenState extends State<ExpiryTrackerScreen> {
  final _storage = ExpiryStorageService();
  late Future<List<ExpiryItem>> _future;

  static const _themeColor = Color(0xFFE53935);

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

  Future<void> _delete(ExpiryItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Item?'),
        content: Text('Remove "${item.name}" from your tracker?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await _storage.delete(item.id);
      _reload();
    }
  }

  Future<void> _addItem() async {
    final result = await Navigator.push<ExpiryItem>(
      context,
      MaterialPageRoute(builder: (_) => const _ScanScreen()),
    );
    if (result != null) {
      await _storage.save(result);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Expiry Tracker'),
        backgroundColor: _themeColor,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addItem,
        backgroundColor: _themeColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.document_scanner_rounded),
        label: const Text('Scan Package'),
      ),
      body: FutureBuilder<List<ExpiryItem>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? [];
          if (items.isEmpty) return _buildEmpty();
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: items.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: 10),
              itemBuilder: (_, i) => _ExpiryCard(
                item: items[i],
                onDelete: () => _delete(items[i]),
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
                  color: Colors.red.shade50, shape: BoxShape.circle),
              child: Icon(Icons.timer_rounded,
                  size: 72, color: Colors.red.shade200),
            ),
            const SizedBox(height: 28),
            const Text('No Items Tracked',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(
              'Tap "Scan Package" to photograph a food label.\nGemini will read the expiry date automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Expiry Card ─────────────────────────────────────────────

class _ExpiryCard extends StatefulWidget {
  final ExpiryItem item;
  final VoidCallback onDelete;

  const _ExpiryCard({required this.item, required this.onDelete});

  @override
  State<_ExpiryCard> createState() => _ExpiryCardState();
}

class _ExpiryCardState extends State<_ExpiryCard> {
  bool _showAdvice = false;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  Color get _statusColor {
    final d = widget.item.daysUntilExpiry;
    if (d < 0) return Colors.red.shade600;
    if (d <= 3) return Colors.orange.shade600;
    if (d <= 7) return Colors.amber.shade700;
    return Colors.green.shade600;
  }

  Color get _statusBg {
    final d = widget.item.daysUntilExpiry;
    if (d < 0) return Colors.red.shade50;
    if (d <= 3) return Colors.orange.shade50;
    if (d <= 7) return Colors.amber.shade50;
    return Colors.green.shade50;
  }

  String _fmtDate(DateTime dt) =>
      '${dt.day} ${_months[dt.month - 1]} ${dt.year}';

  String _categoryLabel(String cat) => switch (cat) {
        'dairy' => '🥛 Dairy',
        'meat' => '🥩 Meat',
        'bread' => '🍞 Bread',
        'beverage' => '🥤 Beverage',
        'canned' => '🥫 Canned',
        'frozen' => '🧊 Frozen',
        'produce' => '🥬 Produce',
        'condiment' => '🫙 Condiment',
        'snack' => '🍪 Snack',
        _ => '🛒 Other',
      };

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final hasPhoto = item.photoPath?.isNotEmpty == true;
    final hasAdvice = item.storageAdvice.isNotEmpty;

    return Card(
      elevation: 2,
      shadowColor: _statusColor.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: _statusColor.withValues(alpha: 0.35), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ─────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: _statusBg,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16)),
            ),
            padding:
                const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: [
                // Photo thumbnail
                if (hasPhoto)
                  Container(
                    width: 52,
                    height: 52,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: _statusColor.withValues(alpha: 0.3)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(
                        File(item.photoPath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                            Icons.image_not_supported_rounded,
                            color: Colors.grey.shade400),
                      ),
                    ),
                  ),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _categoryLabel(item.category),
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _statusColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        item.isExpired
                            ? '✗'
                            : '${item.daysUntilExpiry}d',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        item.isExpired ? 'Expired' : 'left',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 9),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // ── Date row ────────────────────────────────────────
          Padding(
            padding:
                const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                Icon(Icons.event_rounded,
                    size: 14, color: _statusColor),
                const SizedBox(width: 6),
                Text(
                  'Expires: ${_fmtDate(item.expiryDate)}',
                  style: TextStyle(
                      fontSize: 13,
                      color: _statusColor,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                Text(
                  '· ${item.statusLabel}',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          // ── Storage advice ───────────────────────────────────
          if (hasAdvice) ...[
            InkWell(
              onTap: () =>
                  setState(() => _showAdvice = !_showAdvice),
              child: Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  children: [
                    Icon(Icons.lightbulb_rounded,
                        size: 14,
                        color: Colors.amber.shade700),
                    const SizedBox(width: 6),
                    Text(
                      'Storage Tip',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.amber.shade800),
                    ),
                    const Spacer(),
                    Icon(
                      _showAdvice
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: Colors.grey.shade400,
                    ),
                  ],
                ),
              ),
            ),
            if (_showAdvice)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: Colors.amber.shade200),
                ),
                child: Text(
                  item.storageAdvice,
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                      height: 1.6),
                ),
              ),
          ],
          // ── Actions ─────────────────────────────────────────
          Padding(
            padding:
                const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: widget.onDelete,
                  icon: Icon(Icons.delete_outline_rounded,
                      size: 16, color: Colors.red.shade400),
                  label: Text('Delete',
                      style: TextStyle(
                          color: Colors.red.shade400,
                          fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Scan Screen ─────────────────────────────────────────────

enum _ScanStep { idle, scanning, review, gettingAdvice }

class _ScanScreen extends StatefulWidget {
  const _ScanScreen();

  @override
  State<_ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<_ScanScreen> {
  _ScanStep _step = _ScanStep.idle;
  String? _photoPath;
  String _error = '';

  // Form values (editable by user)
  final _nameController = TextEditingController();
  String _category = 'other';
  DateTime? _expiryDate;
  String _storageAdvice = '';
  bool _wasBlurry = false;
  bool _usedFallback = false;
  List<String> _datesFound = [];

  static const _themeColor = Color(0xFFE53935);
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static const _categories = [
    ('dairy', '🥛 Dairy'),
    ('meat', '🥩 Meat'),
    ('bread', '🍞 Bread'),
    ('beverage', '🥤 Beverage'),
    ('canned', '🥫 Canned'),
    ('frozen', '🧊 Frozen'),
    ('produce', '🥬 Produce'),
    ('condiment', '🫙 Condiment'),
    ('snack', '🍪 Snack'),
    ('other', '🛒 Other'),
  ];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // ─── Pick image ─────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
        source: source, imageQuality: 85);
    if (picked == null) return;
    setState(() {
      _photoPath = picked.path;
      _step = _ScanStep.scanning;
      _error = '';
    });
    await _scan(picked.path);
  }

  // ─── ML Kit OCR → Gemini text parse ─────────────────────────

  Future<void> _scan(String path) async {
    try {
      // Step 1: On-device ML Kit OCR (free, no API quota used)
      final inputImage = InputImage.fromFilePath(path);
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final recognized = await recognizer.processImage(inputImage);
      await recognizer.close();
      final ocrText = recognized.text.trim();

      // Step 2: Send extracted text to Gemini 2.0 Flash for date parsing
      final rawJson = ocrText.isEmpty
          ? '{"product_name":"","category":"other","dates_found":[],"expiry_date":"","confidence":"low","is_blurry":true}'
          : await LlmService().parseExpiryFromText(ocrText);

      final data = _parseJson(rawJson);

      final productName = data['product_name']?.toString() ?? '';
      final category = data['category']?.toString() ?? 'other';
      final expiryStr = data['expiry_date']?.toString() ?? '';
      final isBlurry = data['is_blurry'] as bool? ?? false;
      final rawDates = (data['dates_found'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [];

      DateTime? expiry;
      bool usedFallback = false;

      if (expiryStr.isNotEmpty) {
        expiry = DateTime.tryParse(expiryStr);
      }

      // Fallback: category-based estimate
      if ((expiry == null || isBlurry) && !isBlurry) {
        // Still no date but not blurry — use what we have
      }
      if (expiry == null || isBlurry) {
        final days = categoryFallbackDays[category] ?? 14;
        expiry = DateTime.now().add(Duration(days: days));
        usedFallback = true;
      }

      setState(() {
        _nameController.text = productName;
        _category = _categories.any((c) => c.$1 == category)
            ? category
            : 'other';
        _expiryDate = expiry;
        _wasBlurry = isBlurry;
        _usedFallback = usedFallback;
        _datesFound = rawDates;
        _step = _ScanStep.review;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _step = _ScanStep.idle;
      });
    }
  }

  // ─── Get storage advice ──────────────────────────────────────

  Future<void> _fetchAdvice() async {
    setState(() => _step = _ScanStep.gettingAdvice);
    try {
      final advice = await LlmService().getStorageAdviceOllama(
        _nameController.text.trim().isEmpty
            ? _category
            : _nameController.text.trim(),
        _category,
        _expiryDate != null
            ? '${_expiryDate!.day} ${_months[_expiryDate!.month - 1]} ${_expiryDate!.year}'
            : 'unknown',
      );
      setState(() {
        _storageAdvice = advice.trim();
        _step = _ScanStep.review;
      });
    } catch (e) {
      setState(() {
        _storageAdvice = '';
        _step = _ScanStep.review;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not fetch advice: $e'),
          backgroundColor: Colors.orange.shade700,
        ));
      }
    }
  }

  // ─── Save ────────────────────────────────────────────────────

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please enter a product name.')));
      return;
    }
    if (_expiryDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please set an expiry date.')));
      return;
    }
    final item = ExpiryItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      category: _category,
      expiryDate: _expiryDate!,
      photoPath: _photoPath,
      storageAdvice: _storageAdvice,
      addedAt: DateTime.now(),
    );
    Navigator.pop(context, item);
  }

  // ─── Helpers ─────────────────────────────────────────────────

  Map<String, dynamic> _parseJson(String raw) {
    String s = raw
        .trim()
        .replaceAll(RegExp(r'```json\s*'), '')
        .replaceAll(RegExp(r'```\s*'), '');
    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start == -1 || end <= start) return {};
    return jsonDecode(s.substring(start, end + 1)) as Map<String, dynamic>;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2035),
      helpText: 'Set Expiry Date',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
            colorScheme:
                const ColorScheme.light(primary: _themeColor)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _expiryDate = picked);
  }

  String _fmtDate(DateTime dt) =>
      '${dt.day} ${_months[dt.month - 1]} ${dt.year}';

  // ─── Build ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Expiry Date'),
        backgroundColor: _themeColor,
        foregroundColor: Colors.white,
      ),
      body: switch (_step) {
        _ScanStep.scanning => _buildScanning(),
        _ScanStep.gettingAdvice => _buildGettingAdvice(),
        _ScanStep.review => _buildReview(),
        _ => _buildIdle(),
      },
    );
  }

  // ─── Idle (pick image) ───────────────────────────────────────

  Widget _buildIdle() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.document_scanner_rounded,
                size: 64, color: _themeColor),
          ),
          const SizedBox(height: 24),
          const Text(
            'Photograph the food label',
            style:
                TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Point your camera at the expiry date on the packaging.\nGemini will read and extract the date automatically.',
            textAlign: TextAlign.center,
            style:
                TextStyle(color: Colors.grey.shade600, height: 1.6),
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded,
                      color: Colors.red.shade400, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_error,
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.red.shade700)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 36),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: () => _pickImage(ImageSource.camera),
              icon: const Icon(Icons.camera_alt_rounded),
              label: const Text('Take a Photo',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _themeColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: OutlinedButton.icon(
              onPressed: () => _pickImage(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_rounded),
              label: const Text('Choose from Gallery',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                foregroundColor: _themeColor,
                side: const BorderSide(color: _themeColor),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Scanning / Getting advice ────────────────────────────────

  Widget _buildScanning() => _buildLoading(
        Icons.document_scanner_rounded,
        'Reading Label…',
        'On-device OCR scanning text, then Gemini parsing dates',
      );

  Widget _buildGettingAdvice() => _buildLoading(
        Icons.lightbulb_rounded,
        'Getting Storage Tips…',
        'Gemini is generating storage advice',
      );

  Widget _buildLoading(IconData icon, String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
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
                      strokeWidth: 6),
                ),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _themeColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child:
                      Icon(icon, size: 34, color: _themeColor),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Text(title,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.grey.shade600, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  // ─── Review & Edit ────────────────────────────────────────────

  Widget _buildReview() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Photo preview
          if (_photoPath != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.file(
                File(_photoPath!),
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          const SizedBox(height: 16),

          // Blurry / fallback notices
          if (_wasBlurry || _usedFallback) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: Colors.orange.shade700, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _wasBlurry
                          ? 'The label was blurry or no date was found. A fallback date has been estimated based on the food category. Please review and adjust.'
                          : 'No date could be extracted. An estimated expiry date has been set based on the food category.',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade800,
                          height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Dates found
          if (_datesFound.isNotEmpty) ...[
            Text('Dates found on label:',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: _datesFound
                  .map((d) => Chip(
                        label: Text(d,
                            style: const TextStyle(fontSize: 12)),
                        backgroundColor: Colors.grey.shade100,
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
          ],

          // Product Name
          const Text('Product Name',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              hintText: 'e.g. Full Cream Milk',
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
            ),
          ),
          const SizedBox(height: 16),

          // Category
          const Text('Food Category',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _category,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    BorderSide(color: Colors.grey.shade300),
              ),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
            ),
            items: _categories
                .map((c) => DropdownMenuItem(
                    value: c.$1,
                    child: Text(c.$2)))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _category = v);
            },
          ),
          const SizedBox(height: 16),

          // Expiry Date
          const Text('Expiry Date',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_rounded,
                      color: _themeColor, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    _expiryDate != null
                        ? _fmtDate(_expiryDate!)
                        : 'Tap to set expiry date',
                    style: TextStyle(
                      fontSize: 15,
                      color: _expiryDate != null
                          ? Colors.black87
                          : Colors.grey.shade400,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.edit_rounded,
                      size: 16,
                      color: Colors.grey.shade400),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Storage Advice
          Row(
            children: [
              const Text('Storage Advice',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton.icon(
                onPressed: _fetchAdvice,
                icon: const Icon(
                    Icons.auto_awesome_rounded,
                    size: 14),
                label: const Text('Generate with Ollama'),
                style: TextButton.styleFrom(
                    foregroundColor: _themeColor),
              ),
            ],
          ),
          if (_storageAdvice.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_rounded,
                      color: Colors.amber.shade700, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _storageAdvice,
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                          height: 1.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 28),

          // Save button
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_rounded),
              label: const Text('Save to Tracker',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _themeColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () => setState(() {
                _step = _ScanStep.idle;
                _photoPath = null;
                _datesFound = [];
              }),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Scan Again'),
              style:
                  TextButton.styleFrom(foregroundColor: _themeColor),
            ),
          ),
        ],
      ),
    );
  }
}
