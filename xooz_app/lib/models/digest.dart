import 'recap.dart';

class Digest {
  final String id;
  final String userId;
  final String summary;
  final DateTime date;
  final bool cached;

  Digest({
    required this.id,
    required this.userId,
    required this.summary,
    required this.date,
    required this.cached,
  });

  factory Digest.fromJson(Map<String, dynamic> json) {
    return Digest(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? '',
      summary: json['digest'] ?? json['summary'] ?? '',
      date: DateTime.parse(json['date'] ?? DateTime.now().toIso8601String()),
      cached: json['cached'] ?? false,
    );
  }

  String get dateLabel {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    if (isToday) return 'Today';
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
  }

  String get shortSummary {
    return Recap.parseDigest(summary).$1;
  }
}
