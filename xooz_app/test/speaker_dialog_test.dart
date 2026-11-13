import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xooz_app/models/transcript.dart';
import 'package:xooz_app/screens/transcript_screen.dart';

void main() {
  testWidgets('cached summary shows the saved name without its speaker label', (tester) async {
    final transcript = Transcript(
      id: 'cached-transcript',
      userId: 'test-user',
      text: 'We agreed.',
      speakerLabels: [
        {'speaker': 'A', 'text': 'We agreed.', 'start': 0, 'end': 1000},
      ],
      speakerNames: {'A': 'Priya'},
      recordedAt: DateTime(2026, 11, 10),
      summary: '- Speaker A [Priya] agreed.',
    );

    await tester.pumpWidget(MaterialApp(home: TranscriptScreen(transcript: transcript)));
    await tester.pump();

    expect(find.text('Priya agreed.'), findsOneWidget);
    expect(find.textContaining('Speaker A [Priya]'), findsNothing);
  });

  testWidgets('speaker name dialog opens on tap', (tester) async {
    final transcript = Transcript(
      id: 'test-transcript',
      userId: 'test-user',
      text: 'Hello there.',
      speakerLabels: [
        {'speaker': 'A', 'text': 'Hello there.', 'start': 0, 'end': 1000},
      ],
      recordedAt: DateTime(2026, 11, 10),
      summary: 'A greeting.',
    );

    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(home: TranscriptScreen(transcript: transcript)));
      await tester.tap(find.text('Transcript'));
      await tester.pump();
      await tester.tap(find.text('Speaker A'));
      await tester.pump();

      expect(find.text('Name Speaker A'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Saved speakers'), findsOneWidget);
      expect(find.text('Priya'), findsOneWidget);
      expect(find.text('Possible match'), findsOneWidget);
      expect(find.text('Possibly Rahul?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, () => MockClient((request) async {
      if (request.url.path.endsWith('/speakers')) {
        return http.Response('{"speakers":[{"name":"Priya"}]}', 200);
      }
      if (request.url.path.endsWith('/speaker-suggestion')) {
        return http.Response('{"suggestion":{"name":"Rahul","tier":"possible","score":0.72}}', 200);
      }
      return http.Response('not found', 404);
    }));
  });

  testWidgets('possible speaker can be confirmed with one tap', (tester) async {
    final transcript = Transcript(
      id: 'test-transcript', userId: 'test-user', text: 'Hello there.',
      speakerLabels: [
        {'speaker': 'A', 'text': 'Hello there.', 'start': 0, 'end': 5000},
      ],
      recordedAt: DateTime(2026, 11, 10), summary: 'A greeting.',
      audioUrl: 'https://example.com/audio.m4a',
    );
    var confirmed = false;
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(home: TranscriptScreen(transcript: transcript)));
      await tester.tap(find.text('Transcript'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Possibly Rahul?'), findsOneWidget);

      await tester.tap(find.text('Possibly Rahul?'));
      await tester.pump();
      expect(confirmed, isTrue);
      expect(find.text('Rahul'), findsOneWidget);
    }, () => MockClient((request) async {
      if (request.url.path.endsWith('/speaker-suggestion')) {
        return http.Response('{"suggestion":{"name":"Rahul","tier":"possible","score":0.72}}', 200);
      }
      if (request.method == 'PATCH') {
        confirmed = true;
      }
      if (request.url.path.endsWith('/summary')) {
        return http.Response('{"summary":"A greeting.","title":"Greeting"}', 200);
      }
      return http.Response(
        '{"transcript":{"id":"test-transcript","user_id":"test-user",'
        '"text":"Hello there.","recorded_at":"2026-11-10T10:00:00Z",'
        '"speaker_labels":[{"speaker":"A","text":"Hello there.","start":0,"end":5000}],'
        '"speaker_names":${confirmed ? '{"A":"Rahul"}' : '{}'},'
        '"summary":"A greeting.","audio_url":"https://example.com/audio.m4a"}}', 200,
      );
    }));
  });
}
