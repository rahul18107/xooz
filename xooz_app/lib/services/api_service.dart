import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/api.dart';
import '../models/transcript.dart';
import '../models/digest.dart';
import '../models/task.dart';
import '../models/chat.dart';

/// Thrown on any failed API call — includes the status code and server detail.
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() =>
      statusCode != null ? 'ApiException($statusCode): $message' : 'ApiException: $message';
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

  static Future<Map<String, dynamic>> _post(String url, Map<String, dynamic> body) => _request(
        () => http.post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        ),
      );

  static Future<Map<String, dynamic>> _patch(String url, Map<String, dynamic> body) => _request(
        () => http.patch(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        ),
      );

  // ---------------- audio ----------------

  static Future<Transcript?> uploadAudio(File audioFile) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(ApiConfig.uploadAudio),
      );

      request.fields['user_id'] = ApiConfig.testUserId;
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

  static Future<List<Digest>> getDigests({String? month}) async {
    String url = ApiConfig.getDigests(ApiConfig.testUserId);
    if (month != null) url += '?month=$month';

    final json = await _get(url);
    final digests = json['digests'] as List? ?? [];
    return digests
        .map((d) => Digest.fromJson({...d as Map<String, dynamic>, 'digest': d['summary']}))
        .toList();
  }

  // ---------------- transcripts ----------------

  /// Newest first. Pass [date] as 'yyyy-MM-dd' to filter to one day.
  static Future<List<Transcript>> getTranscripts({String? date}) async {
    String url = '${ApiConfig.transcripts}?user_id=${ApiConfig.testUserId}';
    if (date != null) url += '&date=$date';

    final json = await _get(url);
    final transcripts = json['transcripts'] as List? ?? [];
    return transcripts.map((t) => Transcript.fromJson(t as Map<String, dynamic>)).toList();
  }

  static Future<Transcript> getTranscript(String id) async {
    final json = await _get(ApiConfig.transcriptDetail(id));
    return Transcript.fromJson(json['transcript'] as Map<String, dynamic>);
  }

  // ---------------- tasks ----------------

  static Future<List<Task>> getTasks() async {
    final json = await _get(
      '${ApiConfig.tasks}?user_id=${ApiConfig.testUserId}',
    );
    final tasks = json['tasks'] as List? ?? [];
    return tasks.map((t) => Task.fromJson(t as Map<String, dynamic>)).toList();
  }

  static Future<Task> updateTaskStatus(String id, String status) async {
    final json = await _patch(
      ApiConfig.taskDetail(id),
      {'status': status},
    );
    return Task.fromJson(json['task'] as Map<String, dynamic>);
  }

  // ---------------- chat ----------------

  static Future<ChatReply> sendChat(String message, {String? sessionId}) async {
    final body = <String, dynamic>{
      'user_id': ApiConfig.testUserId,
      'message': message,
    };
    if (sessionId != null) {
      body['session_id'] = sessionId;
    }

    final json = await _post(ApiConfig.chat, body);
    return ChatReply(
      sessionId: json['session_id'] as String? ?? '',
      reply: json['reply'] as String? ?? '',
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
    final url = '${ApiConfig.search}?user_id=${ApiConfig.testUserId}'
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
          .map((d) => Digest.fromJson({
                ...d as Map<String, dynamic>,
                'digest': d['summary'],
              }))
          .toList(),
      tasks: tasks.map((t) => Task.fromJson(t as Map<String, dynamic>)).toList(),
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

  static Future<UsageInfo?> getUsage() async {
    final json = await _get('${ApiConfig.usage}?user_id=${ApiConfig.testUserId}');
    return UsageInfo.fromJson(json);
  }
}
