import 'package:flutter_test/flutter_test.dart';
import 'package:xooz_app/models/recap.dart';

void main() {
  test('parses source-linked structured recap sections', () {
    final recap = Recap.fromJson({
      'date': '2026-11-09',
      'digest': 'Train planning\n\nThe team discussed trains.',
      'structured_summary': {
        'action_items': [
          {'text': 'Book the train.', 'recording_id': 'one', 'task_id': 'task-one'},
        ],
        'decisions': [],
        'unresolved_questions': [],
      },
    });
    expect(recap.actionItems.single.recordingId, 'one');
    expect(recap.actionItems.single.text, 'Book the train.');
    expect(recap.actionItems.single.taskId, 'task-one');
  });

  test('unavailable recap never displays old transcript preview text', () {
    final recap = Recap.fromJson({
      'date': '2026-11-08',
      'recap_status': 'preview',
      'digest': 'Recorded conversations\n\nRaw transcript excerpt from a recording.',
      'stats': {'recordings': 1, 'minutes': 1, 'tasks': 0},
    });

    expect(recap.isUnavailable, isTrue);
    expect(recap.title, 'Daily recap');
    expect(recap.quickSummary, isEmpty);
    expect(recap.detailedSummary, isEmpty);
  });

  test('uses recap content when an old digest has a generic title', () {
    final parts = Recap.parseDigest('''Recorded conversations

Priya Sharma confirmed the Mumbai trip and agreed to book the train.''');

    expect(parts.$1, 'Priya Sharma confirmed the Mumbai trip and');
    expect(parts.$2, 'Priya Sharma confirmed the Mumbai trip and agreed to book the train.');
  });

  test('cleans a cached generic title and punctuates recap lines', () {
    final parts = Recap.parseDigest('''Today's recap was centered around a microphone check
Rahul tested the phone microphone
He checked the English language output
He agreed to try another recording''');

    expect(parts.$1, 'A microphone check');
    expect(parts.$2,
        'Rahul tested the phone microphone. He checked the English language output.');
    expect(parts.$3, 'He agreed to try another recording.');
  });

  test('preserves the complete title and separates longer details', () {
    final parts = Recap.parseDigest('''Microphone and language settings review

Rahul tested the microphone. He checked the language output.

The phone captured English speech. A second test was planned. The team will review it.''');

    expect(parts.$1, 'Microphone and language settings review');
    expect(parts.$2,
        'Rahul tested the microphone. He checked the language output.');
    expect(parts.$3,
        'The phone captured English speech. A second test was planned.\n\nThe team will review it.');
  });

  test('removes section labels and digest filler from generated recaps', () {
    final parts = Recap.parseDigest('''Today's conversations centered around the smartwatch's battery life and optimization.

1. Smartwatch battery life.

2. Optimizing battery usage.

Important Decisions/Action Items:: 1.

Consider enabling the "watch only" mode to extend battery life. People Talked To: None identified.

This digest provides a quick summary of today's conversations, highlighting the main topics discussed and any important decisions or action items mentioned.''');

    expect(parts.$1, 'The smartwatch\'s battery life and optimization');
    expect(parts.$2,
        'Smartwatch battery life. Optimizing battery usage.');
    expect(parts.$3,
        'Consider enabling the "watch only" mode to extend battery life.');
  });
}
