import 'dart:io';
import 'dart:typed_data';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'attachment_cache.dart';

AttachmentCache createAttachmentCache() => _IoAttachmentCache();

class _IoAttachmentCache implements AttachmentCache {
  File _targetFile(Directory directory, String key, String fileName) {
    final safeKey = key.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return File(
      '${directory.path}${Platform.pathSeparator}${safeKey}_$safeName',
    );
  }

  @override
  Future<String?> write(String key, String fileName, Uint8List bytes) async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}attachments',
    );
    await directory.create(recursive: true);
    final target = _targetFile(directory, key, fileName);
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }

  @override
  Future<String?> find(String key, String fileName) async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}attachments',
    );
    final target = _targetFile(directory, key, fileName);
    if (await target.exists() && await target.length() > 0) {
      return target.path;
    }
    return null;
  }

  @override
  Future<void> open(String path) async {
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) throw StateError(result.message);
  }
}
