import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ExportException implements Exception {
  final String message;
  ExportException(this.message);

  @override
  String toString() => message;
}

/// Exports a stored recording (Supabase .m4a / AAC) as a real .mp3 file
/// using the on-device ffmpeg (libmp3lame) encoder.
class AudioExportService {
  /// Downloads the recording, converts it to .mp3, and cleans up the
  /// intermediate file. Returns the converted file ready to share/save.
  static Future<XFile> exportToMp3({
    required String url,
    required String fileName,
  }) async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final safeName = _sanitize(fileName);
    final localSource = File('${dir.path}/xooz_export_${stamp}_src.m4a');
    final mp3File = File('${dir.path}/xooz_export_${stamp}_$safeName.mp3');

    // 1. fetch the stored recording
    if (!await localSource.exists()) {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 90));
      if (response.statusCode != 200) {
        throw ExportException(
          'Could not download the recording (status ${response.statusCode})',
        );
      }
      await localSource.writeAsBytes(response.bodyBytes, flush: true);
    }

    // 2. convert AAC -> MP3 (-q:a 2 = high quality VBR)
    final session = await FFmpegKit.executeWithArguments([
      '-y',
      '-i',
      localSource.path,
      '-vn',
      '-codec:a',
      'libmp3lame',
      '-q:a',
      '2',
      mp3File.path,
    ]);
    final returnCode = await session.getReturnCode();
    final converted = await mp3File.exists();

    if (ReturnCode.isSuccess(returnCode) && converted) {
      try {
        await localSource.delete();
      } catch (_) {}
      return XFile(mp3File.path, mimeType: 'audio/mpeg', name: '$safeName.mp3');
    }

    // 3. conversion failed — gather a hint from the logs
    if (converted) {
      try {
        await mp3File.delete();
      } catch (_) {}
    }
    try {
      await localSource.delete();
    } catch (_) {}
    throw ExportException('Audio conversion failed (ffmpeg ${returnCode?.getValue()})');
  }

  static String _sanitize(String name) {
    final clean = name
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
    if (clean.isEmpty) return 'recording';
    return clean.substring(0, clean.length > 40 ? 40 : clean.length);
  }
}
