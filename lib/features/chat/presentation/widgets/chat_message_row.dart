import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';

import '../../../../core/media/media_preview.dart';
import '../../../../core/services/file/attachment_transfer_service.dart';
import '../../../../core/widgets/chat_bubble.dart';
import '../../../session/presentation/chat_object_avatar.dart';
import '../../data/models/chat_message.dart';
import '../message_content/chat_message_content_renderer.dart';
import 'chat_message_delivery_state.dart';
import 'chat_quote_preview.dart';

/// 单条消息气泡行组件（ChatMessageRow）
///
/// 核心职责：
/// 1. 负责单条聊天记录的布局呈现（左侧好友消息 / 右侧我方发送消息）；
/// 2. 展示发送者头像、昵称、以及时间分割线（大于 5 分钟自动展示）；
/// 3. 集成气泡容器 [ChatBubble] 与富媒体消息渲染器 [ChatMessageContentRenderer]；
/// 4. 展示消息送达/发送中/失败重试状态 [ChatMessageDeliveryState] 与对方已读标记；
/// 5. 展示被引用的消息预览模块 [ChatQuotePreview]；
/// 6. 多选模式下提供选择勾选框，并保证勾选槽位预留防止文本气泡产生抖动重排。
class ChatMessageRow extends StatelessWidget {
  const ChatMessageRow({
    required this.message,
    required this.showTime,
    required this.onUserTap,
    required this.onVoiceOpened,
    required this.onLinkTap,
    required this.mediaItems,
    required this.mediaInitialIndex,
    required this.attachmentState,
    required this.onAttachmentDownload,
    required this.onAttachmentCancel,
    required this.onAttachmentOpen,
    required this.onAttachmentSaveAs,
    this.onRetry,
    required this.imageBytes,
    required this.uploadProgress,
    required this.apiBaseUrl,
    required this.selected,
    required this.selectionMode,
    required this.onQuoteTap,
    this.quoteContent,
    required this.showUnreadDivider,
    required this.showPeerRead,
    this.onTap,
    super.key,
  });

  /// 当前消息数据模型
  final ChatMessage message;

  /// 是否显示时间分割线
  final bool showTime;

  /// 点击发送人头像/昵称回调（打开成员资料卡）
  final VoidCallback onUserTap;

  /// 点击播放语音消息回调（标记已听）
  final Future<void> Function() onVoiceOpened;

  /// 点击消息中链接回调（复制链接）
  final Future<void> Function() onLinkTap;

  /// 全屏多媒体浏览器资源列表
  final List<MediaPreviewItem> mediaItems;

  /// 当前消息在多媒体浏览器中的索引
  final int mediaInitialIndex;

  /// 当前消息附件传输状态
  final AttachmentTransferState attachmentState;

  /// 附件下载回调
  final Future<void> Function() onAttachmentDownload;

  /// 附件取消下载回调
  final Future<void> Function() onAttachmentCancel;

  /// 打开附件回调
  final Future<void> Function() onAttachmentOpen;

  /// 附件另存为回调
  final Future<void> Function() onAttachmentSaveAs;

  /// 失败消息重发回调
  final VoidCallback? onRetry;

  /// 本地图片快速预览字节数据
  final Uint8List? imageBytes;

  /// 附件上传进度（0.0 ~ 1.0）
  final double? uploadProgress;

  /// API Base URL（用于拼接富媒体相对路径）
  final String apiBaseUrl;

  /// 多选模式下当前消息是否已被选中
  final bool selected;

  /// 是否处于多选模式
  final bool selectionMode;

  /// 点击引用预览区域回调（跳转并定位至被引用的历史消息）
  final VoidCallback onQuoteTap;

  /// 被引用的历史消息内容 Widget
  final Widget? quoteContent;

  /// 是否展示“以下为新消息”未读分割线
  final bool showUnreadDivider;

  /// 是否展示对方“已读”标记
  final bool showPeerRead;

  /// 点击整行区域回调（多选模式下切换选中状态）
  final VoidCallback? onTap;


  String get _senderLabel {
    if (!kDebugMode) return message.senderName;
    final messageId = message.serverId?.toString() ?? message.localId;
    return '${message.senderName} · $messageId';
  }

  @override
  Widget build(BuildContext context) {
    final renderedQuote = quoteContent;
    if (message.messageType == 1) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Text(
            message.text.isEmpty ? '[系统消息]' : message.text,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }
    if (message.isRollbacked) {
      return Padding(
        padding: const EdgeInsets.all(10),
        child: Center(child: Text('$_senderLabel 撤回了一条消息')),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: <Widget>[
          if (showUnreadDivider)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: <Widget>[
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text('以下为新消息'),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
            ),
          if (showTime)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                _time(message.createdAt),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              const selectionSlotWidth = 36.0;
              const avatarSlotWidth = 48.0;
              final contentMaxWidth = (constraints.maxWidth -
                      selectionSlotWidth -
                      avatarSlotWidth)
                  .clamp(0.0, double.infinity);
              final bubbleWidth = contentMaxWidth * 0.68;
              final avatar = GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onUserTap,
                child: ChatObjectAvatar(
                  name: message.senderName,
                  imageUrl: message.senderAvatarUrl,
                  radius: 18,
                ),
              );
              final content = Expanded(
                child: Column(
                  crossAxisAlignment:
                      message.isMine
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                  children: <Widget>[
                    Align(
                      alignment:
                          message.isMine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: onUserTap,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            _senderLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      ),
                    ),
                    Stack(
                      children: <Widget>[
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: bubbleWidth),
                          child: ChatBubble(
                            style: ChatBubbleStyle.content(
                              side:
                                  message.isMine
                                      ? ChatBubbleSide.right
                                      : ChatBubbleSide.left,
                              backgroundColor:
                                  message.isMine
                                      ? Theme.of(
                                        context,
                                      ).colorScheme.primaryContainer
                                      : Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                ChatMessageContentRenderer(
                                  message: message,
                                  attachmentState: attachmentState,
                                  onVoiceOpened: onVoiceOpened,
                                  onAttachmentDownload: onAttachmentDownload,
                                  onAttachmentCancel: onAttachmentCancel,
                                  onAttachmentOpen: onAttachmentOpen,
                                  onAttachmentSaveAs: onAttachmentSaveAs,
                                  imageBytes: imageBytes,
                                  uploadProgress: uploadProgress,
                                  apiBaseUrl: apiBaseUrl,
                                  mediaItems: mediaItems,
                                  mediaInitialIndex: mediaInitialIndex,
                                  onLinkTap: onLinkTap,
                                ),
                              ],
                            ),
                          ),
                        ),
                        ChatMessageDeliveryState(
                          isMine: message.isMine,
                          state: message.state,
                          onRetry: onRetry,
                        ),
                      ],
                    ),
                    if (renderedQuote != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: bubbleWidth),
                          child: ChatQuotePreview(
                            senderName: message.quoteSenderName,
                            content: renderedQuote,
                            onTap: onQuoteTap,
                          ),
                        ),
                      ),
                  ],
                ),
              );
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (selectionMode)
                    SizedBox(
                      width: selectionSlotWidth,
                      child: Center(
                        child: Checkbox(
                          value: selected,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          onChanged: (_) => onTap?.call(),
                        ),
                      ),
                    ),
                  ...(message.isMine
                      ? <Widget>[content, const SizedBox(width: 12), avatar]
                      : <Widget>[avatar, const SizedBox(width: 12), content]),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          if (showPeerRead)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 47, bottom: 3),
                child: Text(
                  '已读',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _time(DateTime? value) =>
      value == null
          ? ''
          : '${value.month}-${value.day} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
