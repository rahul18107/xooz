import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'api_service.dart';
import 'audio_service.dart';

class PendingUpload {
  final String id;
  final String path;
  final String? sourcePath;
  final DateTime createdAt;
  final Duration duration;
  bool uploading = false;
  String? error;

  PendingUpload({
    required this.id,
    required this.path,
    this.sourcePath,
    required this.createdAt,
    required this.duration,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'source_path': sourcePath,
    'created_at': createdAt.toIso8601String(),
    'duration_ms': duration.inMilliseconds,
  };

  factory PendingUpload.fromJson(Map<String, dynamic> json) => PendingUpload(
    id: json['id'] as String,
    path: json['path'] as String,
    sourcePath: json['source_path'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
    duration: Duration(milliseconds: json['duration_ms'] as int),
  );
}

class PendingUploadService extends ChangeNotifier {
  PendingUploadService._();
  static final instance = PendingUploadService._();

  final List<PendingUpload> _items = [];
  Future<void>? _initializing;
  Timer? _retryTimer;
  bool _draining = false;

  List<PendingUpload> get items => List.unmodifiable(_items);

  Future<Directory> _directory() async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}pending_uploads',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<void> initialize() => _initializing ??= _load();

  Future<void> _load() async {
    final directory = await _directory();
    await for (final entry in directory.list()) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      try {
        final item = PendingUpload.fromJson(
          jsonDecode(await entry.readAsString()) as Map<String, dynamic>,
        );
        if (await File(item.path).exists()) _items.add(item);
      } catch (_) {
        // Keep corrupt metadata on disk for inspection; never delete audio here.
      }
    }
    _items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final raw in await AudioService.recoverableRecordings()) {
      try {
        if (_items.any((item) => item.sourcePath == raw.path)) {
          await raw.delete();
          continue;
        }
        await _enqueueFile(raw, Duration.zero);
        await raw.delete();
      } catch (_) {
        // Leave the original on disk for the next launch.
      }
    }
    notifyListeners();
    _retryTimer ??= Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(retryAll()),
    );
    unawaited(retryAll());
  }

  Future<PendingUpload> enqueue(File source, Duration duration) async {
    await initialize();
    final item = await _enqueueFile(source, duration);
    unawaited(retryAll());
    return item;
  }

  Future<PendingUpload> _enqueueFile(File source, Duration duration) async {
    final directory = await _directory();
    final filename = source.uri.pathSegments.last;
    final id = filename.startsWith('xooz_') && filename.endsWith('.m4a')
        ? filename.substring(0, filename.length - 4)
        : '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    final target = File('${directory.path}${Platform.pathSeparator}$id.m4a');
    await source.copy(target.path);
    final item = PendingUpload(
      id: id,
      path: target.path,
      sourcePath: source.path,
      createdAt: DateTime.now(),
      duration: duration,
    );
    final manifest = File('${directory.path}${Platform.pathSeparator}$id.json');
    final temp = File('${manifest.path}.tmp');
    await temp.writeAsString(jsonEncode(item.toJson()), flush: true);
    await temp.rename(manifest.path);
    _items.add(item);
    notifyListeners();
    return item;
  }

  Future<void> retryAll() async {
    if (_draining) return;
    _draining = true;
    try {
      for (final item in List<PendingUpload>.of(_items)) {
        if (!_items.contains(item)) continue;
        item.uploading = true;
        item.error = null;
        notifyListeners();
        try {
          await ApiService.uploadAudio(
            File(item.path),
            duration: item.duration,
            clientRecordingId: item.id,
          );
          final manifest = File(
            '${(await _directory()).path}${Platform.pathSeparator}${item.id}.json',
          );
          if (await manifest.exists()) await manifest.delete();
          _items.remove(item);
          notifyListeners();
          // The server has acknowledged the upload; a cleanup failure is harmless.
          try {
            await File(item.path).delete();
          } catch (_) {}
        } catch (error) {
          item.error = error.toString().replaceFirst(
            RegExp(r'^ApiException:\s*'),
            '',
          );
        } finally {
          item.uploading = false;
          notifyListeners();
        }
      }
    } finally {
      _draining = false;
    }
  }
}
