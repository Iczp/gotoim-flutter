import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_environment.dart';
import '../../../../core/media/media_preview.dart';
import '../../../../core/services/file/attachment_cache.dart';
import '../../../../core/services/file/attachment_transfer_service.dart';
import '../../../../core/utils/api_url_resolver.dart';
import '../../application/chat_controller.dart';
import '../../data/models/chat_message.dart';
import 'chat_message_presentation.dart';
import 'file_message_content.dart';
import 'image_message_content.dart';
import 'message_bubble.dart';
import 'video_message_content.dart';
import 'voice_message_content.dart';

class HistoryMessageContent extends StatelessWidget {
  const HistoryMessageContent({
    required this.message,
    this.apiBaseUrl = '',
    this.presentation = ChatMessagePresentation.normal,
    this.rootMessageId,
    this.attachmentTransferService,
    super.key,
  });

  final ChatMessage message;
  final String apiBaseUrl;
  final ChatMessagePresentation presentation;
  final int? rootMessageId;
  final AttachmentTransferService? attachmentTransferService;

  int? get effectiveRootMessageId => rootMessageId ?? message.serverId;

  /// 为聊天记录内子消息附件统一补全 `su`、`msg` 与外层可见 `rootMsg` 授权参数。
  String resolveChildAttachmentUrl(
    String? rawUrl,
    String targetApiBaseUrl, {
    int? childMessageId,
    String? childSessionUnitId,
  }) => resolveAttachmentUrl(
    rawUrl,
    targetApiBaseUrl,
    sessionUnitId:
        (childSessionUnitId?.trim().isNotEmpty == true)
            ? childSessionUnitId
            : message.sessionUnitId,
    messageId: childMessageId,
    rootMessageId: effectiveRootMessageId,
  );

  /// 构造供下载、打开、另存为与在线签权使用的子消息上下文。
  AttachmentAccessContext resolveChildAccessContext({
    int? childMessageId,
    String? childSessionUnitId,
  }) => AttachmentAccessContext(
    sessionUnitId:
        (childSessionUnitId?.trim().isNotEmpty == true)
            ? childSessionUnitId!.trim()
            : message.sessionUnitId,
    messageId: childMessageId,
    rootMessageId: effectiveRootMessageId,
  );

  static String resolveEffectiveApiBaseUrl(
    BuildContext context,
    String explicitApiBaseUrl,
  ) {
    if (explicitApiBaseUrl.trim().isNotEmpty) return explicitApiBaseUrl.trim();
    try {
      return ProviderScope.containerOf(
        context,
        listen: false,
      ).read(appEnvironmentProvider).apiBaseUrl;
    } catch (_) {
      return '';
    }
  }

  static AttachmentTransferService? resolveTransferService(
    BuildContext context,
    AttachmentTransferService? explicitService,
  ) {
    if (explicitService != null) return explicitService;
    try {
      return ProviderScope.containerOf(
        context,
        listen: false,
      ).read(attachmentTransferServiceProvider);
    } catch (_) {
      return null;
    }
  }

  /// 将合并转发内容中的子消息列表标准化为 [ChatMessage]。
  List<ChatMessage> parseHistoryItems() {
    final rawList =
        message.content['items'] ??
        message.content['messageList'] ??
        message.content['messageIdList'];
    if (rawList is! List) return const <ChatMessage>[];
    final result = <ChatMessage>[];
    for (var i = 0; i < rawList.length; i++) {
      final entry = rawList[i];
      if (entry is! Map) continue;
      final normalized = _normalizeChildJson(
        Map<String, dynamic>.from(entry),
        index: i,
      );
      result.add(
        ChatMessage.fromJson(
          normalized,
          ownerId: message.ownerId,
          // 统一使用当前查看者会话上下文作为 `su`，避免将原始会话 ID 错当作鉴权主体
          sessionUnitId: message.sessionUnitId,
        ),
      );
    }
    return result;
  }

  Map<String, dynamic> _normalizeChildJson(
    Map<String, dynamic> raw, {
    required int index,
  }) {
    final serverId = raw['id'] ?? raw['messageId'] ?? raw['serverMessageId'];
    final clientMessageId = raw['clientMessageId'] ??
        (serverId == null ? 'history-item-$index' : null);
    final rawType = raw['messageType'];
    final messageType = _normalizeMessageType(rawType);
    final rawContent =
        raw['content'] is Map
            ? Map<String, dynamic>.from(raw['content'] as Map)
            : <String, dynamic>{};
    for (final key in const <String>[
      'text',
      'url',
      'originalUrl',
      'thumbnailUrl',
      'snapshotUrl',
      'snapshotThumbnailUrl',
      'gifUrl',
      'fileName',
      'fileSize',
      'size',
      'suffix',
      'title',
      'description',
      'items',
      'messageList',
      'messageIdList',
    ]) {
      if (!rawContent.containsKey(key) && raw[key] != null) {
        rawContent[key] = raw[key];
      }
    }
    if (!rawContent.containsKey('size') && raw['fileSize'] != null) {
      rawContent['size'] = raw['fileSize'];
    }
    if (!rawContent.containsKey('snapshotUrl') && raw['videoCoverUrl'] != null) {
      rawContent['snapshotUrl'] = raw['videoCoverUrl'];
    }
    final creationTime =
        raw['creationTime'] ??
        (raw['creationTimeMs'] is num
            ? DateTime.fromMillisecondsSinceEpoch(
              (raw['creationTimeMs'] as num).toInt(),
            ).toIso8601String()
            : null) ??
        (raw['timeMs'] is num
            ? DateTime.fromMillisecondsSinceEpoch(
              (raw['timeMs'] as num).toInt(),
            ).toIso8601String()
            : null);

    final senderUnit =
        raw['senderSessionUnit'] is Map
            ? raw['senderSessionUnit']
            : (raw['senderName'] != null || raw['sender'] != null)
            ? <String, dynamic>{
              'displayName':
                  (raw['senderName'] ?? raw['sender'])?.toString() ?? '未知发送者',
            }
            : null;

    return <String, dynamic>{
      ...raw,
      if (serverId != null) 'id': serverId,
      if (clientMessageId != null) 'clientMessageId': clientMessageId,
      'messageType': messageType,
      'content': rawContent,
      if (creationTime != null) 'creationTime': creationTime,
      if (senderUnit != null) 'senderSessionUnit': senderUnit,
    };
  }

  static int _normalizeMessageType(Object? rawType) {
    if (rawType is int) return rawType;
    if (rawType is num) return rawType.toInt();
    final text = rawType?.toString().trim() ?? '';
    final parsed = int.tryParse(text);
    if (parsed != null) return parsed;
    return switch (text.toLowerCase()) {
      'text' => 0,
      'cmd' => 1,
      'image' => 2,
      'sound' || 'voice' || 'audio' => 3,
      'video' => 4,
      'file' => 5,
      'link' => 6,
      'location' => 7,
      'contacts' || 'contact' || 'card' => 8,
      'redenvelope' => 9,
      'html' => 10,
      'article' => 11,
      'history' => 12,
      'template' => 13,
      _ => 0,
    };
  }

  @override
  Widget build(BuildContext context) {
    final compact = presentation == ChatMessagePresentation.quote;
    final card = SizedBox(
      width: compact ? null : 240,
      child: Row(
        children: <Widget>[
          Icon(Icons.forum_outlined, size: compact ? 19 : 28),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  message.historyTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (!compact && message.historyDescription.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      message.historyDescription,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    if (compact) {
      return card;
    }

    return MessageBubble(
      message: message,
      child: InkWell(
        onTap: () => _openDetailDialog(context),
        borderRadius: BorderRadius.circular(8),
        child: card,
      ),
    );
  }

  Future<void> _openDetailDialog(BuildContext context) async {
    final effectiveBaseUrl = resolveEffectiveApiBaseUrl(context, apiBaseUrl);
    final resolvedTransfer = resolveTransferService(
      context,
      attachmentTransferService,
    );
    final items = parseHistoryItems();
    await showDialog<void>(
      context: context,
      builder:
          (dialogContext) => _HistoryDetailDialog(
            title: message.historyTitle,
            viewerSessionUnitId: message.sessionUnitId,
            rootMessageId: effectiveRootMessageId,
            apiBaseUrl: effectiveBaseUrl,
            items: items,
            transferService: resolvedTransfer,
            resolveChildUrl:
                (raw, {childMessageId}) => resolveChildAttachmentUrl(
                  raw,
                  effectiveBaseUrl,
                  childMessageId: childMessageId,
                  childSessionUnitId: message.sessionUnitId,
                ),
            resolveChildContext:
                ({childMessageId}) => resolveChildAccessContext(
                  childMessageId: childMessageId,
                  childSessionUnitId: message.sessionUnitId,
                ),
          ),
    );
  }
}

class _HistoryDetailDialog extends StatelessWidget {
  const _HistoryDetailDialog({
    required this.title,
    required this.viewerSessionUnitId,
    required this.rootMessageId,
    required this.apiBaseUrl,
    required this.items,
    required this.transferService,
    required this.resolveChildUrl,
    required this.resolveChildContext,
  });

  final String title;
  final String viewerSessionUnitId;
  final int? rootMessageId;
  final String apiBaseUrl;
  final List<ChatMessage> items;
  final AttachmentTransferService? transferService;
  final String Function(String? rawUrl, {int? childMessageId}) resolveChildUrl;
  final AttachmentAccessContext Function({int? childMessageId})
  resolveChildContext;

  List<MediaPreviewItem> _buildChildMediaItems() {
    return items
        .where((item) => item.messageType == 2 || item.messageType == 4)
        .map((item) {
          final isVideo = item.messageType == 4;
          final source = resolveChildUrl(
            item.mediaUrl,
            childMessageId: item.serverId,
          );
          final rawThumb =
              isVideo
                  ? (item.videoCoverUrl ?? item.thumbnailUrl)
                  : item.thumbnailUrl;
          final thumb =
              rawThumb != null && rawThumb.isNotEmpty
                  ? resolveChildUrl(rawThumb, childMessageId: item.serverId)
                  : source;
          final fallbackName =
              '${item.localId}${item.fileSuffix.isNotEmpty ? item.fileSuffix : (isVideo ? '.mp4' : '.jpg')}';
          return MediaPreviewItem(
            id: item.localId,
            messageId: item.localId,
            type: isVideo ? MediaPreviewType.video : MediaPreviewType.image,
            source: source,
            thumbnail: thumb,
            fileName: item.fileName.isNotEmpty ? item.fileName : fallbackName,
            createdAt: item.createdAt,
            userId: item.ownerId.toString(),
            chatTarget: viewerSessionUnitId,
            serverMessageId: item.serverId,
            rootMessageId: rootMessageId,
            heroTag: buildMediaHeroTag(
              messageId: 'history:${item.localId}',
              mediaId: item.localId,
            ),
          );
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final mediaItems = _buildChildMediaItems();
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 480,
        height: 460,
        child:
            items.isEmpty
                ? const Center(child: Text('暂无聊天记录明细'))
                : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 16),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _buildChildRow(context, item, mediaItems);
                  },
                ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildChildRow(
    BuildContext context,
    ChatMessage child,
    List<MediaPreviewItem> mediaItems,
  ) {
    final senderName =
        child.senderName.isNotEmpty ? child.senderName : '成员';
    final mediaIndex = mediaItems.indexWhere((m) => m.id == child.localId);
    final accessContext = resolveChildContext(childMessageId: child.serverId);

    Widget contentWidget;
    switch (child.messageType) {
      case 2:
        contentWidget = ImageMessageContent(
          message: child,
          bytes: null,
          apiBaseUrl: apiBaseUrl,
          progress: null,
          mediaItems: mediaItems,
          initialIndex: mediaIndex,
          rootMessageId: rootMessageId,
          attachmentTransferService: transferService,
        );
      case 4:
        contentWidget = VideoMessageContent(
          message: child,
          apiBaseUrl: apiBaseUrl,
          progress: null,
          mediaItems: mediaItems,
          initialIndex: mediaIndex,
          rootMessageId: rootMessageId,
          attachmentTransferService: transferService,
        );
      case 5:
        contentWidget = _buildChildFileWidget(child, accessContext);
      case 3:
        contentWidget = VoiceMessageContent(
          message: child,
          rootMessageId: rootMessageId,
          onOpened: () async {},
        );
      case 12:
        contentWidget = HistoryMessageContent(
          message: child,
          apiBaseUrl: apiBaseUrl,
          rootMessageId: rootMessageId,
          attachmentTransferService: transferService,
        );
      default:
        contentWidget = SelectableText(
          child.text.isNotEmpty ? child.text : '[消息内容]',
        );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                senderName,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (child.createdAt != null)
              Text(
                _formatDateTime(child.createdAt!),
                style: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        ),
        const SizedBox(height: 6),
        contentWidget,
      ],
    );
  }

  Widget _buildChildFileWidget(
    ChatMessage child,
    AttachmentAccessContext accessContext,
  ) {
    final service = transferService;
    final transferId = 'history:${child.localId}';
    final source = resolveChildUrl(
      child.mediaUrl ?? child.linkUrl,
      childMessageId: child.serverId,
    );
    final fileName = child.fileName.isNotEmpty ? child.fileName : '附件';
    final category = resolveAttachmentCategory(
      fileName,
      fileSuffix: child.fileSuffix,
      messageType: child.messageType,
    );

    if (service == null) {
      return FileMessageContent(
        message: child,
        transfer: const AttachmentTransferState(),
        onDownload: () async {},
        onCancel: () async {},
        onOpen: () async {},
        onSaveAs: () async {},
      );
    }

    Future<void> onDownload() => service.download(
      id: transferId,
      source: source,
      fileName: fileName,
      userId: child.ownerId.toString(),
      chatTarget: viewerSessionUnitId,
      messageDate: child.createdAt,
      category: category,
      accessContext: accessContext,
      verifyOnline: true,
    );

    Future<void> onCancel() => service.cancel(
      transferId,
      userId: child.ownerId.toString(),
    );

    Future<void> onOpen() => service.open(
      id: transferId,
      source: source,
      fileName: fileName,
      userId: child.ownerId.toString(),
      chatTarget: viewerSessionUnitId,
      messageDate: child.createdAt,
      category: category,
      accessContext: accessContext,
      verifyOnline: true,
      forceVerifyOnline: true,
    );

    Future<void> onSaveAs() => service.saveAs(
      id: transferId,
      source: source,
      fileName: fileName,
      userId: child.ownerId.toString(),
      chatTarget: viewerSessionUnitId,
      messageDate: child.createdAt,
      category: category,
      mimeType: child.content['contentType']?.toString(),
      accessContext: accessContext,
      verifyOnline: true,
      forceVerifyOnline: true,
    );

    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final state = service.stateFor(
          transferId,
          userId: child.ownerId.toString(),
        );
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Flexible(
              child: FileMessageContent(
                message: child,
                transfer: state,
                onDownload: onDownload,
                onCancel: onCancel,
                onOpen: onOpen,
                onSaveAs: onSaveAs,
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: '另存为',
              icon: const Icon(Icons.download_outlined, size: 18),
              onPressed: onSaveAs,
            ),
          ],
        );
      },
    );
  }

  static String _formatDateTime(DateTime time) {
    final local = time.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.month}-${local.day} $hh:$mm';
  }
}
