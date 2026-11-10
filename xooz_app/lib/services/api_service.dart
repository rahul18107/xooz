import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/api.dart';
import '../models/transcript.dart';
import '../models/digest.dart';
import '../models/recap.dart';
import '../models/task.dart';
import '../models/chat.dart';

/// Thrown on any failed API call — includes the status code and server detail.
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() => statusCode != null
      ? 'ApiException($statusCode): $message'
      : 'ApiException: $message';
}

class TranscriptSummary {
  final String title;
  final String summary;

  const TranscriptSummary({required this.title, required this.summary});
}

class ApiService {
  // ---------------- internal helpers ----------------

  static Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw ApiException(
      'Request failed (${response.statusCode}): ${response.body}',
      statusCode: response.statusCode,
    );
  }

  static Future<Map<String, dynamic>> _request(
    Future<http.Response> Function() call,
  ) async {
    try {
      return _decode(await call());
    } on ApiException {
      rethrow; // real server response — surface it as-is
    } catch (e) {
      // network error (server offline, timeout, connection refused…)
      throw ApiException('API error: $e');
    }
  }

  static Future<Map<String, dynamic>> _get(String url) =>
      _request(() => http.get(Uri.parse(url)));

  static Future<Map<String, dynamic>> _post(
    String url,
    Map<String, dynamic> body,
  ) => _request(
    () => http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    ),
  );

  static Future<Map<String, dynamic>> _patch(
    String url,
    Map<String, dynamic> body,
  ) => _request(
    () => http.patch(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    ),
  );

  // ---------------- audio ----------------

  static Future<Transcript?> uploadAudio(
    File audioFile, {
    Duration? duration,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(ApiConfig.uploadAudio),
      );

      request.fields['user_id'] = ApiConfig.testUserId;
      if (duration != null) {
        request.fields['duration_seconds'] = (duration.inMilliseconds / 1000)
            .toStringAsFixed(3);
      }
      request.files.add(
        await http.MultipartFile.fromPath('file', audioFile.path),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200) {
        throw ApiException(
          'Upload failed (${response.statusCode}): ${response.body}',
          statusCode: response.statusCode,
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final t = (json['transcript'] ?? json) as Map<String, dynamic>;
      return Transcript.fromJson({
        ...t,
        'user_id': t['user_id'] ?? ApiConfig.testUserId,
        'recorded_at': t['recorded_at'] ?? DateTime.now().toIso8601String(),
      });
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('API error: $e');
    }
  }

  // ---------------- digests (recaps) ----------------

  static Future<Digest?> getDigest({String? date}) async {
    String url = ApiConfig.getDigest(ApiConfig.testUserId);
    if (date != null) url += '?date=$date';

    final json = await _get(url);
    return Digest.fromJson({
      ...json,
      'date': json['date'] ?? date ?? DateTime.now().toIso8601String(),
    });
  }

  static Future<Recap> getRecap({String? date, bool force = false}) async {
    String url = ApiConfig.getRecap(ApiConfig.testUserId);
    if (date != null || force) {
      url +=
          '?${[if (date != null) 'date=$date', if (force) 'force=true'].join('&')}';
    }

    final json = await _get(url);
    return Recap.fromJson(json);
  }

  static Future<List<Digest>> getDigests({String? month}) async {
    String url = ApiConfig.getDigests(ApiConfig.testUserId);
    if (month != null) url += '?month=$month';

    final json = await _get(url);
    final d_digests = json['digests'] as List? ?? [];
    return d_digests
        .map(
          (d) => Digest.fromJson({
            ...d as Map<String, dynamic>,
            'digest': d['summary'],
          }),
        )
        .toList();
  }

  static Future<Digest> generateDigest(String date) async {
    final json = await _post(
      '${ApiConfig.getDigest(ApiConfig.testUserId)}?date=$date',
      {},
    );
    final summary = (json['digest'] as String? ?? '').trim();
    if (summary.isEmpty || summary.startsWith('Daily summary unavailable.')) {
      throw ApiException('Daily summary unavailable. Please try again.');
    }
    return Digest.fromJson(json);
  }

  static Future<void> deleteDigest(String date) async {
    await _request(
      () => http.delete(
        Uri.parse('${ApiConfig.getDigests(ApiConfig.testUserId)}?date=$date'),
      ),
    );
  }

  // ---------------- transcripts ----------------

  /// Newest first. Pass [date] as 'yyyy-MM-dd' to filter to one day.
  static Future<List<Transcript>> getTranscripts({
    String? date,
    int? limit,
  }) async {
    String url = '${ApiConfig.transcripts}?user_id=${ApiConfig.testUserId}';
    if (date != null) url += '&date=$date';
    if (limit != null) url += '&limit=$limit';

    final json = await _get(url);
    final transcripts = json['transcripts'] as List? ?? [];
    return transcripts
        .map((t) => Transcript.fromJson(t as Map<String, dynamic>))
        .toList();
  }

  static Future<Transcript> getTranscript(String id) async {
    final json = await _get(ApiConfig.transcriptDetail(id));
    return Transcript.fromJson(json['transcript'] as Map<String, dynamic>);
  }

  /// Generate (or fetch cached) AI summary for one recording.
  static Future<TranscriptSummary> generateSummary(
    String id, {
    bool force = false,
  }) async {
    String url = '${ApiConfig.transcriptDetail(id)}/summary';
    if (force) url += '?force=true';

    final json = await _post(url, {});
    return TranscriptSummary(
      title: json['title'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
    );
  }

  static Future<Transcript> renameTranscript(String id, String title) async {
    final json = await _patch(ApiConfig.transcriptDetail(id), {'title': title});
    return Transcript.fromJson(json['transcript'] as Map<String, dynamic>);
  }

  static Future<Transcript> setStarred(String id, bool starred) async {
    final json = await _patch(ApiConfig.transcriptDetail(id), {
      'starred': starred,
    });
    return Transcript.fromJson(json['transcript'] as Map<String, dynamic>);
  }

  static Future<Transcript> setSpeakerName(
    String id,
    Map<String, String> names,
  ) async {
    final json = await _patch(ApiConfig.transcriptDetail(id), {
      'speaker_names': names,
    });
    return Transcript.fromJson(json['transcript'] as Map<String, dynamic>);
  }

  static Future<void> deleteTranscript(String id) async {
    await _request(
      () => http.delete(Uri.parse(ApiConfig.transcriptDetail(id))),
    );
  }

  // ---------------- tasks ----------------

  static Future<List<Task>> getTasks({String? date}) async {
    String url = '${ApiConfig.tasks}?user_id=${ApiConfig.testUserId}';
    if (date != null) url += '&date=$date';

    final json = await _get(url);
    final tasks = json['tasks'] as List? ?? [];
    return tasks.map((t) => Task.fromJson(t as Map<String, dynamic>)).toList();
  }

  static Future<Task> updateTaskStatus(String id, String status) async {
    final json = await _patch(ApiConfig.taskDetail(id), {'status': status});
    return Task.fromJson(json['task'] as Map<String, dynamic>);
  }

  static Future<void> deleteTask(String id) async {
    await _request(
      () => http.delete(
        Uri.parse(
          '${ApiConfig.taskDetail(id)}?user_id=${Uri.encodeQueryComponent(ApiConfig.testUserId)}',
        ),
      ),
    );
  }

  static Future<String> getTaskPlan(String id) async {
    final json = await _get('${ApiConfig.taskDetail(id)}/plan');
    return (json['plan'] as String?) ?? '';
  }

  static Future<Map<String, String>> getTaskBriefs(String transcriptId) async {
    final json = await _get(
      '${ApiConfig.tasks}/briefs'
      '?user_id=${ApiConfig.testUserId}&transcript_id=$transcriptId',
    );
    final briefs = json['briefs'] as Map<String, dynamic>? ?? {};
    return {for (final e in briefs.entries) e.key: (e.value as String?) ?? ''};
  }

  // ---------------- chat ----------------

  /// Legacy session used by recordings made before multi-thread chat.
  static String get chatSessionId => '${ApiConfig.testUserId}-main';

  static Future<List<ChatThread>> getChatThreads() async {
    final json = await _get(
      '${ApiConfig.chat}/threads?user_id=${Uri.encodeQueryComponent(ApiConfig.testUserId)}',
    );
    return (json['threads'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(ChatThread.fromJson)
        .toList();
  }

  static Future<ChatThread> createChatThread() async {
    final json = await _post('${ApiConfig.chat}/threads', {
      'user_id': ApiConfig.testUserId,
    });
    return ChatThread.fromJson(json['thread'] as Map<String, dynamic>);
  }

  static Future<void> deleteChatThread(String sessionId) async {
    await _request(
      () => http.delete(
        Uri.parse(
          '${ApiConfig.chat}/threads/${Uri.encodeComponent(sessionId)}'
          '?user_id=${Uri.encodeQueryComponent(ApiConfig.testUserId)}',
        ),
      ),
    );
  }

  static Future<List<({String text, bool isUser, List<String> sourceIds})>>
  loadChatHistory({int limit = 100, String? sessionId}) async {
    final json = await _get(
      '${ApiConfig.chat}/history'
      '?user_id=${Uri.encodeQueryComponent(ApiConfig.testUserId)}'
      '&session_id=${Uri.encodeQueryComponent(sessionId ?? chatSessionId)}&limit=$limit',
    );
    final messages = json['messages'] as List? ?? [];
    return [
      for (final m in messages)
        if (((m['content'] as String?) ?? '').trim().isNotEmpty)
          (
            text: (m['content'] as String?) ?? '',
            isUser: (m['role'] ?? 'user') == 'user',
            sourceIds: (m['source_ids'] as List? ?? const [])
                .whereType<String>()
                .toList(),
          ),
    ];
  }

  static Future<ChatReply> sendChat(
    String message, {
    String? sessionId,
    String? requestId,
  }) async {
    final body = <String, dynamic>{
      'user_id': ApiConfig.testUserId,
      'message': message,
    };
    if (sessionId != null) {
      body['session_id'] = sessionId;
    }
    if (requestId != null) body['client_request_id'] = requestId;

    final json = await _post(ApiConfig.chat, body);
    return ChatReply(
      sessionId: json['session_id'] as String? ?? '',
      reply: json['reply'] as String? ?? '',
      sourceIds: (json['sources'] as List<dynamic>? ?? [])
          .map((source) => (source as Map<String, dynamic>)['id'] as String)
          .toList(),
    );
  }

  // ---------------- search ----------------

  /// Never throws — returns empty map when the server is offline/not migrated,
  /// so the category grid can safely show zeros.
  static Future<Map<String, int>> getCategoryCounts() async {
    try {
      final json = await _get(
        '${ApiConfig.categoryCounts}?user_id=${ApiConfig.testUserId}',
      );
      final categories = json['categories'] as Map<String, dynamic>? ?? {};
      return categories.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0));
    } catch (_) {
      return {};
    }
  }

  static Future<SearchResults> search(String query) async {
    final url =
        '${ApiConfig.search}?user_id=${ApiConfig.testUserId}'
        '&q=${Uri.encodeQueryComponent(query)}';
    final json = await _get(url);

    final transcripts = json['transcripts'] as List? ?? [];
    final digests = json['digests'] as List? ?? [];
    final tasks = json['tasks'] as List? ?? [];

    return SearchResults(
      transcripts: transcripts
          .map((t) => Transcript.fromJson(t as Map<String, dynamic>))
          .toList(),
      digests: digests
          .map(
            (d) => Digest.fromJson({
              ...d as Map<String, dynamic>,
              'digest': d['summary'],
            }),
          )
          .toList(),
      tasks: tasks
          .map((t) => Task.fromJson(t as Map<String, dynamic>))
          .toList(),
    );
  }

  // ---------------- activity ----------------

  static Future<ActivityFeed> getActivity() async {
    final json = await _get(ApiConfig.activity(ApiConfig.testUserId));
    final needsAttention = json['needs_attention'] as List? ?? [];
    final today = json['today'] as List? ?? [];

    return ActivityFeed(
      needsAttention: needsAttention
          .map((t) => Transcript.fromJson(t as Map<String, dynamic>))
          .toList(),
      today: today
          .map((t) => Transcript.fromJson(t as Map<String, dynamic>))
          .toList(),
    );
  }

  // ---------------- profile & usage ----------------

  static Future<ProfileInfo?> getProfile() async {
    final json = await _get('${ApiConfig.me}?user_id=${ApiConfig.testUserId}');
    return ProfileInfo.fromJson(json['profile'] as Map<String, dynamic>);
  }

  static Future<ProfileInfo> updateTranscriptionVocabulary(
    List<String> terms,
  ) async {
    final json = await _patch(ApiConfig.me, {
      'user_id': ApiConfig.testUserId,
      'transcription_vocabulary': terms,
    });
    return ProfileInfo.fromJson(json['profile'] as Map<String, dynamic>);
  }

  static Future<ProfileInfo> updateDailyRecapSchedule({
    required bool enabled,
    required int hour,
    required String timezone,
  }) async {
    final json = await _patch(ApiConfig.me, {
      'user_id': ApiConfig.testUserId,
      'daily_recap_enabled': enabled,
      'daily_recap_hour': hour,
      'timezone': timezone,
    });
    return ProfileInfo.fromJson(json['profile'] as Map<String, dynamic>);
  }

  static Future<UsageInfo?> getUsage() async {
    final json = await _get(
      '${ApiConfig.usage}?user_id=${ApiConfig.testUserId}',
    );
    return UsageInfo.fromJson(json);
  }
}
