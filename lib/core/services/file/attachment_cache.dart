import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'attachment_cache_stub.dart'
    if (dart.library.io) 'attachment_cache_io.dart'
    as platform;
import 'storage_path_service.dart';

/// 根据文件后缀或消息类型解析附件所属类别（用于目录分类保存与局域网管理站）
String resolveAttachmentCategory(
  String fileName, {
  String? fileSuffix,
  int? messageType,
}) {
  if (messageType == 2) return '图片';
  if (messageType == 4) return '视频';
  if (messageType == 3) return '语音';
  final ext = (fileSuffix != null && fileSuffix.isNotEmpty
          ? fileSuffix
          : (fileName.contains('.') ? '.${fileName.split('.').last}' : ''))
      .toLowerCase();
  if (['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.heic', '.svg']
      .contains(ext)) {
    return '图片';
  }
  if (['.mp4', '.mov', '.avi', '.mkv', '.flv', '.wmv', '.webm', '.3gp']
      .contains(ext)) {
    return '视频';
  }
  if (['.mp3', '.m4a', '.wav', '.aac', '.flac', '.ogg', '.amr'].contains(ext)) {
    return '语音';
  }
  if ([
    '.pdf',
    '.doc',
    '.docx',
    '.xls',
    '.xlsx',
    '.ppt',
    '.pptx',
    '.txt',
    '.md',
    '.zip',
    '.rar',
    '.7z',
    '.tar',
    '.gz',
    '.json',
    '.csv',
  ].contains(ext)) {
    return '文档';
  }
  return '文档';
}

final RegExp _blobRouteRegex = RegExp(
  r'/(?:api/chat/)?file/([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}|[0-9a-fA-F]{32})(?:[/?#]|$)',
  caseSensitive: false,
);
final RegExp _blobGuidExactRegex = RegExp(
  r'^(?:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}|[0-9a-fA-F]{32})$',
);
const Set<String> _volatileCacheQueryParams = <String>{
  'su',
  'msg',
  'rootmsg',
  'exp',
  'sig',
  'token',
  'access_token',
};

/// 从附件 URL 中提取共享的 BlobId（忽略 su/msg/rootMsg/exp/sig 等短时上下文与签名参数）
String? extractAttachmentBlobId(String? source) {
  final raw = source?.trim() ?? '';
  if (raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  final path = uri?.path ?? raw;
  final routeMatch = _blobRouteRegex.firstMatch(path);
  if (routeMatch != null) {
    return routeMatch.group(1)!.toLowerCase();
  }
  if (uri != null) {
    for (final entry in uri.queryParameters.entries) {
      if (entry.key.toLowerCase() == 'id' &&
          _blobGuidExactRegex.hasMatch(entry.value.trim())) {
        return entry.value.trim().toLowerCase();
      }
    }
  }
  return null;
}

String _resolveNormalizedOrigin(String? source, String? serverOrigin) {
  final sourceUri = source != null ? Uri.tryParse(source.trim()) : null;
  if (sourceUri != null && sourceUri.hasScheme && sourceUri.host.isNotEmpty) {
    final port = sourceUri.hasPort ? ':${sourceUri.port}' : '';
    return '${sourceUri.scheme.toLowerCase()}://${sourceUri.host.toLowerCase()}$port';
  }
  final baseUri =
      serverOrigin != null ? Uri.tryParse(serverOrigin.trim()) : null;
  if (baseUri != null && baseUri.hasScheme && baseUri.host.isNotEmpty) {
    final port = baseUri.hasPort ? ':${baseUri.port}' : '';
    return '${baseUri.scheme.toLowerCase()}://${baseUri.host.toLowerCase()}$port';
  }
  return 'default';
}

String _fnv1aHex(String input) {
  var h1 = 0x811c9dc5;
  var h2 = 0x01000193;
  for (final code in input.codeUnits) {
    h1 ^= code;
    h1 = (h1 * 0x01000193) & 0xffffffff;
    h2 ^= (code + 0x9e3779b9) & 0xffffffff;
    h2 = (h2 * 0x85ebca6b) & 0xffffffff;
  }
  return '${h1.toRadixString(16).padLeft(8, '0')}${h2.toRadixString(16).padLeft(8, '0').substring(0, 4)}';
}

/// 生成按「服务端实例 + BlobId」归一化的缓存键；账号隔离由目录 `<userId>` 负责
String normalizeAttachmentCacheKey({
  String? source,
  String? blobId,
  required String fallbackKey,
  String? serverOrigin,
}) {
  final normalizedExplicit =
      blobId != null && _blobGuidExactRegex.hasMatch(blobId.trim())
          ? blobId.trim().toLowerCase()
          : null;
  final effectiveBlobId = normalizedExplicit ?? extractAttachmentBlobId(source);
  if (effectiveBlobId != null) {
    final origin = _resolveNormalizedOrigin(source, serverOrigin);
    return 'blob_${_fnv1aHex(origin)}_$effectiveBlobId';
  }

  final raw = (source?.trim().isNotEmpty == true ? source!.trim() : fallbackKey)
      .trim();
  final uri = Uri.tryParse(raw);
  if (uri != null && uri.queryParameters.isNotEmpty) {
    final filtered = <String, List<String>>{};
    for (final entry in uri.queryParametersAll.entries) {
      if (!_volatileCacheQueryParams.contains(entry.key.toLowerCase())) {
        filtered[entry.key] = entry.value;
      }
    }
    final cleanUri = uri.replace(
      queryParameters: filtered.isEmpty ? null : filtered,
    );
    final sanitized =
        cleanUri.toString().replaceAll(RegExp(r'\?$'), '');
    if (sanitized.isNotEmpty && raw == source?.trim()) {
      return '${_fnv1aHex(sanitized)}_${fallbackKey.trim()}';
    }
  }
  return fallbackKey.trim();
}

/// 格式化日期作为目录名：yyyy-MM-dd
String resolveDateFolder(DateTime? date) {
  final d = date ?? DateTime.now();
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// Platform boundary for the private attachment cache and OS file opening.
/// The chat layer never imports `dart:io` or `open_filex` directly.
abstract class AttachmentCache {
  Future<String?> write(
    String key,
    String fileName,
    Uint8List bytes, {
    String? userId,
    String? chatTarget,
    DateTime? messageDate,
    String? category,
  });

  Future<String?> find(
    String key,
    String fileName, {
    String? userId,
    String? chatTarget,
    DateTime? messageDate,
    String? category,
  });

  Future<bool> exists(String path);

  Future<Uint8List?> readBytes(String path);

  Future<void> open(String path);
}

AttachmentCache createAttachmentCache({
  Future<String> Function()? storagePathResolver,
}) => platform.createAttachmentCache(storagePathResolver: storagePathResolver);

/// 全局 AttachmentCache Provider，默认注入持久化存储路径解析器
final attachmentCacheProvider = Provider<AttachmentCache>((ref) {
  final storageService = ref.watch(storagePathServiceProvider);
  return createAttachmentCache(
    storagePathResolver: storageService.getActiveStoragePath,
  );
});
