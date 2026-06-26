import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:androidtestllm_flutter/domain/models/medication.dart';
import 'package:androidtestllm_flutter/data/repositories/medication_storage.dart';

void main() {
  test('MedicationStorage saves and retrieves medications', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = MedicationStorage();
    
    final med = Medication(
      id: 1,
      name: 'Aspirin',
      dosage: '81mg',
      frequency: 'Daily',
      dateAdded: '2026-05-30',
    );

    await storage.saveMedications([med]);
    final retrieved = await storage.getMedications();
    
    expect(retrieved.length, 1);
    expect(retrieved.first.name, 'Aspirin');
  });
}