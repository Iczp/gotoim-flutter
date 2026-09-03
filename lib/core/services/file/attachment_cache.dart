import 'dart:typed_data';

import 'attachment_cache_stub.dart'
    if (dart.library.io) 'attachment_cache_io.dart'
    as platform;

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
    DateTime? messageDate,
    String? category,
  });

  Future<String?> find(
    String key,
    String fileName, {
    DateTime? messageDate,
    String? category,
  });

  Future<void> open(String path);
}

AttachmentCache createAttachmentCache() => platform.createAttachmentCache();
