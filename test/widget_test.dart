// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also read widget tree state, read text, and verify that the
// values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shear_plate/main.dart';

void main() {
  testWidgets('App shows search field and settings control', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });
}
