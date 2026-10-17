import 'dart:async';
import 'dart:io' show Directory, File, Platform, Process;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// 目录统计数据
class StorageDirectoryStats {
  const StorageDirectoryStats({
    required this.fileCount,
    required this.totalBytes,
  });

  final int fileCount;
  final int totalBytes;

  String get formattedBytes {
    if (totalBytes < 1024) return '$totalBytes B';
    if (totalBytes < 1024 * 1024) {
      return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    }
    if (totalBytes < 1024 * 1024 * 1024) {
      return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// 文件迁移执行结果
class StorageMigrationResult {
  const StorageMigrationResult({
    required this.success,
    required this.migratedCount,
    required this.totalBytes,
    this.errorMessage,
  });

  final bool success;
  final int migratedCount;
  final int totalBytes;
  final String? errorMessage;
}

/// 聊天附件与离线存储路径管理服务 (StoragePathService)
/// - 支持默认文档目录 `{Documents}/LocalShare/聊天文件`；
/// - 支持用户自定义存储位置持久化 (`gotoim.storage.custom_path.v1`)；
/// - 提供微信同款旧目录统计、异步流式无损迁移与文件管理器定位打开。
class StoragePathService extends ChangeNotifier {
  StoragePathService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String customStoragePathKey = 'gotoim.storage.custom_path.v1';

  /// 全局静态路径解析器，供无 Provider 上下文的单例（如 DefaultMediaDownloader）直接调用
  static Future<String> Function()? globalResolver;

  final FlutterSecureStorage _storage;
  String? _cachedCustomPath;
  String? _cachedDefaultPath;

  /// 获取系统默认存储根目录：`{Documents}/LocalShare/聊天文件`
  Future<String> getDefaultPath() async {
    if (_cachedDefaultPath != null && _cachedDefaultPath!.isNotEmpty) {
      return _cachedDefaultPath!;
    }
    try {
      final docs = await getApplicationDocumentsDirectory();
      final defaultDir = Directory(
        '${docs.path}${Platform.pathSeparator}LocalShare${Platform.pathSeparator}聊天文件',
      );
      if (!await defaultDir.exists()) {
        await defaultDir.create(recursive: true);
      }
      _cachedDefaultPath = defaultDir.path;
      return defaultDir.path;
    } catch (_) {
      // 降级使用当前系统临时或根目录
      final fallback = 'C:${Platform.pathSeparator}GotoIM_Files';
      _cachedDefaultPath = fallback;
      return fallback;
    }
  }

  /// 获取当前实际生效的存储根目录
  /// - 若用户设置了自定义路径且非空，则返回自定义路径；
  /// - 否则返回系统默认路径。
  Future<String> getActiveStoragePath() async {
    final custom = await getCustomPath();
    if (custom != null && custom.trim().isNotEmpty) {
      return custom.trim();
    }
    return getDefaultPath();
  }

  /// 获取持久化保存的用户自定义路径（未设置时返回 null）
  Future<String?> getCustomPath() async {
    if (_cachedCustomPath != null) return _cachedCustomPath;
    try {
      final val = await _storage.read(key: customStoragePathKey);
      if (val != null && val.trim().isNotEmpty) {
        _cachedCustomPath = val.trim();
        return _cachedCustomPath;
      }
    } catch (_) {}
    return null;
  }

  /// 设置并持久化用户自定义存储路径
  Future<void> setCustomPath(String newPath) async {
    final cleanPath = newPath.trim();
    if (cleanPath.isEmpty) {
      await resetToDefault();
      return;
    }
    _cachedCustomPath = cleanPath;
    try {
      await _storage.write(key: customStoragePathKey, value: cleanPath);
    } catch (_) {}

    // 确保新目录存在
    try {
      final dir = Directory(cleanPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } catch (_) {}

    notifyListeners();
  }

  /// 恢复使用默认存储路径
  Future<void> resetToDefault() async {
    _cachedCustomPath = null;
    try {
      await _storage.delete(key: customStoragePathKey);
    } catch (_) {}
    notifyListeners();
  }

  /// 在操作系统文件管理器中打开指定目录
  Future<bool> openInExplorer(String dirPath) async {
    if (kIsWeb) return false;
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      if (Platform.isWindows) {
        await Process.run('explorer.exe', [dir.path]);
        return true;
      } else if (Platform.isMacOS) {
        await Process.run('open', [dir.path]);
        return true;
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [dir.path]);
        return true;
      }
    } catch (e) {
      debugPrint('[StoragePathService] 打开文件夹异常: $e');
    }
    return false;
  }

  /// 统计目录下的文件数量与总大小
  Future<StorageDirectoryStats> calculateDirectoryStats(String dirPath) async {
    if (kIsWeb) return const StorageDirectoryStats(fileCount: 0, totalBytes: 0);
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        return const StorageDirectoryStats(fileCount: 0, totalBytes: 0);
      }
      int count = 0;
      int bytes = 0;
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          count++;
          try {
            bytes += await entity.length();
          } catch (_) {}
        }
      }
      return StorageDirectoryStats(fileCount: count, totalBytes: bytes);
    } catch (e) {
      debugPrint('[StoragePathService] 统计目录失败: $e');
      return const StorageDirectoryStats(fileCount: 0, totalBytes: 0);
    }
  }

  /// 执行聊天文件无损迁移：将 sourcePath 目录下的文件完整拷贝至 targetPath
  /// - 保持子目录结构 (用户/聊天对象/分类/日期)；
  /// - 支持回调通知进度 `onProgress(current, total)`；
  /// - 迁移成功后自动更新并持久化自定义存储路径。
  Future<StorageMigrationResult> migrateFiles({
    required String sourcePath,
    required String targetPath,
    bool deleteSourceFiles = false,
    void Function(int current, int total)? onProgress,
  }) async {
    if (kIsWeb) {
      return const StorageMigrationResult(
        success: false,
        migratedCount: 0,
        totalBytes: 0,
        errorMessage: 'Web 平台不支持文件系统迁移',
      );
    }

    try {
      final sourceDir = Directory(sourcePath);
      final targetDir = Directory(targetPath);

      if (!await sourceDir.exists()) {
        await setCustomPath(targetPath);
        return const StorageMigrationResult(
          success: true,
          migratedCount: 0,
          totalBytes: 0,
        );
      }

      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      final files = <File>[];
      await for (final entity in sourceDir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          files.add(entity);
        }
      }

      final total = files.length;
      if (total == 0) {
        await setCustomPath(targetPath);
        return const StorageMigrationResult(
          success: true,
          migratedCount: 0,
          totalBytes: 0,
        );
      }

      int successCount = 0;
      int transferredBytes = 0;

      for (int i = 0; i < total; i++) {
        final file = files[i];
        try {
          // 计算相对路径
          var relativePath = file.path.substring(sourceDir.path.length);
          if (relativePath.startsWith(Platform.pathSeparator) ||
              relativePath.startsWith('/') ||
              relativePath.startsWith('\\')) {
            relativePath = relativePath.substring(1);
          }

          final destFile = File(
            '${targetDir.path}${Platform.pathSeparator}$relativePath',
          );
          final destDir = destFile.parent;
          if (!await destDir.exists()) {
            await destDir.create(recursive: true);
          }

          // 复制文件
          await file.copy(destFile.path);
          final len = await destFile.length();
          transferredBytes += len;
          successCount++;

          if (deleteSourceFiles) {
            try {
              await file.delete();
            } catch (_) {}
          }
        } catch (e) {
          debugPrint('[StoragePathService] 迁移文件失败: ${file.path} -> $e');
        }

        onProgress?.call(i + 1, total);
      }

      // 迁移完成后更新配置为目标路径
      await setCustomPath(targetPath);

      return StorageMigrationResult(
        success: true,
        migratedCount: successCount,
        totalBytes: transferredBytes,
      );
    } catch (e) {
      return StorageMigrationResult(
        success: false,
        migratedCount: 0,
        totalBytes: 0,
        errorMessage: e.toString(),
      );
    }
  }
}

/// 全局 Riverpod Provider
final storagePathServiceProvider = Provider<StoragePathService>((ref) {
  final service = StoragePathService();
  StoragePathService.globalResolver = service.getActiveStoragePath;
  return service;
});
