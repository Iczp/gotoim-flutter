import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/file/attachment_cache.dart';
import '../services/file/attachment_transfer_service.dart';
import 'media_preview.dart';

/// 统一媒体下载器抽象，负责在全屏预览时探查本地缓存、执行下载与广播进度。
abstract class MediaDownloader {
  /// 检查媒体在本地是否已有持久化缓存文件。若有则返回本地绝对路径。
  Future<String?> getCachedPath(MediaPreviewItem item);

  /// 执行下载并返回下载完成后的本地绝对路径。
  Future<String> download(
    MediaPreviewItem item, {
    void Function(int received, int total)? onProgress,
    Object? cancelTag,
  });

  /// 取消正在进行的下载。
  Future<void> cancel(MediaPreviewItem item);
}

/// 基于 Dio 与 AttachmentCache 的默认独立下载器，适用于诊断中心和通用场景。
class DefaultMediaDownloader implements MediaDownloader {
  DefaultMediaDownloader({
    Dio? dio,
    AttachmentCache? cache,
  })  : _dio = dio ?? Dio(),
        _cache = cache ?? createAttachmentCache();

  static final DefaultMediaDownloader instance = DefaultMediaDownloader();

  final Dio _dio;
  final AttachmentCache _cache;
  final Map<String, CancelToken> _cancelTokens = {};

  String _resolveFileName(MediaPreviewItem item) {
    if (item.fileName != null && item.fileName!.trim().isNotEmpty) {
      return item.fileName!.trim();
    }
    final raw = item.source.split('?').first.split('/').last.trim();
    if (raw.isNotEmpty) return raw;
    final suffix = item.type == MediaPreviewType.video ? '.mp4' : '.jpg';
    return '${item.id}$suffix';
  }

  @override
  Future<String?> getCachedPath(MediaPreviewItem item) async {
    if (item.localPath != null && item.localPath!.isNotEmpty) {
      return item.localPath;
    }
    final fileName = _resolveFileName(item);
    final category = item.type == MediaPreviewType.video ? '视频' : '图片';
    return _cache.find(
      item.id,
      fileName,
      userId: item.userId,
      chatTarget: item.chatTarget,
      messageDate: item.createdAt,
      category: category,
    );
  }

  @override
  Future<String> download(
    MediaPreviewItem item, {
    void Function(int received, int total)? onProgress,
    Object? cancelTag,
  }) async {
    final cached = await getCachedPath(item);
    if (cached != null) return cached;

    final fileName = _resolveFileName(item);
    final cancelToken = CancelToken();
    _cancelTokens[item.id] = cancelToken;

    try {
      final response = await _dio.get<List<int>>(
        item.source,
        options: Options(responseType: ResponseType.bytes),
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          onProgress?.call(received, total);
        },
      );

      final bytes = Uint8List.fromList(response.data ?? <int>[]);
      final category = item.type == MediaPreviewType.video ? '视频' : '图片';
      final path = await _cache.write(
        item.id,
        fileName,
        bytes,
        userId: item.userId,
        chatTarget: item.chatTarget,
        messageDate: item.createdAt,
        category: category,
      );
      return path ?? '';
    } finally {
      _cancelTokens.remove(item.id);
    }
  }

  @override
  Future<void> cancel(MediaPreviewItem item) async {
    final token = _cancelTokens.remove(item.id);
    token?.cancel('User cancelled download');
  }
}

/// 桥接项目已有 AttachmentTransferService 的下载器实现。
class AttachmentTransferMediaDownloader implements MediaDownloader {
  AttachmentTransferMediaDownloader({
    required AttachmentTransferService transferService,
  }) : _transferService = transferService;

  final AttachmentTransferService _transferService;

  String _resolveFileName(MediaPreviewItem item) {
    if (item.fileName != null && item.fileName!.trim().isNotEmpty) {
      return item.fileName!.trim();
    }
    final raw = item.source.split('?').first.split('/').last.trim();
    if (raw.isNotEmpty) return raw;
    final suffix = item.type == MediaPreviewType.video ? '.mp4' : '.jpg';
    return '${item.id}$suffix';
  }

  @override
  Future<String?> getCachedPath(MediaPreviewItem item) async {
    if (item.localPath != null && item.localPath!.isNotEmpty) {
      return item.localPath;
    }
    final fileName = _resolveFileName(item);
    final category = item.type == MediaPreviewType.video ? '视频' : '图片';
    return _transferService.findCachedPath(
      id: item.id,
      fileName: fileName,
      userId: item.userId,
      chatTarget: item.chatTarget,
      messageDate: item.createdAt,
      category: category,
    );
  }

  @override
  Future<String> download(
    MediaPreviewItem item, {
    void Function(int received, int total)? onProgress,
    Object? cancelTag,
  }) async {
    final cached = await getCachedPath(item);
    if (cached != null) return cached;

    final fileName = _resolveFileName(item);
    final category = item.type == MediaPreviewType.video ? '视频' : '图片';
    final completer = Completer<String>();

    void listener() {
      final state = _transferService.stateFor(item.id);
      if (state.isDownloading && state.totalBytes > 0) {
        onProgress?.call(state.receivedBytes, state.totalBytes);
      } else if (state.isReady && state.localPath != null) {
        _transferService.removeListener(listener);
        if (!completer.isCompleted) completer.complete(state.localPath!);
      } else if (state.status == AttachmentTransferStatus.failed) {
        _transferService.removeListener(listener);
        if (!completer.isCompleted) {
          completer.completeError(state.error ?? StateError('下载失败'));
        }
      }
    }

    _transferService.addListener(listener);
    try {
      await _transferService.download(
        id: item.id,
        source: item.source,
        fileName: fileName,
        userId: item.userId,
        chatTarget: item.chatTarget,
        messageDate: item.createdAt,
        category: category,
      );
    } catch (e) {
      _transferService.removeListener(listener);
      if (!completer.isCompleted) completer.completeError(e);
    }

    return completer.future;
  }

  @override
  Future<void> cancel(MediaPreviewItem item) => _transferService.cancel(item.id);
}
