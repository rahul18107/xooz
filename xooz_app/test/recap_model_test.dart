import 'package:flutter_test/flutter_test.dart';
import 'package:xooz_app/models/recap.dart';

void main() {
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
