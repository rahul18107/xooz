/// One day's recap: parsed digest text + stats + the day's recordings.
class Recap {
  final String date; // 'YYYY-MM-DD'
  final String title;
  final String quickSummary;
  final String detailedSummary;
  final int recordingCount;
  final double minutes;
  final int taskCount;
  final List<RecapEntry> recordings;

  Recap({
    required this.date,
    required this.title,
    required this.quickSummary,
    required this.detailedSummary,
    required this.recordingCount,
    required this.minutes,
    required this.taskCount,
    required this.recordings,
  });

  factory Recap.fromJson(Map<String, dynamic> json) {
    final date = (json['date'] ?? '').toString();
    final stats = (json['stats'] as Map<String, dynamic>? ?? {});
    final rawRecordings = (json['recordings'] as List? ?? []);
    final recordings = rawRecordings
        .whereType<Map<String, dynamic>>()
        .map((t) => RecapEntry.fromJson(t))
        .toList();
    final summary = ((json['digest'] ?? '') as String).trim();
    final parts = parseDigest(summary);

    return Recap(
      date: date,
      title: parts.$1,
      quickSummary: parts.$2,
      detailedSummary: parts.$3,
      recordingCount: (stats['recordings'] as num?)?.toInt() ?? 0,
      minutes: (stats['minutes'] as num?)?.toDouble() ?? 0.0,
      taskCount: (stats['tasks'] as num?)?.toInt() ?? 0,
      recordings: recordings,
    );
  }

  static String _cleanLine(String s) {
    var t = s.replaceAll('**', '').replaceAll('__', '').replaceAll('`', '');
    t = t.replaceFirst(RegExp(r'^\s*[-*]+\s*'), '');
    t = t.replaceFirst(RegExp(r'^\s*#+\s*'), '');
    return t.trim();
  }

  static bool _isSkipLine(String l) {
    final line = l.trim();
    return RegExp(r'^daily\s*digest', caseSensitive: false).hasMatch(line) ||
        RegExp(r'^(this\s+)?digest\s+(provides|summarizes|highlights|is)\b',
                caseSensitive: false)
            .hasMatch(line) ||
        RegExp(r'^this\s+summary\s+(provides|summarizes|highlights)\b',
                caseSensitive: false)
            .hasMatch(line) ||
        RegExp(r'^(people\s+talked\s+to|people)\s*:\s*(none|none identified)\.?$',
                caseSensitive: false)
            .hasMatch(line);
  }

  static String _stripLabel(String line) {
    return line
        .replaceFirst(
          RegExp(
            r'^(key topics|details|decisions|action items|important decisions/action items|people talked to|people)\s*:+\s*',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
  }

  static String _stripListMarker(String line) {
    return line.replaceFirst(RegExp(r'^\s*(?:\d+[\.)]|[-*])\s*'), '').trim();
  }

  static String _sentence(String value) {
    final line = value.trim();
    if (line.isEmpty) return '';
    return RegExp(r'[.!?]$').hasMatch(line) ? line : '$line.';
  }

  static String _shortTitle(String value) {
    var title = value.trim();
    title = title.replaceFirst(
      RegExp(
        r"^today.?s\s+(?:recap|conversations?)\s+(?:was\s+)?(?:centered\s+)?(?:around|on|about)\s*",
        caseSensitive: false,
      ),
      '',
    );
    title = title.replaceFirst(
      RegExp(
        r'^the\s+day\s+(?:was\s+)?(?:centered\s+)?(?:around|on|about)\s*',
        caseSensitive: false,
      ),
      '',
    );
    title = title.replaceAll(RegExp(r'\.$'), '').trim();
    if (title.isEmpty) return 'Daily recap';

    final words = title.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length > 7) title = words.take(7).join(' ');
    return '${title[0].toUpperCase()}${title.substring(1)}';
  }

  static String _titleFromListItems(List<String> lines) {
    final items = lines
        .map(_stripLabel)
        .map(_stripListMarker)
        .where((line) => line.isNotEmpty && !_isSkipLine(line))
        .take(2)
        .toList();
    if (items.isEmpty) return '';
    final title = items.join(' and ').replaceAll(RegExp(r'\.$'), '').trim();
    return _shortTitle(title);
  }

  static (String, String, String) parseDigest(String summary) {
    if (summary.isEmpty) return ('No conversations', '', 'No recap for this day yet.');

    final lines = summary
        .split('\n')
        .map(_cleanLine)
        .where((line) => line.isNotEmpty && !_isSkipLine(line))
        .toList();
    if (lines.isEmpty) return ('No conversations', '', 'No recap for this day yet.');

    var titleIndex = 0;
    if (RegExp(r'^(overview|quick summary|summary|title)\s*:$', caseSensitive: false)
        .hasMatch(lines.first) && lines.length > 1) {
      titleIndex = 1;
    }

    var title = lines[titleIndex].replaceFirst(
      RegExp(r'^(overview|quick summary|summary|title)\s*:\s*', caseSensitive: false),
      '',
    );
    final afterTitle = lines.skip(titleIndex + 1).toList();
    final listTitle = _titleFromListItems(
      afterTitle.where((line) => RegExp(r'^\s*\d+[\.)]\s+').hasMatch(line)).toList(),
    );
    final parsedTitle = _shortTitle(title);
    title = parsedTitle == 'Daily recap' && listTitle.isNotEmpty ? listTitle : parsedTitle;

    final sentences = <String>[];
    for (final line in afterTitle) {
      if (_isSkipLine(line)) continue;
      var body = _stripLabel(line);
      body = _stripListMarker(body);
      body = body.replaceFirst(
        RegExp(r'\s*people\s+talked\s+to\s*:\s*none identified\.?$',
            caseSensitive: false),
        '',
      );
      body = body.replaceFirst(RegExp(r'^\d+\s*$'), '').trim();
      if (body.isEmpty || _isSkipLine(body)) continue;
      for (final part in body.split(RegExp(r'(?<=[.!?])\s+'))) {
        final sentence = part.trim();
        if (sentence.isEmpty || _isSkipLine(sentence)) continue;
        sentences.add(_sentence(sentence));
      }
    }

    final quick = sentences.take(2).join(' ');
    final details = <String>[];
    for (var i = 2; i < sentences.length; i += 2) {
      details.add(sentences.skip(i).take(2).join(' '));
    }
    return (title, quick, details.join('\n\n'));
  }

  String get dateLabel {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    if (date.length >= 10) {
      final y = date.substring(0, 4);
      final m = (int.tryParse(date.substring(5, 7)) ?? 1) - 1;
      final d = int.tryParse(date.substring(8, 10)) ?? 1;
      return '${months[m.clamp(0, 11)]} $d, $y';
    }
    return date;
  }

  String get minutesLabel {
    if (minutes <= 0) return '0m';
    if (minutes < 1) return '${(minutes * 60).round()}s';
    return '${minutes.round()}m';
  }
}

class RecapEntry {
  final String id;
  final String text;
  final String? title;
  final String? summary;
  final DateTime recordedAt;
  final Map<String, dynamic> raw;

  RecapEntry({
    required this.id,
    required this.text,
    required this.recordedAt,
    required this.raw,
    this.title,
    this.summary,
  });

  factory RecapEntry.fromJson(Map<String, dynamic> json) {
    return RecapEntry(
      id: (json['id'] ?? '').toString(),
      text: (json['text'] ?? '').toString(),
      title: (json['title'] as String?)?.trim(),
      summary: (json['summary'] as String?)?.trim(),
      recordedAt: DateTime.parse(
        json['recorded_at'] ?? DateTime.now().toIso8601String(),
      ).toLocal(),
      raw: json,
    );
  }

  String get highlightTitle {
    if ((title ?? '').isNotEmpty) return title!;
    return _oneLiner(text);
  }

  String get highlightLine {
    if ((summary ?? '').isNotEmpty) {
      final lines = summary!
          .split('\n')
          .map((l) {
            var t = l.replaceAll('**', '').replaceAll('`', '');
            t = t.replaceFirst(RegExp(r'^\s*[-*]+\s*'), '').trim();
            return t;
          })
          .where((t) => t.isNotEmpty)
          .toList();
      if (lines.isNotEmpty) return _cap(lines.first, 110);
      return _oneLiner(text);
    }
    return _oneLiner(text);
  }

  static String _cap(String s, int max) {
    if (s.length <= max) return s;
    final cut = s.substring(0, max);
    final lastSpace = cut.lastIndexOf(' ');
    return '${cut.substring(0, lastSpace > 50 ? lastSpace : max)}...';
  }

  String _oneLiner(String text) {
    final t = text.trim();
    if (t.isEmpty) return 'Recording';
    final sentenceMatch = RegExp(r'^(.+?[.!?])').firstMatch(t);
    var h = sentenceMatch?.group(1) ?? t;
    if (h.length <= 90) return h;
    final cut = t.substring(0, 90);
    final lastSpace = cut.lastIndexOf(' ');
    return '${cut.substring(0, lastSpace > 40 ? lastSpace : 90)}...';
  }

  String get timeLabel {
    final h = recordedAt.hour;
    final m = recordedAt.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final hour = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '$hour:$m $period';
  }
}
