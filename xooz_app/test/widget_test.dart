import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:xooz_app/main.dart';

void main() {
  testWidgets('App builds and shows HomeScreen smoke test',
      (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const XoozApp());

    // Let any pending async work (network fallback in HomeScreen) settle.
    await tester.pump();

    // Verify the app renders a MaterialApp and the home screen content.
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('Daily Recaps'), findsOneWidget);
  });
}
