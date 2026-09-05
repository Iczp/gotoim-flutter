import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

/// 跨平台相册存储与复制服务。
///
/// 负责将已下载或生成的图片、视频文件保存/复制到设备系统相册中。
abstract class MediaGallerySaver {
  /// 保存/复制图片到系统相册。
  static Future<bool> saveImage(String filePath, {String? album}) async {
    try {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows)) {
        final hasAccess = await Gal.hasAccess(toAlbum: album != null);
        if (!hasAccess) {
          final granted = await Gal.requestAccess(toAlbum: album != null);
          if (!granted) {
            throw StateError('保存失败：未授予相册访问权限');
          }
        }
        await Gal.putImage(filePath, album: album);
        return true;
      }
      return await _saveToDesktopMediaFolder(filePath, isVideo: false);
    } on GalException catch (e) {
      if (e.type == GalExceptionType.accessDenied) {
        throw StateError('保存失败：未授予相册访问权限');
      }
      // 桌面端或特定系统若 Gal 未能成功，降级尝试拷贝至系统图片/视频目录
      return _saveToDesktopMediaFolder(filePath, isVideo: false);
    } catch (e) {
      // 降级尝试拷贝至系统媒体目录
      return _saveToDesktopMediaFolder(filePath, isVideo: false);
    }
  }

  /// 保存/复制视频到系统相册。
  static Future<bool> saveVideo(String filePath, {String? album}) async {
    try {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows)) {
        final hasAccess = await Gal.hasAccess(toAlbum: album != null);
        if (!hasAccess) {
          final granted = await Gal.requestAccess(toAlbum: album != null);
          if (!granted) {
            throw StateError('保存失败：未授予相册访问权限');
          }
        }
        await Gal.putVideo(filePath, album: album);
        return true;
      }
      return await _saveToDesktopMediaFolder(filePath, isVideo: true);
    } on GalException catch (e) {
      if (e.type == GalExceptionType.accessDenied) {
        throw StateError('保存失败：未授予相册访问权限');
      }
      return _saveToDesktopMediaFolder(filePath, isVideo: true);
    } catch (e) {
      return _saveToDesktopMediaFolder(filePath, isVideo: true);
    }
  }

  /// 针对桌面端（Windows/Linux/macOS）降级保存至系统 Pictures / Videos 目录。
  static Future<bool> _saveToDesktopMediaFolder(
    String filePath, {
    required bool isVideo,
  }) async {
    if (kIsWeb) return false;
    try {
      final sourceFile = File(filePath);
      if (!await sourceFile.exists()) {
        throw StateError('源文件不存在：$filePath');
      }
      Directory? targetDir;
      if (isVideo) {
        try {
          targetDir = await getDownloadsDirectory();
        } catch (_) {}
      } else {
        try {
          targetDir = await getApplicationDocumentsDirectory();
        } catch (_) {}
      }
      targetDir ??= await getApplicationDocumentsDirectory();

      final fileName = sourceFile.uri.pathSegments.isNotEmpty
          ? sourceFile.uri.pathSegments.last
          : 'media_${DateTime.now().millisecondsSinceEpoch}';
      final destination = File('${targetDir.path}${Platform.pathSeparator}$fileName');
      await sourceFile.copy(destination.path);
      return true;
    } catch (e) {
      debugPrint('[MediaGallerySaver] 降级复制至本地目录失败: $e');
      return false;
    }
  }
}
