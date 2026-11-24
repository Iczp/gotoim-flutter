import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/features/attachment_browser/domain/attachment_browser_models.dart';

void main() {
  group('AttachmentBrowser models', () {
    test('AttachmentAsset.fromMessageJson maps image message correctly', () {
      final asset = AttachmentAsset.fromMessageJson(
        <String, dynamic>{
          'id': '1001',
          'messageType': 2,
          'sessionId': 'sess-1',
          'senderId': '42',
          'creationTime': '2026-11-25T00:00:00Z',
          'content': <String, dynamic>{
            'fileName': 'diagram.png',
            'url': 'https://cdn.example.com/diagram.png',
            'thumbnailUrl': 'https://cdn.example.com/diagram_thumb.png',
            'size': 204800,
            'suffix': 'png',
            'blobId': 'blob-1',
          },
        },
        source: AttachmentSource.session,
      );

      expect(asset.id, '1001');
      expect(asset.mediaType, AttachmentMediaType.image);
      expect(asset.fileName, 'diagram.png');
      expect(asset.extension, '.png');
      expect(asset.sizeBytes, 204800);
      expect(asset.blobId, 'blob-1');
    });

    test('AttachmentBrowserOptions preserves rich & special parameters', () {
      const options = AttachmentBrowserOptions(
        mode: AttachmentBrowserMode.multiSelect,
        title: '选择功课媒体',
        allowedTypes: [AttachmentMediaType.image, AttachmentMediaType.video],
        maxCount: 9,
        maxFileSize: 50 * 1024 * 1024,
        allowedExtensions: ['.jpg', '.png', '.mp4'],
        tags: ['homework'],
        allowLocalUpload: true,
        alwaysOnTop: true,
      );

      expect(options.mode, AttachmentBrowserMode.multiSelect);
      expect(options.maxCount, 9);
      expect(options.tags, ['homework']);
      expect(options.allowLocalUpload, true);
      expect(options.alwaysOnTop, true);
    });
  });
}
