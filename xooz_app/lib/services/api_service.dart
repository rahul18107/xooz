import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/api.dart';
import '../models/transcript.dart';
import '../models/digest.dart';

class ApiService {
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

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return Transcript(
          id: json['transcript_id'],
          userId: ApiConfig.testUserId,
          text: json['text'],
          speakerLabels: [],
          recordedAt: DateTime.now(),
        );
      } else {
        throw Exception('Upload failed: ${response.body}');
      }
    } catch (e) {
      throw Exception('API error: $e');
    }
  }

  static Future<Digest?> getDigest({String? date}) async {
    try {
      String url = ApiConfig.getDigest(ApiConfig.testUserId);
      if (date != null) url += '?date=$date';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return Digest.fromJson({
          ...json,
          'date': date ?? DateTime.now().toIso8601String(),
        });
      } else {
        throw Exception('Failed to fetch digest: ${response.body}');
      }
    } catch (e) {
      throw Exception('API error: $e');
    }
  }
}
