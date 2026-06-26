// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:androidtestllm_flutter/main.dart';
import 'package:androidtestllm_flutter/data/repositories/conversation_repository.dart';

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final sharedPreferences = await SharedPreferences.getInstance();

    // Build our app and trigger a frame.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sharedPreferences),
        ],
        child: const AndroidTestLlmApp(),
      ),
    );

    // Verify that the app launches and shows the Welcome text.
    expect(find.text('Welcome'), findsOneWidget);
  });
}
