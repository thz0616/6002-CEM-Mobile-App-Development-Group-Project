import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:androidtestllm_flutter/ui/screens/medication_validation_screen.dart';

void main() {
  testWidgets('Validation Screen shows text fields for Name, Dosage, Frequency and styled Button', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MedicationValidationScreen(
        initialName: 'Aspirin',
        initialDosage: '81mg',
        initialFrequency: 'Daily',
      ),
    ));

    expect(find.text('Verify Medication'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(3));
    expect(find.byType(ElevatedButton), findsOneWidget);
    expect(find.text('Aspirin'), findsOneWidget);
  });
}