import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xooz_app/screens/recap_screen.dart';

void main() {
  testWidgets('recap action items are collapsed until opened', (tester) async {
    const response = '''{
      "date":"2026-11-10",
      "digest":"Project report and phone test\\n\\nThe team reviewed the project report. The phone test was planned.",
      "recap_status":"ready",
      "stats":{"recordings":2,"minutes":4,"tasks":2},
      "recordings":[],
      "source_recordings":[],
      "structured_summary":{"action_items":[
        {"text":"Finish project report","recording_id":"one","task_id":"task-one"},
        {"text":"Test the phone app","recording_id":"two","task_id":"task-two"}
      ]}
    }''';

    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: RecapScreen(date: '2026-11-10')));
      await tester.pumpAndSettle();

      expect(find.text('Action items (2)'), findsOneWidget);
      expect(find.text('Finish project report'), findsNothing);
      await tester.tap(find.text('Action items (2)'));
      await tester.pump();
      expect(find.text('Finish project report'), findsOneWidget);
      expect(find.text('Test the phone app'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, () => MockClient((_) async => http.Response(response, 200)));
  });
}
