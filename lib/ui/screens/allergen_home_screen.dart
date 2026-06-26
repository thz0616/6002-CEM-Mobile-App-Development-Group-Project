import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/selected_allergens.dart';
import 'allergen_scanner_screen.dart';
import 'allergen_ocr_screen.dart';

class AllergenHomeScreen extends StatefulWidget {
  const AllergenHomeScreen({super.key});

  @override
  State<AllergenHomeScreen> createState() => _AllergenHomeScreenState();
}

class _AllergenHomeScreenState extends State<AllergenHomeScreen> {
  static const String prefsName = 'AllergenPrefs';
  
  bool cbPeanuts = false;
  bool cbTreeNuts = false;
  bool cbDairy = false;
  bool cbEggs = false;
  bool cbSoy = false;
  bool cbWheat = false;
  bool cbGluten = false;
  bool cbFish = false;
  bool cbShellfish = false;
  bool cbSesame = false;
  
  final TextEditingController _otherController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  @override
  void dispose() {
    _savePreferences();
    _otherController.dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      cbPeanuts = prefs.getBool('peanuts') ?? false;
      cbTreeNuts = prefs.getBool('treenuts') ?? false;
      cbDairy = prefs.getBool('dairy') ?? false;
      cbEggs = prefs.getBool('eggs') ?? false;
      cbSoy = prefs.getBool('soy') ?? false;
      cbWheat = prefs.getBool('wheat') ?? false;
      cbGluten = prefs.getBool('gluten') ?? false;
      cbFish = prefs.getBool('fish') ?? false;
      cbShellfish = prefs.getBool('shellfish') ?? false;
      cbSesame = prefs.getBool('sesame') ?? false;
      _otherController.text = prefs.getString('other') ?? '';
    });
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('peanuts', cbPeanuts);
    await prefs.setBool('treenuts', cbTreeNuts);
    await prefs.setBool('dairy', cbDairy);
    await prefs.setBool('eggs', cbEggs);
    await prefs.setBool('soy', cbSoy);
    await prefs.setBool('wheat', cbWheat);
    await prefs.setBool('gluten', cbGluten);
    await prefs.setBool('fish', cbFish);
    await prefs.setBool('shellfish', cbShellfish);
    await prefs.setBool('sesame', cbSesame);
    await prefs.setString('other', _otherController.text);
  }

  SelectedAllergens _collectSelected() {
    Set<String> custom = _parseOtherAndApplyToCheckboxes();
    Set<String> picks = {};
    
    if (cbPeanuts) picks.add('Peanut');
    if (cbTreeNuts) picks.add('Tree nut');
    if (cbDairy) picks.add('Milk');
    if (cbEggs) picks.add('Egg');
    if (cbSoy) picks.add('Soy');
    if (cbWheat) picks.add('Wheat');
    if (cbGluten) picks.add('Gluten');
    if (cbFish) picks.add('Fish');
    if (cbShellfish) picks.add('Shellfish');
    if (cbSesame) picks.add('Sesame');
    
    picks.addAll(custom);
    return SelectedAllergens(picks.toList());
  }

  Set<String> _parseOtherAndApplyToCheckboxes() {
    Set<String> customs = {};
    String raw = _otherController.text;
    if (raw.isEmpty) return customs;

    String normalized = raw
        .replaceAll('\n', ',')
        .replaceAll(';', ',')
        .replaceAll('、', ',')
        .replaceAll('，', ',')
        .replaceAll('&', ',')
        .replaceAll('+', ',');
    
    normalized = normalized.replaceAll(RegExp(r'\band\b', caseSensitive: false), ',');
    
    for (String token in normalized.split(',')) {
      String t = token.trim();
      if (t.isEmpty) continue;
      
      String? mapped = _mapToStandardAllergen(t);
      if (mapped != null) {
        _checkBoxFor(mapped, true);
      } else {
        customs.add(t);
      }
    }
    return customs;
  }

  void _checkBoxFor(String std, bool checked) {
    switch (std) {
      case 'Peanut': cbPeanuts = checked; break;
      case 'Tree nut': cbTreeNuts = checked; break;
      case 'Milk': cbDairy = checked; break;
      case 'Egg': cbEggs = checked; break;
      case 'Soy': cbSoy = checked; break;
      case 'Wheat': cbWheat = checked; break;
      case 'Gluten': cbGluten = checked; break;
      case 'Fish': cbFish = checked; break;
      case 'Shellfish': cbShellfish = checked; break;
      case 'Sesame': cbSesame = checked; break;
    }
  }

  String? _mapToStandardAllergen(String input) {
    String s = input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').trim();
    if (s.isEmpty) return null;

    if (_containsAny(s, ["peanut", "peanuts", "groundnut", "ground nuts", "arachis", "arachide"])) return "Peanut";
    if (_containsAny(s, ["almond", "walnut", "cashew", "pecan", "hazelnut", "pistachio", "brazil nut", "macadamia", "pine nut", "tree nut", "tree nuts", "nuts"])) return "Tree nut";
    if (_containsAny(s, ["milk", "dairy", "lactose", "casein", "whey", "butterfat", "cheese"])) return "Milk";
    if (_containsAny(s, ["egg", "eggs", "eggwhite", "egg white", "egg whites", "albumen", "ovalbumin", "ovomucoid"])) return "Egg";
    if (_containsAny(s, ["soy", "soya", "soybean", "edamame", "tofu"])) return "Soy";
    if (_containsAny(s, ["wheat", "farina", "spelt", "durum"])) return "Wheat";
    if (_containsAny(s, ["gluten", "barley", "rye", "malt", "triticale"])) return "Gluten";
    if (_containsAny(s, ["fish", "anchovy", "salmon", "tuna", "cod", "haddock", "mackerel", "sardine"])) return "Fish";
    if (_containsAny(s, ["shellfish", "shell fish", "crustacean", "mollusk", "shrimp", "prawn", "crab", "lobster", "scallop", "clam", "oyster", "mussel"])) return "Shellfish";
    if (_containsAny(s, ["sesame", "tahini", "benne"])) return "Sesame";

    return null; // Fuzzy matching omitted for simplicity
  }

  bool _containsAny(String s, List<String> keys) {
    for (String k in keys) {
      if (s.contains(k)) return true;
    }
    return false;
  }

  Widget _buildCheckbox(String title, bool value, ValueChanged<bool?> onChanged) {
    return Theme(
      data: Theme.of(context).copyWith(
        unselectedWidgetColor: Colors.grey,
      ),
      child: CheckboxListTile(
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)),
        value: value,
        onChanged: onChanged,
        activeColor: const Color(0xFFFF6F00),
        checkColor: Colors.black,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Select your allergens'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFF6F00), width: 1),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    children: [
                      _buildCheckbox('Peanuts', cbPeanuts, (v) => setState(() => cbPeanuts = v ?? false)),
                      _buildCheckbox('Tree nuts', cbTreeNuts, (v) => setState(() => cbTreeNuts = v ?? false)),
                      _buildCheckbox('Dairy', cbDairy, (v) => setState(() => cbDairy = v ?? false)),
                      _buildCheckbox('Eggs', cbEggs, (v) => setState(() => cbEggs = v ?? false)),
                      _buildCheckbox('Soy', cbSoy, (v) => setState(() => cbSoy = v ?? false)),
                      _buildCheckbox('Wheat', cbWheat, (v) => setState(() => cbWheat = v ?? false)),
                      _buildCheckbox('Gluten', cbGluten, (v) => setState(() => cbGluten = v ?? false)),
                      _buildCheckbox('Fish', cbFish, (v) => setState(() => cbFish = v ?? false)),
                      _buildCheckbox('Shellfish', cbShellfish, (v) => setState(() => cbShellfish = v ?? false)),
                      _buildCheckbox('Sesame', cbSesame, (v) => setState(() => cbSesame = v ?? false)),
                      
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                        child: TextField(
                          controller: _otherController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Other (comma separated)',
                            labelStyle: const TextStyle(color: Colors.grey),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.grey.shade700),
                            ),
                            focusedBorder: const UnderlineInputBorder(
                              borderSide: BorderSide(color: Color(0xFFFF6F00)),
                            ),
                          ),
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await _savePreferences();
                        if (!context.mounted) return;
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => AllergenScannerScreen(selectedAllergens: _collectSelected())
                        ));
                      },
                      icon: const Icon(Icons.qr_code_scanner, color: Colors.black),
                      label: const Text('SCAN', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6F00),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 1,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await _savePreferences();
                        if (!context.mounted) return;
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => AllergenOcrScreen(selectedAllergens: _collectSelected())
                        ));
                      },
                      icon: const Icon(Icons.document_scanner, color: Color(0xFFFF6F00)),
                      label: const Text('OCR', style: TextStyle(color: Color(0xFFFF6F00), fontWeight: FontWeight.bold, fontSize: 16)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFFF6F00)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
