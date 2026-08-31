import 'dart:typed_data';

import 'attachment_cache.dart';

AttachmentCache createAttachmentCache() => _UnsupportedAttachmentCache();

class _UnsupportedAttachmentCache implements AttachmentCache {
  @override
  Future<void> open(String path) =>
      throw UnsupportedError('当前平台不能直接使用系统程序打开附件。');

  @override
  Future<String?> write(String key, String fileName, Uint8List bytes) async =>
      null;
}
