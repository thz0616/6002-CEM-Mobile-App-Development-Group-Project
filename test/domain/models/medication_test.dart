import 'package:flutter_test/flutter_test.dart';
import 'package:androidtestllm_flutter/domain/models/medication.dart';

void main() {
  test('Medication should serialize to and from JSON', () {
    final json = {
      'id': 1,
      'name': 'Aspirin',
      'dosage': '81mg',
      'frequency': 'Once daily',
      'date_added': '2026-05-30',
    };

    final medication = Medication.fromJson(json);
    expect(medication.name, 'Aspirin');
    
    final toJson = medication.toJson();
    expect(toJson['frequency'], 'Once daily');
  });
}