import 'dart:io';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

class AudioService {
  static final _recorder = AudioRecorder();
  static String? _currentPath;

  static Future<bool> hasPermission() async {
    return await _recorder.hasPermission();
  }

  static Future<void> startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) throw Exception('Microphone permission denied');

    final support = await getApplicationSupportDirectory();
    final dir = Directory(
      '${support.path}${Platform.pathSeparator}raw_recordings',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    _currentPath =
        '${dir.path}/xooz_${DateTime.now().microsecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: _currentPath!,
    );
  }

  static Future<File?> stopRecording() async {
    final path = await _recorder.stop();
    if (path == null) return null;
    return File(path);
  }

  static Future<List<File>> recoverableRecordings() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(
      '${support.path}${Platform.pathSeparator}raw_recordings',
    );
    if (!await dir.exists()) return [];
    final files = <File>[];
    final activePath = await _recorder.isRecording() ? _currentPath : null;
    await for (final entry in dir.list()) {
      if (entry is File && entry.path != activePath &&
          entry.path.endsWith('.m4a') &&
          await entry.length() >= 2048) {
        files.add(entry);
      }
    }
    return files;
  }

  static Future<bool> isRecording() async {
    return await _recorder.isRecording();
  }

  /// Cancels the recorder. Pass `deleteFile: false` when an upload may still
  /// be reading the recording — deleting it would kill the upload mid-flight.
  static Future<void> cancelRecording({bool deleteFile = true}) async {
    await _recorder.cancel();
    if (deleteFile && _currentPath != null) {
      final file = File(_currentPath!);
      if (await file.exists()) await file.delete();
    }
  }

  /// Deletes the recording file left after a successful background upload.
  static Future<void> deletePendingFile() async {
    if (_currentPath == null) return;
    final file = File(_currentPath!);
    if (await file.exists()) await file.delete();
  }

  static void dispose() {
    _recorder.dispose();
  }
}
