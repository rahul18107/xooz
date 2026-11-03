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
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    if (isToday) return 'Today';
    return '${date.day}/${date.month}/${date.year}';
  }

  String get shortSummary {
    if (summary.length <= 80) return summary;
    return '${summary.substring(0, 80)}...';
  }
}
