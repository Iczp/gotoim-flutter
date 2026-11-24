import 'package:flutter/foundation.dart';

enum AttachmentMediaType {
  image('图片'),
  video('视频'),
  audio('音频'),
  file('文件'),
  link('链接');

  const AttachmentMediaType(this.label);
  final String label;

  int get serverMessageType => switch (this) {
    AttachmentMediaType.image => 2,
    AttachmentMediaType.audio => 3,
    AttachmentMediaType.video => 4,
    AttachmentMediaType.file => 5,
    AttachmentMediaType.link => 6,
  };

  static AttachmentMediaType fromServerMessageType(int? type) => switch (type) {
    2 => AttachmentMediaType.image,
    3 => AttachmentMediaType.audio,
    4 => AttachmentMediaType.video,
    6 => AttachmentMediaType.link,
    _ => AttachmentMediaType.file,
  };
}

enum AttachmentSource {
  session('当前会话'),
  favorites('我的收藏'),
  global('全部会话'),
  custom('指定列表'),
  local('本地上传');

  const AttachmentSource(this.label);
  final String label;
}

enum AttachmentBrowserMode { viewer, singleSelect, multiSelect }

enum AttachmentDatePreset {
  all('全部时间'),
  today('今天'),
  days7('近 7 天'),
  days30('近 30 天'),
  days90('近 90 天'),
  year('今年'),
  custom('自定义日期');

  const AttachmentDatePreset(this.label);
  final String label;
}

enum AttachmentSortBy {
  timeDesc('最新优先', 'CreationTime desc'),
  timeAsc('最早优先', 'CreationTime asc'),
  sizeDesc('文件最大', 'Size desc'),
  sizeAsc('文件最小', 'Size asc'),
  nameAsc('名称排序', 'Id desc');

  const AttachmentSortBy(this.label, this.serverSorting);
  final String label;
  final String serverSorting;
}

enum AttachmentLayout { grid, list, timeline }

@immutable
class AttachmentAsset {
  const AttachmentAsset({
    required this.id,
    required this.source,
    required this.mediaType,
    required this.fileName,
    required this.url,
    required this.creationTime,
    this.extension,
    this.mimeType,
    this.sizeBytes,
    this.thumbnailUrl,
    this.durationSeconds,
    this.width,
    this.height,
    this.blobId,
    this.messageId,
    this.sessionUnitId,
    this.sessionId,
    this.sessionName,
    this.senderId,
    this.senderName,
    this.isFavorited = false,
    this.tags = const <String>[],
  });

  final String id;
  final AttachmentSource source;
  final AttachmentMediaType mediaType;
  final String fileName;
  final String url;
  final String creationTime;
  final String? extension;
  final String? mimeType;
  final int? sizeBytes;
  final String? thumbnailUrl;
  final int? durationSeconds;
  final int? width;
  final int? height;
  final String? blobId;
  final String? messageId;
  final String? sessionUnitId;
  final String? sessionId;
  final String? sessionName;
  final String? senderId;
  final String? senderName;
  final bool isFavorited;
  final List<String> tags;

  factory AttachmentAsset.fromMessageJson(
    Map<String, dynamic> msg, {
    required AttachmentSource source,
    String? overrideCreationTime,
    String? overrideSessionUnitId,
  }) {
    final id = (msg['id'] ?? msg['messageId'] ?? '').toString();
    final msgType = (msg['messageType'] as num?)?.toInt();
    final mediaType = AttachmentMediaType.fromServerMessageType(msgType);
    final content = msg['content'] is Map
        ? Map<String, dynamic>.from(msg['content'] as Map)
        : const <String, dynamic>{};

    final url = (content['url'] ??
            content['originalUrl'] ??
            content['actionUrl'] ??
            content['linkUrl'] ??
            '')
        .toString();
    final thumb =
        (content['thumbnailUrl'] ?? content['coverUrl'])?.toString();
    final fileName = (content['fileName'] ??
            content['title'] ??
            content['name'] ??
            (mediaType == AttachmentMediaType.image
                ? 'image_$id.jpg'
                : mediaType == AttachmentMediaType.video
                    ? 'video_$id.mp4'
                    : 'file_$id'))
        .toString();
    final suffixRaw = content['suffix']?.toString() ??
        (fileName.contains('.') ? fileName.split('.').last : null);
    final ext = suffixRaw != null && suffixRaw.isNotEmpty
        ? '.${suffixRaw.replaceFirst(RegExp(r'^\.'), '').toLowerCase()}'
        : null;
    final sizeBytes =
        ((content['size'] ?? msg['size']) as num?)?.toInt();

    final senderUnit = msg['senderSessionUnit'];
    String? senderName;
    if (senderUnit is Map) {
      senderName = senderUnit['displayName']?.toString() ??
          (senderUnit['owner'] is Map
              ? senderUnit['owner']['name']?.toString()
              : null);
    }
    senderName ??= msg['senderName']?.toString();

    return AttachmentAsset(
      id: id,
      source: source,
      mediaType: mediaType,
      fileName: fileName,
      url: url,
      creationTime:
          overrideCreationTime ?? msg['creationTime']?.toString() ?? '',
      extension: ext,
      mimeType: content['contentType']?.toString(),
      sizeBytes: sizeBytes,
      thumbnailUrl: thumb,
      durationSeconds:
          ((content['time'] ?? content['duration']) as num?)?.toInt(),
      width: (content['width'] as num?)?.toInt(),
      height: (content['height'] as num?)?.toInt(),
      blobId: content['blobId']?.toString(),
      messageId: id,
      sessionUnitId:
          overrideSessionUnitId ?? msg['senderSessionUnitId']?.toString(),
      sessionId: msg['sessionId']?.toString(),
      sessionName: msg['sessionName']?.toString(),
      senderId: msg['senderId']?.toString(),
      senderName: senderName,
      isFavorited:
          source == AttachmentSource.favorites || msg['isFavorited'] == true,
    );
  }
}

@immutable
class AttachmentBrowserOptions {
  const AttachmentBrowserOptions({
    this.mode = AttachmentBrowserMode.viewer,
    this.title,
    this.subtitle,
    this.sources = const <AttachmentSource>[
      AttachmentSource.session,
      AttachmentSource.favorites,
      AttachmentSource.global,
    ],
    this.defaultSource = AttachmentSource.session,
    this.sessionUnitId,
    this.sessionId,
    this.ownerId,
    this.allowSwitchSession = true,
    this.customItems = const <AttachmentAsset>[],
    this.defaultTypes = const <AttachmentMediaType>[],
    this.allowedTypes,
    this.datePreset = AttachmentDatePreset.all,
    this.startTime,
    this.endTime,
    this.senderId,
    this.minSizeBytes,
    this.maxSizeBytes,
    this.keyword,
    this.tags = const <String>[],
    this.extensions = const <String>[],
    this.sortBy = AttachmentSortBy.timeDesc,
    this.minCount = 0,
    this.maxCount,
    this.maxFileSize,
    this.allowedExtensions,
    this.initialSelectedIds = const <String>[],
    this.disabledIds = const <String>[],
    this.lockedIds = const <String>[],
    this.defaultLayout = AttachmentLayout.grid,
    this.enablePreview = true,
    this.enableDownload = true,
    this.enableForward = true,
    this.enableLocateMessage = true,
    this.allowLocalUpload = false,
    this.confirmButtonText,
    this.emptyText,
    this.alwaysOnTop = false,
  });

  final AttachmentBrowserMode mode;
  final String? title;
  final String? subtitle;
  final List<AttachmentSource> sources;
  final AttachmentSource defaultSource;
  final String? sessionUnitId;
  final String? sessionId;
  final String? ownerId;
  final bool allowSwitchSession;
  final List<AttachmentAsset> customItems;
  final List<AttachmentMediaType> defaultTypes;
  final List<AttachmentMediaType>? allowedTypes;
  final AttachmentDatePreset datePreset;
  final DateTime? startTime;
  final DateTime? endTime;
  final String? senderId;
  final int? minSizeBytes;
  final int? maxSizeBytes;
  final String? keyword;
  final List<String> tags;
  final List<String> extensions;
  final AttachmentSortBy sortBy;
  final int minCount;
  final int? maxCount;
  final int? maxFileSize;
  final List<String>? allowedExtensions;
  final List<String> initialSelectedIds;
  final List<String> disabledIds;
  final List<String> lockedIds;
  final AttachmentLayout defaultLayout;
  final bool enablePreview;
  final bool enableDownload;
  final bool enableForward;
  final bool enableLocateMessage;
  final bool allowLocalUpload;
  final String? confirmButtonText;
  final String? emptyText;
  final bool alwaysOnTop;
}

@immutable
class AttachmentBrowserResult {
  const AttachmentBrowserResult({
    required this.confirmed,
    required this.selectedItems,
  });

  final bool confirmed;
  final List<AttachmentAsset> selectedItems;
}
