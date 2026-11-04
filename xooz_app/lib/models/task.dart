class Task {
  final String id;
  final String userId;
  final String title;
  final String status; // open | done | snoozed
  final String? dueDate;
  final String? sourceTranscriptId;
  final DateTime createdAt;

  Task({
    required this.id,
    required this.userId,
    required this.title,
    required this.status,
    required this.createdAt,
    this.dueDate,
    this.sourceTranscriptId,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'],
      userId: json['user_id'],
      title: json['title'],
      status: json['status'] ?? 'open',
      dueDate: json['due_date'],
      sourceTranscriptId: json['source_transcript_id'],
      createdAt: DateTime.parse(json['created_at']).toLocal(),
    );
  }

  bool get isDone => status == 'done';
  String get statusLabel {
    switch (status) {
      case 'done':
        return 'Done';
      case 'snoozed':
        return 'Snoozed';
      default:
        return 'Open';
    }
  }

  Task copyWith({String? status, String? dueDate}) {
    return Task(
      id: id,
      userId: userId,
      title: title,
      status: status ?? this.status,
      createdAt: createdAt,
      dueDate: dueDate ?? this.dueDate,
      sourceTranscriptId: sourceTranscriptId,
    );
  }
}
