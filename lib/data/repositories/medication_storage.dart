import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/medication.dart';

class MedicationStorage {
  static const String _key = 'medications_cabinet';

  Future<void> saveMedications(List<Medication> medications) async {
    final prefs = await SharedPreferences.getInstance();
    final String encodedData = jsonEncode(
      medications.map((m) => m.toJson()).toList(),
    );
    await prefs.setString(_key, encodedData);
  }

  Future<List<Medication>> getMedications() async {
    final prefs = await SharedPreferences.getInstance();
    final String? encodedData = prefs.getString(_key);
    
    if (encodedData == null || encodedData.isEmpty) {
      return [];
    }

    final List<dynamic> decoded = jsonDecode(encodedData);
    return decoded.map((item) => Medication.fromJson(item)).toList();
  }
}