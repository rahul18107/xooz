import 'package:flutter_test/flutter_test.dart';
import 'package:xooz_app/services/pending_upload_service.dart';

void main() {
  test('pending upload metadata survives serialization', () {
    final item = PendingUpload(
      id: 'xooz_123',
      path: '/recordings/xooz_123.m4a',
      sourcePath: '/raw/xooz_123.m4a',
      createdAt: DateTime.utc(2026, 11, 13),
      duration: const Duration(seconds: 42),
    );

    final restored = PendingUpload.fromJson(item.toJson());

    expect(restored.id, item.id);
    expect(restored.path, item.path);
    expect(restored.sourcePath, item.sourcePath);
    expect(restored.duration, item.duration);
    expect(restored.createdAt, item.createdAt);
  });
}
