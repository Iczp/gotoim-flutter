import 'dart:typed_data';

import 'attachment_cache_stub.dart'
    if (dart.library.io) 'attachment_cache_io.dart'
    as platform;

/// Platform boundary for the private attachment cache and OS file opening.
/// The chat layer never imports `dart:io` or `open_filex` directly.
abstract class AttachmentCache {
  Future<String?> write(String key, String fileName, Uint8List bytes);

  Future<String?> find(String key, String fileName);

  Future<void> open(String path);
}

AttachmentCache createAttachmentCache() => platform.createAttachmentCache();
