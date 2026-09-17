import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../session/application/active_chat_registry.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/file/file_picker_service.dart';
import '../../../core/services/media/media_service.dart';

import '../../../core/services/media/audio_playback_service.dart';
import '../../../core/services/clipboard_service.dart';
import '../../../core/config/app_environment.dart';
import '../../../core/media/media_preview.dart';
import '../../../core/utils/api_url_resolver.dart';
import '../../../core/widgets/half_page_sheet.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/floating_popover.dart';
import '../../../core/widgets/target_picker/target_picker.dart';
import '../application/chat_controller.dart';
import '../application/ai_stream_change_bus.dart';
import '../data/models/chat_message.dart';
import '../../chat_settings/data/models/chat_member.dart';
import '../../chat_settings/application/chat_settings_controller.dart';
import '../../chat_settings/presentation/member_profile_sheet.dart';
import '../../session/application/session_list_controller.dart';
import '../../session/data/session_change_bus.dart';
import '../../session/presentation/chat_object_avatar.dart';
import '../../auth/application/auth_controller.dart';
import '../../call_center/application/call_center_controller.dart';
import 'message_content/chat_message_content_renderer.dart';
import 'message_content/chat_message_presentation.dart';
import 'message_menu/chat_avatar_menu.dart';
import 'message_menu/chat_message_menu.dart';
import 'widgets/chat_composer.dart';
import 'widgets/chat_input_area.dart';
import 'widgets/chat_message_list.dart';
import 'widgets/chat_message_row.dart';
import 'widgets/chat_selection_bar.dart';
import 'widgets/chat_text_selection_sheet.dart';
import 'widgets/chat_title_bar.dart';
import 'widgets/chat_transfer_sheet.dart';
import 'ai_run_timeline_page.dart';

/// 聊天会话主页面（ChatPage）
///
/// 核心职责：
/// 1. 负责聊天页面的生命周期编排与耗时跟踪监控（`_pageStopwatch`）；
/// 2. 调度 [ChatController] 进行本地离线消息并行读取与远端增量同步；
/// 3. 连接并编排各个解耦的展示子组件：
///    - [ChatTitleBar]：顶部导航与客服转接入口；
///    - [ChatMessageList]：自适应反向消息滚动列表；
///    - [ChatMessageRow]：单条消息气泡行（头像/内容/状态/引用/多选）；
///    - [ChatInputArea] 与 [ChatComposer]：底部输入框、语音录制、附件功能区；
///    - [ChatSelectionBar]：多选批量删除/合并转发控制条；
/// 4. 路由与弹窗交互代理（群设置、消息菜单、转发目标选择、客服转接弹窗）。
class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({
    required this.ownerId,
    required this.sessionUnitId,
    required this.title,
    super.key,
  });

  /// 当前登录用户身份 ID（Owner ID）
  final int ownerId;

  /// 当前会话单元 ID（Session Unit ID）
  final String sessionUnitId;

  /// 页面进入时传入的默认标题（在本地/线上详情加载完成后会自动更新为最新昵称）
  final String title;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage>
    with WidgetsBindingObserver {
  /// 聊天核心业务状态控制器
  late final ChatController controller;

  /// 音频播放服务（语音消息播放）
  late final AudioPlaybackService _audioPlayback;

  /// 前台活跃会话注册表
  late final ActiveChatRegistry _activeChatRegistry;

  /// 底部消息输入框控制器
  final input = TextEditingController();

  /// 消息列表滚动控制器
  final ScrollController _scrollController = ScrollController();

  /// 底部输入组件 GlobalKey（用于外部控制失焦或取消录音）
  final GlobalKey<ChatComposerState> _composerKey =
      GlobalKey<ChatComposerState>();

  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  final Map<int, ChatMessage> _quotedMessageCache = <int, ChatMessage>{};
  final Set<int> _quotedMessageLookups = <int>{};
  final Map<String, bool> _timeVisibility = <String, bool>{};
  final Set<String> _specialFollowedSenders = <String>{};
  List<MediaPreviewItem> _mediaItems = const <MediaPreviewItem>[];
  String _mediaItemsFingerprint = '';
  int _timeVisibilityResetMarker = 0;
  final Stopwatch _pageStopwatch = Stopwatch();

  @override
  void initState() {
    super.initState();
    _pageStopwatch.start();
    debugPrint(
      '[ChatTrace] 🚀 ChatPage.initState | session=${widget.sessionUnitId}',
    );
    WidgetsBinding.instance.addObserver(this);
    _activeChatRegistry = ref.read(activeChatRegistryProvider);
    _activeChatRegistry.enterChat(widget.sessionUnitId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint(
        '[ChatTrace] 🎨 [First Frame Painted] | '
        'elapsed=${_pageStopwatch.elapsedMilliseconds}ms',
      );
    });
    _audioPlayback = ref.read(audioPlaybackServiceProvider);
    controller = ChatController(
      ref.read(messageRepositoryProvider),
      ref.read(sessionRepositoryProvider),
      filePickerService: ref.read(filePickerServiceProvider),
      attachmentTransferService: ref.read(attachmentTransferServiceProvider),
      mediaService: ref.read(mediaServiceProvider),
      audioPlaybackService: _audioPlayback,
      sessionChangeBus: ref.read(sessionChangeBusProvider),
      clipboardService: ref.read(clipboardServiceProvider),
      chatSettingsRepository: ref.read(chatSettingsRepositoryProvider),
      aiStreamChangeBus: ref.read(aiStreamChangeBusProvider),
      signalRGateway: ref.read(signalRGatewayProvider),
      ownerId: widget.ownerId,
      sessionUnitId: widget.sessionUnitId,
      initialTitle: widget.title,
    )..initialize();
  }

  @override
  void dispose() {
    debugPrint(
      '[ChatTrace] 🚪 ChatPage.dispose | '
      'totalSessionDuration=${_pageStopwatch.elapsedMilliseconds}ms',
    );
    WidgetsBinding.instance.removeObserver(this);
    _activeChatRegistry.leaveChat(widget.sessionUnitId);
    unawaited(_audioPlayback.stop());
    controller.dispose();
    input.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(_audioPlayback.stop());
      _composerKey.currentState?.cancelActiveRecording();
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final mediaItems = _mediaItemsFor(controller.messages);
      _pruneMessageKeys(controller.messages);
      return PopScope(
        canPop: !controller.selectionMode,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && controller.selectionMode) {
            controller.cancelSelection();
          }
        },
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          floatingActionButton:
              controller.newMessageCount > 0
                  ? FloatingActionButton.extended(
                    onPressed: () async {
                      if (_scrollController.hasClients) {
                        await _scrollController.animateTo(
                          0,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        );
                      }
                      controller.clearNewMessageCount();
                    },
                    icon: const Icon(Icons.arrow_downward),
                    label: Text('${controller.newMessageCount} 条新消息'),
                  )
                  // Keep the Scaffold FAB slot stable while the count changes.
                  // Replacing a FAB with null during a pointer packet can leave
                  // Flutter's built-in FAB transition without a laid-out child.
                  : const SizedBox.shrink(),
          appBar: ChatTitleBar(
            title: controller.title,
            showTransfer: controller.friend?.isShopkeeperOrWaiter == true,
            selectionMode: controller.selectionMode,
            onCancelSelection: controller.cancelSelection,
            onTransfer: _openTransferSheet,
            onOpenSettings: _openChatSettings,
            onOpenAiRuns: _openAiRunTimeline,
          ),
          body: Column(
            children: <Widget>[
              Expanded(
                child: ChatMessageList(
                  messages: controller.messages,
                  transientItems: controller.aiStreamReplies
                      .map((reply) => _buildAiStreamReply(reply))
                      .toList(growable: false),
                  scrollController: _scrollController,
                  isLoading: controller.isLoading,
                  hasMore: controller.hasMore,
                  error: controller.error,
                  onViewingLatestChanged: controller.setViewingLatest,
                  onLoadMore: controller.loadMore,
                  onTapOutside: _closeInputArea,
                  itemBuilder:
                      (context, message, index) => _buildMessageItem(
                        context,
                        message,
                        index,
                        mediaItems,
                      ),
                ),
              ),
              if (controller.hasActiveAiStream)
                _buildActiveAiStreamStopBar(Theme.of(context)),
              ChatInputArea(
                selectionMode: controller.selectionMode,
                selectionActions: ChatSelectionBar(
                  count: controller.selectedLocalIds.length,
                  onCancel: controller.cancelSelection,
                  onDelete: _deleteSelectedMessages,
                  onMergeForward: _showMergeForwardTargets,
                ),
                composer: ChatComposer(
                  key: _composerKey,
                  controller: controller,
                  input: input,
                  quoteContentBuilder:
                      (quote) => _buildQuotedContent(quote, _mediaItems),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _buildAiStreamReply(AiStreamReply reply) {
    final theme = Theme.of(context);
    final isThinking = reply.status == AiStreamStatus.thinking;
    final text = switch (reply.status) {
      AiStreamStatus.thinking => 'AI 正在思考…',
      AiStreamStatus.failed => reply.error,
      _ => reply.text.isEmpty ? 'AI 正在生成…' : reply.text,
    };
    final showProgress =
        reply.status == AiStreamStatus.thinking ||
        reply.status == AiStreamStatus.streaming;
    final elapsed = _formatAiDuration(
      reply.displayElapsedMilliseconds(DateTime.now()),
    );
    final queue =
        reply.queueMilliseconds > 0
            ? _formatAiDuration(reply.queueMilliseconds)
            : '—';
    return Padding(
      key: ValueKey<String>('ai-stream-${reply.runId}'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ChatObjectAvatar(
            name: controller.peerDisplayName,
            imageUrl: controller.peerAvatarUrl,
            size: 44,
            radius: 22,
            chatObjectId: controller.peerChatObjectId,
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(
                        controller.peerDisplayName,
                        style: theme.textTheme.labelSmall,
                      ),
                      if (showProgress)
                        InkWell(
                          onTap: () => controller.stopAiStream(reply),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(
                                  Icons.stop_circle_outlined,
                                  size: 14,
                                  color: theme.colorScheme.error,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  isThinking ? '停止思考' : '停止生成',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.error,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(text),
                  const SizedBox(height: 6),
                  Text(
                    '排队 $queue · 调用 $elapsed',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (showProgress) ...<Widget>[
                    const SizedBox(height: 8),
                    const SizedBox(
                      height: 2,
                      width: 72,
                      child: LinearProgressIndicator(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveAiStreamStopBar(ThemeData theme) {
    final active = controller.activeAiStreamReply;
    final isThinking = active?.status == AiStreamStatus.thinking;
    final label = isThinking ? 'AI 正在思考…' : 'AI 正在生成…';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 10),
          InkWell(
            onTap: controller.stopAllActiveAiStreams,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.stop_rounded,
                    size: 14,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    isThinking ? '停止思考' : '停止生成',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatAiDuration(int milliseconds) {
    if (milliseconds < 1000) return '${milliseconds}ms';
    if (milliseconds < 60000) {
      return '${(milliseconds / 1000).toStringAsFixed(1)}s';
    }
    final minutes = milliseconds ~/ 60000;
    final seconds = (milliseconds % 60000) ~/ 1000;
    return '$minutes分$seconds秒';
  }

  /// 收起键盘和底部功能面板
  void _closeInputArea() {
    FocusManager.instance.primaryFocus?.unfocus();
    _composerKey.currentState?.closeInputArea();
  }

  /// 跳转至聊天会话设置页面（单聊/群聊成员、置顶、免打扰、清空记录等）
  Future<void> _openChatSettings() async {
    _closeInputArea();
    final cleared = await context.push<bool>(
      '/chat/${Uri.encodeComponent(widget.sessionUnitId)}/settings'
      '?ownerId=${widget.ownerId}',
    );
    if (cleared == true) controller.handleMessagesCleared();
  }

  Future<void> _openAiRunTimeline() => showHalfPageSheet<void>(
    context: context,
    options: const HalfPageSheetOptions(
      heightFactor: .78,
      constraints: BoxConstraints(maxWidth: 720),
      keyboardBehavior: HalfPageSheetKeyboardBehavior.overlay,
      routeSettings: RouteSettings(name: '/chat/ai-run-timeline'),
    ),
    builder: (_) => AiRunTimelinePage(controller: controller),
  );

  /// 构建单条消息 Item（包装了长按菜单浮层与单条消息 Row）
  Widget _buildMessageItem(
    BuildContext context,
    ChatMessage message,
    int index,
    List<MediaPreviewItem> mediaItems,
  ) {
    final older =
        index + 1 < controller.messages.length
            ? controller.messages[index + 1]
            : null;
    final supportsFileRetry = switch (message.messageType) {
      2 || 3 || 4 || 5 => true,
      _ => false,
    };
    final menuController = FloatingPopoverController();
    final menuItems = const ChatMessageMenuBuilder().build(
      ChatMessageMenuContext(
        message: message,
        canRecall:
            message.isMine && message.serverId != null && !message.isRollbacked,
        canRetry: controller.canRetryMessage(message),
        isEarpiece: _audioPlayback.isEarpiece,
        onAction:
            (action, target) =>
                _handleMessageMenuAction(menuController, action, target),
      ),
    );

    final avatarMenuController = FloatingPopoverController();
    final avatarMenuItems = _buildAvatarMenuItems(
      message,
      avatarMenuController,
    );

    final quote = _restoreQuoteMessage(message);
    final row = ChatMessageRow(
      key: _messageKeyFor(message.localId),
      message: message,
      showTime: _showTime(message, older),
      onUserTap: () => _showSenderProfile(message),
      onSessionUnitTap: _showSessionUnitProfile,
      onVoiceOpened: () => controller.markVoiceOpened(message),
      onLinkTap: () => _copyLink(message),
      mediaItems: mediaItems,
      mediaInitialIndex: mediaItems.indexWhere(
        (item) => item.id == message.localId,
      ),
      attachmentState: controller.attachmentState(message.localId),
      onAttachmentDownload:
          () => _runAttachmentAction(
            () => controller.downloadAttachment(message),
            success: '附件已下载',
          ),
      onAttachmentCancel: () => controller.cancelAttachmentDownload(message),
      onAttachmentOpen:
          () => _runAttachmentAction(() => controller.openAttachment(message)),
      onAttachmentSaveAs:
          () => _runAttachmentAction(
            () => controller.saveAttachmentAs(message),
            success: '已打开另存为窗口',
          ),
      onRetry:
          supportsFileRetry && message.state == 'failed'
              ? () => controller.retryFile(message)
              : null,
      imageBytes: controller.imagePreview(message.localId),
      uploadProgress: controller.uploadProgress[message.localId],
      apiBaseUrl: ref.read(appEnvironmentProvider).apiBaseUrl,
      selected: controller.selectedLocalIds.contains(message.localId),
      selectionMode: controller.selectionMode,
      onTap:
          controller.selectionMode
              ? () => controller.toggleSelection(message)
              : null,
      onQuoteTap: () => _scrollToQuoted(message),
      quoteContent:
          quote == null ? null : _buildQuotedContent(quote, mediaItems),
      showUnreadDivider:
          message.serverId != null &&
          controller.initialUnreadDividerMessageId == message.serverId &&
          index > 0,
      showPeerRead:
          message.isMine &&
          message.serverId != null &&
          controller.friend?.peerReadMessageId == message.serverId,
      contentMenuController: menuController,
      contentMenuBuilder:
          menuItems.isEmpty
              ? null
              : (_) => ChatMessageMenu(
                items: menuItems,
                layoutMode: ChatMessageMenuLayoutMode.doubleRow,
              ),
      avatarMenuController: avatarMenuController,
      avatarMenuBuilder:
          avatarMenuItems.isEmpty
              ? null
              : (_) => ChatAvatarMenu(items: avatarMenuItems),
    );
    return KeyedSubtree(key: ValueKey<String>(message.localId), child: row);
  }

  List<ChatAvatarMenuItem> _buildAvatarMenuItems(
    ChatMessage message,
    FloatingPopoverController popoverController,
  ) {
    final senderUnitId = message.senderSessionUnitId ?? message.senderName;
    final isFollowing = _specialFollowedSenders.contains(senderUnitId);

    return [
      ChatAvatarMenuItem(
        id: 'mention',
        label: '@TA',
        icon: Icons.alternate_email,
        onTap: () {
          popoverController.hide();
          _composerKey.currentState?.insertMention(message.senderName);
        },
      ),
      if (isFollowing)
        ChatAvatarMenuItem(
          id: 'unfollow',
          label: '取消关注',
          icon: Icons.star,
          onTap: () {
            popoverController.hide();
            setState(() => _specialFollowedSenders.remove(senderUnitId));
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已取消对「${message.senderName}」的特别关注')),
              );
            }
          },
        )
      else
        ChatAvatarMenuItem(
          id: 'follow',
          label: '特别关注',
          icon: Icons.star_border,
          onTap: () {
            popoverController.hide();
            setState(() => _specialFollowedSenders.add(senderUnitId));
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已将「${message.senderName}」设为特别关注')),
              );
            }
          },
        ),
      ChatAvatarMenuItem(
        id: 'mute',
        label: '禁言',
        icon: Icons.volume_off_outlined,
        onTap: () {
          popoverController.hide();
          _showMuteMemberDialog(message);
        },
      ),
      ChatAvatarMenuItem(
        id: 'profile',
        label: '查看资料',
        icon: Icons.account_circle_outlined,
        onTap: () {
          popoverController.hide();
          _showSenderProfile(message);
        },
      ),
    ];
  }

  void _showMuteMemberDialog(ChatMessage message) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (bottomSheetContext) {
        final options = <String>['10 分钟', '1 小时', '1 天', '7 天', '永久禁言'];
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '对「${message.senderName}」设置禁言',
                  style: Theme.of(bottomSheetContext).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(height: 1),
              for (final opt in options)
                ListTile(
                  title: Text(opt, textAlign: TextAlign.center),
                  onTap: () {
                    Navigator.of(bottomSheetContext).pop();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('已对「${message.senderName}」禁言 $opt'),
                        ),
                      );
                    }
                  },
                ),
              const Divider(height: 1),
              ListTile(
                title: const Text(
                  '取消',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                onTap: () => Navigator.of(bottomSheetContext).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  ChatMessage? _restoreQuoteMessage(ChatMessage owner) {
    if (owner.quoteMessage.isEmpty) return null;
    final serverId = owner.quoteMessageId;
    final canonical =
        controller.messageByServerId(serverId) ?? _quotedMessageCache[serverId];
    if (canonical != null) return canonical;
    final raw = <String, dynamic>{...owner.quoteMessage};
    raw['id'] ??= serverId;
    raw['sessionUnitId'] ??= owner.sessionUnitId;
    try {
      final recovered = ChatMessage.fromJson(
        raw,
        ownerId: owner.ownerId,
        sessionUnitId: owner.sessionUnitId,
      );
      _loadCanonicalQuoteMessage(serverId);
      return recovered;
    } on FormatException {
      return null;
    }
  }

  void _loadCanonicalQuoteMessage(int? serverId) {
    if (serverId == null || !_quotedMessageLookups.add(serverId)) return;
    unawaited(() async {
      final message = await controller.findLocalMessageByServerId(serverId);
      if (message == null || !mounted) return;
      setState(() => _quotedMessageCache[serverId] = message);
    }());
  }

  Widget _buildQuotedContent(
    ChatMessage quote,
    List<MediaPreviewItem> mediaItems,
  ) => ChatMessageContentRenderer(
    message: quote,
    attachmentState: controller.attachmentState(quote.localId),
    onVoiceOpened: () => controller.markVoiceOpened(quote),
    onAttachmentDownload: () => controller.downloadAttachment(quote),
    onAttachmentCancel: () => controller.cancelAttachmentDownload(quote),
    onAttachmentOpen: () => controller.openAttachment(quote),
    onAttachmentSaveAs: () => controller.saveAttachmentAs(quote),
    imageBytes: controller.imagePreview(quote.localId),
    uploadProgress: controller.uploadProgress[quote.localId],
    apiBaseUrl: ref.read(appEnvironmentProvider).apiBaseUrl,
    mediaItems: mediaItems,
    mediaInitialIndex: mediaItems.indexWhere(
      (item) => item.id == quote.localId,
    ),
    onLinkTap: () => _copyLink(quote),
    presentation: ChatMessagePresentation.quote,
  );

  Future<void> _copyLink(ChatMessage message) async {
    if (message.linkUrl.isEmpty) return;
    await controller.copyLink(message);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('链接已复制')));
    }
  }

  GlobalKey _messageKeyFor(String localId) =>
      _messageKeys.putIfAbsent(localId, GlobalKey.new);

  void _pruneMessageKeys(List<ChatMessage> messages) {
    if (_messageKeys.isEmpty) return;
    final liveIds = messages.map((m) => m.localId).toSet();
    _messageKeys.removeWhere((id, _) => !liveIds.contains(id));
  }

  List<MediaPreviewItem> _mediaItemsFor(List<ChatMessage> messages) {
    final fingerprint = messages
        .where((item) => item.messageType == 2 || item.messageType == 4)
        .map(
          (item) => [
            item.localId,
            item.messageType,
            item.mediaUrl,
            item.thumbnailUrl,
            item.videoCoverUrl,
            item.localFilePath,
            controller.imagePreview(item.localId)?.length,
          ].join('|'),
        )
        .join(';');
    if (fingerprint == _mediaItemsFingerprint) return _mediaItems;
    _mediaItemsFingerprint = fingerprint;
    final baseUrl = ref.read(appEnvironmentProvider).apiBaseUrl;
    // 列表是 reverse: true（最新消息在 index 0），媒体画廊需按自然时间正序排列（最旧在 index 0，最新在末尾）
    _mediaItems = messages.reversed
        .where((item) => item.messageType == 2 || item.messageType == 4)
        .map((message) {
          final localFile =
              (message.localFilePath != null &&
                      !kIsWeb &&
                      File(message.localFilePath!).existsSync())
                  ? message.localFilePath
                  : null;
          final sourceUrl =
              (message.mediaUrl != null && message.mediaUrl!.isNotEmpty)
                  ? message.mediaUrl!
                  : (localFile ?? message.localFilePath ?? '');
          final source = resolveApiUrl(sourceUrl, baseUrl);
          final thumbRaw = message.thumbnailUrl ?? message.videoCoverUrl;
          final thumbnail =
              thumbRaw != null ? resolveApiUrl(thumbRaw, baseUrl) : null;
          final fileName =
              message.fileName.isNotEmpty
                  ? message.fileName
                  : '${message.localId}${message.fileSuffix.isNotEmpty ? message.fileSuffix : (message.messageType == 4 ? '.mp4' : '.jpg')}';
          final cachedAttachmentPath =
              controller.attachmentState(message.localId).localPath;
          final validCachedPath =
              (cachedAttachmentPath != null &&
                      !kIsWeb &&
                      File(cachedAttachmentPath).existsSync())
                  ? cachedAttachmentPath
                  : localFile;
          return MediaPreviewItem(
            id: message.localId,
            messageId: message.localId,
            type:
                message.messageType == 2
                    ? MediaPreviewType.image
                    : MediaPreviewType.video,
            source: source,
            thumbnail: thumbnail,
            fileName: fileName,
            localPath: validCachedPath,
            createdAt: message.createdAt,
            userId: message.ownerId.toString(),
            chatTarget: message.sessionUnitId,
            bytes: controller.imagePreview(message.localId),
            heroTag: buildMediaHeroTag(
              messageId: message.localId,
              mediaId: message.localId,
            ),
          );
        })
        .where((item) => item.source.isNotEmpty || item.bytes != null)
        .toList(growable: false);
    return _mediaItems;
  }

  Future<void> _runAttachmentAction(
    Future<void> Function() action, {
    String? success,
  }) async {
    try {
      await action();
      if (success != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('附件操作失败：$error')));
      }
    }
  }

  Future<void> _handleMessageMenuAction(
    FloatingPopoverController menu,
    String action,
    ChatMessage message,
  ) async {
    menu.hide();
    switch (action) {
      case 'copy':
        await controller.copyMessage(message);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('已复制消息')));
        }
        return;
      case 'quote':
      case 'reply':
        if (message.serverId == null) return;
        controller.quoteMessage(message);
        _composerKey.currentState?.focusText();
        return;
      case 'retry':
        await _runMessageAction(
          () => controller.retryMessage(message),
          success: '已重新发送消息',
        );
        return;
      case 'delete':
        await _runMessageAction(
          message.serverId == null
              ? () => controller.deleteMessages(<String>[message.localId])
              : () => controller.deleteRemote(message),
          success: '消息已删除',
        );
        return;
      case 'recall':
        await _runMessageAction(
          () => controller.rollbackMessage(message),
          success: '消息已撤回',
        );
        return;
      case 'forward':
        await _showForwardTargets(message);
        return;
      case 'select':
        controller.beginSelection(message);
        return;
      case 'selectText':
        if (message.text.isNotEmpty) {
          showChatTextSelectionSheet(context, text: message.text);
        }
        return;
      case 'earpiece':
        await _audioPlayback.setEarpiece(true, manual: true);
        if (mounted) {
          showToast('已切换为听筒播放，请用耳朵靠近听筒位置');
        }
        return;
      case 'speaker':
        await _audioPlayback.setEarpiece(false, manual: true);
        if (mounted) {
          showToast('已切换为扬声器播放');
        }
        return;
      case 'playVideo':
      case 'play':
        _playVideoInFloatingWindow(message);
        return;
    }
  }

  /// 在画中画悬浮小窗口中播放视频消息
  void _playVideoInFloatingWindow(ChatMessage message) {
    final mediaItems = _mediaItemsFor(controller.messages);
    final targetIndex = mediaItems.indexWhere((it) => it.id == message.localId);
    final baseUrl = ref.read(appEnvironmentProvider).apiBaseUrl;
    final source = resolveApiUrl(
      message.mediaUrl ?? message.localFilePath ?? '',
      baseUrl,
    );
    if (source.isEmpty) return;
    final item =
        targetIndex >= 0
            ? mediaItems[targetIndex]
            : MediaPreviewItem(
              id: message.localId,
              messageId: message.localId,
              type: MediaPreviewType.video,
              source: source,
              userId: message.ownerId.toString(),
              chatTarget: message.sessionUnitId,
              createdAt: message.createdAt,
              heroTag: buildMediaHeroTag(
                messageId: message.localId,
                mediaId: message.localId,
              ),
            );
    openFloatingVideoWindow(
      context,
      item: item,
      items: mediaItems,
      initialIndex: targetIndex < 0 ? 0 : targetIndex,
    );
  }

  bool _showTime(ChatMessage current, ChatMessage? older) {
    if (_timeVisibilityResetMarker != controller.timeVisibilityResetMarker) {
      _timeVisibilityResetMarker = controller.timeVisibilityResetMarker;
      _timeVisibility.clear();
    }
    return _timeVisibility.putIfAbsent(current.localId, () {
      if (current.createdAt == null || older?.createdAt == null) {
        return older == null;
      }
      return current.createdAt!.difference(older!.createdAt!).abs() >
          const Duration(minutes: 5);
    });
  }

  Future<void> _showSenderProfile(ChatMessage message) {
    final sender = <String, dynamic>{...message.senderSessionUnit};
    sender.putIfAbsent(
      'id',
      () => message.senderSessionUnitId ?? message.sessionUnitId,
    );
    if (sender['owner'] == null) {
      sender['owner'] = <String, dynamic>{
        'displayName': message.senderName,
        if (message.senderAvatarUrl != null)
          'thumbnail': message.senderAvatarUrl,
      };
    }
    return showMemberProfileSheet(context, ChatMember.fromJson(sender));
  }

  Future<void> _showSessionUnitProfile(
    String sessionUnitId,
    String displayName,
  ) {
    return showMemberProfileSheet(
      context,
      ChatMember.fromJson(<String, dynamic>{
        'id': sessionUnitId,
        'displayName': displayName,
        'owner': <String, dynamic>{'displayName': displayName},
      }),
    );
  }

  Future<void> _openTransferSheet() async {
    final friend = controller.friend;
    final shopKeeperId = friend?.transferShopKeeperId;
    if (friend == null || shopKeeperId == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('客服身份信息尚未加载完成，请稍后重试。')));
      }
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final transfer = CallCenterController(
      repository: ref.read(callCenterRepositoryProvider),
      shopKeeperId: shopKeeperId,
      sourceOwnerId: friend.ownerId,
      sessionUnitId: widget.sessionUnitId,
    )..initialize();
    final transferred = await showHalfPageSheet<bool>(
      context: context,
      options: const HalfPageSheetOptions(heightFactor: .62),
      builder: (_) => ChatTransferSheet(controller: transfer),
    );
    transfer.dispose();
    if (transferred == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('转接成功')));
    }
  }

  Future<void> _deleteSelectedMessages() =>
      _runMessageAction(controller.deleteSelectedMessages, success: '已删除所选消息');

  Future<void> _runMessageAction(
    Future<void> Function() action, {
    required String success,
  }) async {
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('操作失败：$error')));
      }
    }
  }

  Future<void> _showForwardTargets(ChatMessage message) async {
    final targets = await controller.loadForwardTargets();
    if (!mounted) return;
    if (targets.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有可转发的会话')));
      return;
    }
    final selectedSessions = await TargetPicker.pickSessionUnits(
      context: context,
      sessions: targets,
      title: '选择转发目标',
      subtitle: '逐条转发（支持多选，最多 9 个）',
      multiple: true,
      maxCount: 9,
      minCount: 1,
    );
    if (selectedSessions == null || selectedSessions.isEmpty) return;

    for (final target in selectedSessions) {
      await _runMessageAction(
        () => controller.forwardMessage(message, target.id),
        success: '已转发至 ${target.title}',
      );
    }
  }

  Future<void> _showMergeForwardTargets() async {
    final count = controller.selectedLocalIds.length;
    if (count == 0) return;
    final targets = await controller.loadForwardTargets();
    if (!mounted) return;
    if (targets.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有可转发的会话')));
      return;
    }
    final selectedSessions = await TargetPicker.pickSessionUnits(
      context: context,
      sessions: targets,
      title: '合并转发',
      subtitle: '将 $count 条消息作为一张聊天记录发送',
      multiple: false,
      showConfirmButton: false,
    );
    if (selectedSessions == null || selectedSessions.isEmpty) return;

    final target = selectedSessions.first;
    await _runMessageAction(
      () => controller.forwardSelectedAsHistory(target.id),
      success: '已合并转发 $count 条消息至 ${target.title}',
    );
  }

  Future<void> _scrollToQuoted(ChatMessage message) async {
    final id = message.quoteMessageId;
    if (id == null) return;
    for (var attempt = 0; attempt < 10; attempt++) {
      final index = controller.messages.indexWhere(
        (item) => item.serverId == id,
      );
      if (index >= 0) {
        final target = controller.messages[index];
        var targetContext = _messageKeys[target.localId]?.currentContext;
        if (targetContext == null && _scrollController.hasClients) {
          // The list only builds visible children. This estimate merely brings
          // the target into the build range; the final placement below always
          // uses the rendered child and therefore does not assume a fixed row
          // height.
          final estimate = (index * 92.0).clamp(
            0.0,
            _scrollController.position.maxScrollExtent,
          );
          _scrollController.jumpTo(estimate);
          await WidgetsBinding.instance.endOfFrame;
          if (!mounted) return;
          targetContext = _messageKeys[target.localId]?.currentContext;
        }
        if (targetContext != null && targetContext.mounted) {
          await Scrollable.ensureVisible(
            targetContext,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            alignment: .35,
          );
          return;
        }
      }
      if (!controller.hasMore) break;
      await controller.loadMore();
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('引用消息已不在可加载的历史范围内')));
    }
  }
}
