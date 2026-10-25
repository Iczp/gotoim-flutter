import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/media/media_preview.dart';
import '../../../../core/services/file/attachment_transfer_service.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/utils/message_text_formatter.dart';
import '../../../../core/utils/message_time_formatter.dart';
import '../../../../core/widgets/floating_popover.dart';
import '../../../session/presentation/chat_object_avatar.dart';
import '../../data/models/chat_message.dart';
import '../message_content/chat_message_content_renderer.dart';
import 'chat_quote_preview.dart';

/// 单条消息气泡行组件（ChatMessageRow）
class ChatMessageRow extends StatelessWidget {
  const ChatMessageRow({
    required this.message,
    required this.showTime,
    required this.onUserTap,
    this.onUserLongPress,
    this.onSessionUnitTap,
    this.onChatObjectTap,
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
    this.highlighted = false,
    required this.selectionMode,
    required this.onQuoteTap,
    this.quoteContent,
    required this.showUnreadDivider,
    required this.showPeerRead,
    this.contentMenuBuilder,
    this.contentMenuController,
    this.contentMenuOffset = const Offset(0, 6),
    this.onSecondaryTapDown,
    this.avatarMenuBuilder,
    this.avatarMenuController,
    this.avatarMenuOffset = const Offset(8, 0),
    this.onTap,
    this.onAvatarHover,
    this.onAvatarLeave,
    this.showAvatar = true,
    this.showMyAvatar,
    this.showPeerAvatar,
    this.showArticleAvatar,
    this.myAvatarUrl,
    this.peerAvatarUrl,
    this.peerDisplayName,
    this.peerChatObjectId,
    this.myChatObjectId,
    super.key,
  });

  /// 当前消息数据模型
  final ChatMessage message;

  /// 是否显示时间分割线
  final bool showTime;

  /// 是否显示发送人头像（全局开关，默认为 true）
  final bool showAvatar;

  /// 是否显示自己发送消息的头像（若未设置则跟随 showAvatar，公众号场景下默认配置为 true）
  final bool? showMyAvatar;

  /// 是否显示对方发送消息的头像（若未设置则跟随 showAvatar）
  final bool? showPeerAvatar;

  /// 是否显示推送文章消息的头像（默认 false）
  final bool? showArticleAvatar;

  /// 当前登录用户的头像 URL（确保本地发送中的消息即时渲染头像）
  final String? myAvatarUrl;
  final String? peerAvatarUrl;
  final String? peerDisplayName;
  final int? peerChatObjectId;

  /// 当前登录用户的 ChatObjectId
  final int? myChatObjectId;

  /// 点击发送人头像/昵称回调（打开成员资料卡）
  final VoidCallback onUserTap;

  /// 长按发送人头像回调（打开头像菜单）
  final VoidCallback? onUserLongPress;

  /// 点击系统消息中用户链接的回调
  final void Function(String sessionUnitId, String name)? onSessionUnitTap;

  /// 点击系统消息中对象链接的回调
  final void Function(String chatObjectId, String name)? onChatObjectTap;

  /// 消息气泡内容菜单构建器（长按仅在消息气泡内容上生效）
  final WidgetBuilder? contentMenuBuilder;

  /// 消息气泡内容菜单控制器
  final FloatingPopoverController? contentMenuController;

  /// 消息气泡内容菜单偏移量
  final Offset contentMenuOffset;

  /// 桌面端鼠标右键消息气泡回调 (Secondary Tap Down)
  final void Function(TapDownDetails details, ChatMessage message)? onSecondaryTapDown;

  /// 头像上下文菜单构建器
  final WidgetBuilder? avatarMenuBuilder;

  /// 头像上下文菜单控制器
  final FloatingPopoverController? avatarMenuController;

  /// 头像上下文菜单偏移量
  final Offset avatarMenuOffset;

  /// 桌面端头像鼠标移入回调
  final void Function(Rect rect)? onAvatarHover;

  /// 桌面端头像鼠标移出回调
  final VoidCallback? onAvatarLeave;

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

  /// A short-lived target state shown after jumping from a quote preview.
  final bool highlighted;

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
    var name = message.senderName;
    if ((name == '未知用户' || name.isEmpty) &&
        !message.isMine &&
        peerDisplayName != null &&
        peerDisplayName!.isNotEmpty) {
      name = peerDisplayName!;
    }
    if (!kDebugMode) return name;
    final messageId = message.serverId?.toString() ?? message.localId;
    return '$name · $messageId';
  }

  /// 综合全局配置、自身/对方维度以及文章类型，计算当前消息是否显示头像
  bool get effectiveShowAvatar {
    if (message.messageType == 11) {
      return showArticleAvatar ?? false;
    }
    if (message.isMine) {
      return showMyAvatar ?? showAvatar;
    }
    return showPeerAvatar ?? showAvatar;
  }

  @override
  Widget build(BuildContext context) {
    final renderedQuote = quoteContent;
    if (message.messageType == 1) {
      return _buildSystemMessage(context);
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        color:
            selected
                ? Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: .42)
                : highlighted
                ? Theme.of(
                  context,
                ).colorScheme.tertiaryContainer.withValues(alpha: .52)
                : Colors.transparent,
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
                final avatarSize = context.appTokens.chatMessageMinHeight;
                final avatarSlotWidth = avatarSize;
                const contentPadding = 12.0;
                final selectionWidth = selectionMode ? selectionSlotWidth : 0.0;
                final availableWidth = constraints.maxWidth - selectionWidth;

                final contentMaxWidth = (availableWidth -
                        (effectiveShowAvatar
                            ? avatarSlotWidth + contentPadding
                            : 0.0))
                    .clamp(0.0, double.infinity);

                // 响应式拟定消息气泡的最大宽度：
                // 1. 移动端窄屏（< 600px）：有头像时利用率 78%；无头像（如公众号或大卡片模式）时留出 24px 边距，上限 480px；
                // 2. 平板与桌面宽屏（>= 600px）：限制在 68% 且设定上限 620px，保证舒适阅读视线，防止单行文字过长。
                final double bubbleWidth;
                if (constraints.maxWidth < 600) {
                  bubbleWidth =
                      effectiveShowAvatar
                          ? contentMaxWidth * 0.78
                          : (contentMaxWidth - 24.0).clamp(0.0, 480.0);
                } else {
                  bubbleWidth = (contentMaxWidth * 0.68).clamp(360.0, 620.0);
                }

                Widget? avatarWidget;
                if (effectiveShowAvatar) {
                  final avatarUrl =
                      message.isMine
                          ? (message.senderAvatarUrl ?? myAvatarUrl)
                          : (message.senderAvatarUrl ?? peerAvatarUrl);
                  final avatarName =
                      message.isMine
                          ? (message.senderName != '未知用户' &&
                                  message.senderName.isNotEmpty
                              ? message.senderName
                              : '我')
                          : (message.senderName != '未知用户' &&
                                  message.senderName.isNotEmpty
                              ? message.senderName
                              : (peerDisplayName?.isNotEmpty == true
                                  ? peerDisplayName!
                                  : '未知用户'));
                  final avatarObjectId =
                      message.isMine
                          ? (message.senderChatObjectId ?? myChatObjectId)
                          : (message.senderChatObjectId ?? peerChatObjectId);
                  Widget av = ChatObjectAvatar(
                    name: avatarName,
                    imageUrl: avatarUrl,
                    size: avatarSize,
                    radius: avatarSize / 2,
                    chatObjectId: avatarObjectId,
                  );
                  av = GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onUserTap,
                    onLongPress:
                        onUserLongPress ??
                        () {
                          avatarMenuController?.show();
                        },
                    child: av,
                  );
                  if (avatarMenuBuilder != null) {
                    av = FloatingPopover(
                      controller: avatarMenuController,
                      contentBuilder: avatarMenuBuilder!,
                      placement: FloatingPlacement.avatar,
                      offset: avatarMenuOffset,
                      vibrateCount: 1,
                      child: av,
                    );
                  }
                  final avatarKey = GlobalKey();
                  av = KeyedSubtree(
                    key: avatarKey,
                    child: av,
                  );
                  if (onAvatarHover != null) {
                    av = MouseRegion(
                      onEnter: (_) {
                        final renderBox =
                            avatarKey.currentContext?.findRenderObject()
                                as RenderBox?;
                        if (renderBox != null && renderBox.hasSize) {
                          final offset = renderBox.localToGlobal(Offset.zero);
                          final rect = offset & renderBox.size;
                          onAvatarHover!(rect);
                        }
                      },
                      onExit: (_) {
                        onAvatarLeave?.call();
                      },
                      child: av,
                    );
                  }
                  avatarWidget = av;
                }

                Widget messageContentWidget = ChatMessageContentRenderer(
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
                  onRetry: onRetry,
                  maxWidth: bubbleWidth,
                );

                if (contentMenuBuilder != null) {
                  messageContentWidget = FloatingPopover(
                    controller: contentMenuController,
                    contentBuilder: contentMenuBuilder!,
                    placement: FloatingPlacement.auto,
                    offset: contentMenuOffset,
                    onSecondaryTap: onSecondaryTapDown != null ? () {} : null,
                    child: messageContentWidget,
                  );
                }

                if (onSecondaryTapDown != null) {
                  messageContentWidget = GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onSecondaryTapDown: (details) =>
                        onSecondaryTapDown!(details, message),
                    child: messageContentWidget,
                  );
                }

                final messageBody = Expanded(
                  child: Column(
                    crossAxisAlignment:
                        message.isMine
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                    children: <Widget>[
                      // 发送人名称 (各自加 padding: 12)
                      if (effectiveShowAvatar &&
                          !message.isMine &&
                          _senderLabel.isNotEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: contentPadding,
                            ).copyWith(bottom: 4),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: onUserTap,
                              child: Text(
                                _senderLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ),
                          ),
                        ),
                      // 各种消息（自个约束，不加 padding，气泡尾巴宽度 12）
                      Align(
                        alignment:
                            message.isMine
                                ? Alignment.centerRight
                                : (effectiveShowAvatar
                                    ? Alignment.centerLeft
                                    : Alignment.center),
                        child: messageContentWidget,
                      ),
                      // 引用消息 (各自加 padding: 12)
                      if (renderedQuote != null)
                        Padding(
                          padding: const EdgeInsets.only(
                            left: contentPadding,
                            right: contentPadding,
                            top: 6,
                          ),
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
                    // - 复选框（编辑模式下才显示）
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
                    // - 消息（占满）
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children:
                            message.isMine
                                ? <Widget>[
                                  // 消息内容（占满）
                                  messageBody,
                                  if (effectiveShowAvatar &&
                                      avatarWidget != null) ...<Widget>[
                                    const SizedBox(width: contentPadding),
                                    avatarWidget,
                                  ],
                                ]
                                : <Widget>[
                                  if (effectiveShowAvatar &&
                                      avatarWidget != null) ...<Widget>[
                                    avatarWidget,
                                    const SizedBox(width: contentPadding),
                                  ],
                                  // 消息内容（占满）
                                  messageBody,
                                ],
                      ),
                    ),
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
      ),
    );
  }

  Widget _buildSystemMessage(BuildContext context) {
    final rawText = message.text.isEmpty ? '[系统消息]' : message.text;
    final theme = Theme.of(context);
    final textStyle =
        theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
          fontSize: 12,
          height: 1.4,
        ) ??
        const TextStyle(fontSize: 12, color: Colors.grey);

    final linkStyle = textStyle.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w600,
    );

    final spans = parseMessageTagsToSpans(
      rawText,
      textStyle: textStyle,
      linkStyle: linkStyle,
      onSessionUnitTap: onSessionUnitTap,
      onChatObjectTap: onChatObjectTap,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.5,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text.rich(
            TextSpan(children: spans),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  String _time(DateTime? value) => formatChatMessageTime(value);
}
