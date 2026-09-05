import 'dart:io';
import 'dart:typed_data';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'attachment_cache.dart';

AttachmentCache createAttachmentCache() => _IoAttachmentCache();

class _IoAttachmentCache implements AttachmentCache {
  String _sanitizeKey(String key) =>
      key.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

  String _sanitizeName(String fileName) =>
      fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

  String _sanitizeSegment(String? value, String fallback) {
    if (value == null || value.trim().isEmpty) return fallback;
    final sanitized = value.trim().replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');
    return sanitized.isEmpty ? fallback : sanitized;
  }

  /// 获取局域网文件共享站“聊天文件”根目录：
  /// ${Documents}/LocalShare/聊天文件
  Future<Directory> _getChatFilesRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${docs.path}${Platform.pathSeparator}LocalShare${Platform.pathSeparator}聊天文件',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 获取按 用户/聊天对象/类型/日期 分级的目标目录：
  /// `${Documents}/LocalShare/聊天文件/<用户>/<聊天对象>/<分类>/<yyyy-MM-dd>`
  Future<Directory> _resolveDirectory({
    required String fileName,
    String? userId,
    String? chatTarget,
    DateTime? messageDate,
    String? category,
  }) async {
    final root = await _getChatFilesRoot();
    final userSegment = _sanitizeSegment(userId, 'default_user');
    final targetSegment = _sanitizeSegment(chatTarget, 'default_target');
    final cat = category ?? resolveAttachmentCategory(fileName);
    final date = resolveDateFolder(messageDate);
    final dir = Directory(
      '${root.path}${Platform.pathSeparator}$userSegment${Platform.pathSeparator}$targetSegment${Platform.pathSeparator}$cat${Platform.pathSeparator}$date',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  File _targetFile(Directory directory, String key, String fileName) {
    final safeKey = _sanitizeKey(key);
    final safeName = _sanitizeName(fileName);
    return File(
      '${directory.path}${Platform.pathSeparator}${safeKey}_$safeName',
    );
  }

  @override
  Future<String?> write(
    String key,
    String fileName,
    Uint8List bytes, {
    String? userId,
    String? chatTarget,
    DateTime? messageDate,
    String? category,
  }) async {
    final directory = await _resolveDirectory(
      fileName: fileName,
      userId: userId,
      chatTarget: chatTarget,
      messageDate: messageDate,
      category: category,
    );
    final target = _targetFile(directory, key, fileName);
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }

  @override
  Future<String?> find(
    String key,
    String fileName, {
    String? userId,
    String? chatTarget,
    DateTime? messageDate,
    String? category,
  }) async {
    final safeKey = _sanitizeKey(key);
    final safeName = _sanitizeName(fileName);
    final root = await _getChatFilesRoot();

    // 1. 如果指定了用户与聊天对象，优先在精确的 用户/聊天对象/类型/日期 目录下寻找
    if (userId != null && chatTarget != null) {
      final userSegment = _sanitizeSegment(userId, 'default_user');
      final targetSegment = _sanitizeSegment(chatTarget, 'default_target');
      final cat = category ?? resolveAttachmentCategory(fileName);
      final date = resolveDateFolder(messageDate);
      final exactDir = Directory(
        '${root.path}${Platform.pathSeparator}$userSegment${Platform.pathSeparator}$targetSegment${Platform.pathSeparator}$cat${Platform.pathSeparator}$date',
      );
      if (await exactDir.exists()) {
        final exactFile = File('${exactDir.path}${Platform.pathSeparator}${safeKey}_$safeName');
        if (await exactFile.exists() && await exactFile.length() > 0) {
          return exactFile.path;
        }
        final exactPlain = File('${exactDir.path}${Platform.pathSeparator}$safeName');
        if (await exactPlain.exists() && await exactPlain.length() > 0) {
          return exactPlain.path;
        }
      }

      // 2. 在当前用户的当前会话目录下递回查找
      final targetDir = Directory(
        '${root.path}${Platform.pathSeparator}$userSegment${Platform.pathSeparator}$targetSegment',
      );
      if (await targetDir.exists()) {
        final found = await _searchInDirectory(targetDir, safeKey, safeName);
        if (found != null) return found;
      }

      // 3. 在当前用户目录下跨会话查找
      final userDir = Directory('${root.path}${Platform.pathSeparator}$userSegment');
      if (await userDir.exists()) {
        final found = await _searchInDirectory(userDir, safeKey, safeName);
        if (found != null) return found;
      }
    }

    // 4. 扫描 LocalShare/聊天文件 下所有层级子目录（跨用户/未传入用户信息时查找）
    if (await root.exists()) {
      final found = await _searchInDirectory(root, safeKey, safeName);
      if (found != null) return found;
    }

    // 5. 兜底兼容旧版私有缓存目录（getApplicationSupportDirectory()/attachments）
    try {
      final supportRoot = await getApplicationSupportDirectory();
      final legacyDir = Directory(
        '${supportRoot.path}${Platform.pathSeparator}attachments',
      );
      if (await legacyDir.exists()) {
        final legacyFile = _targetFile(legacyDir, key, fileName);
        if (await legacyFile.exists() && await legacyFile.length() > 0) {
          return legacyFile.path;
        }
      }
    } catch (_) {}

    return null;
  }

  Future<String?> _searchInDirectory(
    Directory dir,
    String safeKey,
    String safeName,
  ) async {
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final name = entity.uri.pathSegments.isNotEmpty
            ? entity.uri.pathSegments.last
            : '';
        if ((name == '${safeKey}_$safeName' ||
                name == safeName ||
                (safeKey.isNotEmpty && name.startsWith('${safeKey}_'))) &&
            await entity.length() > 0) {
          return entity.path;
        }
      }
    }
    return null;
  }

  @override
  Future<void> open(String path) async {
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) throw StateError(result.message);
  }
}
