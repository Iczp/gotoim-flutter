import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/file/file_picker_service.dart';
import '../../../core/services/file/attachment_transfer_service.dart';
import '../../../core/services/media/media_service.dart';
import '../../../core/services/media/audio_playback_service.dart';
import '../../../core/services/clipboard_service.dart';
import '../../../core/config/app_environment.dart';
import '../../../core/media/media_preview.dart';
import '../../../core/utils/api_url_resolver.dart';
import '../../../core/widgets/half_page_sheet.dart';
import '../../../core/widgets/chat_bubble.dart';
import '../../../core/widgets/floating_popover.dart';
import '../application/chat_controller.dart';
import '../data/models/chat_message.dart';
import '../../chat_settings/data/models/chat_member.dart';
import '../../chat_settings/application/chat_settings_controller.dart';
import '../../chat_settings/presentation/member_profile_sheet.dart';
import '../../session/application/session_list_controller.dart';
import '../../session/data/session_change_bus.dart';
import '../../session/presentation/chat_object_avatar.dart';
import '../../call_center/application/call_center_controller.dart';
import '../../call_center/data/models/transfer_target.dart';
import 'message_content/chat_message_content_renderer.dart';
import 'message_content/chat_message_presentation.dart';
import 'message_menu/chat_message_menu.dart';
import 'widgets/chat_input_area.dart';
import 'widgets/chat_message_list.dart';
import 'widgets/chat_message_delivery_state.dart';
import 'widgets/chat_quote_preview.dart';
import 'widgets/chat_selection_bar.dart';
import 'widgets/chat_title_bar.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({
    required this.ownerId,
    required this.sessionUnitId,
    required this.title,
    super.key,
  });
  final int ownerId;
  final String sessionUnitId;
  final String title;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage>
    with WidgetsBindingObserver {
  late final ChatController controller;
  late final AudioPlaybackService _audioPlayback;
  final input = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<_ComposerState> _composerKey = GlobalKey<_ComposerState>();
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  final Map<int, ChatMessage> _quotedMessageCache = <int, ChatMessage>{};
  final Set<int> _quotedMessageLookups = <int>{};
  final Map<String, bool> _timeVisibility = <String, bool>{};
  List<MediaPreviewItem> _mediaItems = const <MediaPreviewItem>[];
  String _mediaItemsFingerprint = '';
  int _timeVisibilityResetMarker = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      ownerId: widget.ownerId,
      sessionUnitId: widget.sessionUnitId,
      initialTitle: widget.title,
    )..initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
      return Scaffold(
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
          onTransfer: _openTransferSheet,
          onOpenSettings: _openChatSettings,
        ),
        body: Column(
          children: <Widget>[
            Expanded(
              child: ChatMessageList(
                messages: controller.messages,
                scrollController: _scrollController,
                isLoading: controller.isLoading,
                hasMore: controller.hasMore,
                error: controller.error,
                onViewingLatestChanged: controller.setViewingLatest,
                onLoadMore: controller.loadMore,
                onTapOutside: _closeInputArea,
                itemBuilder:
                    (context, message, index) =>
                        _buildMessageItem(context, message, index, mediaItems),
              ),
            ),
            ChatInputArea(
              selectionMode: controller.selectionMode,
              selectionActions: ChatSelectionBar(
                count: controller.selectedLocalIds.length,
                onCancel: controller.cancelSelection,
                onDelete: _deleteSelectedMessages,
                onMergeForward: _showMergeForwardTargets,
              ),
              composer: SafeArea(
                top: false,
                child: _Composer(
                  key: _composerKey,
                  controller: controller,
                  input: input,
                  quoteContentBuilder:
                      (quote) => _buildQuotedContent(quote, _mediaItems),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  void _closeInputArea() {
    FocusManager.instance.primaryFocus?.unfocus();
    _composerKey.currentState?.closeInputArea();
  }

  Future<void> _openChatSettings() async {
    _closeInputArea();
    final cleared = await context.push<bool>(
      '/chat/${Uri.encodeComponent(widget.sessionUnitId)}/settings'
      '?ownerId=${widget.ownerId}',
    );
    if (cleared == true) controller.handleMessagesCleared();
  }

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
        onAction:
            (action, target) =>
                _handleMessageMenuAction(menuController, action, target),
      ),
    );
    final quote = _restoreQuoteMessage(message);
    final row = _MessageRow(
      key: _messageKeyFor(message.localId),
      message: message,
      showTime: _showTime(message, older),
      onUserTap: () => _showSenderProfile(message),
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
    );
    return KeyedSubtree(
      key: ValueKey<String>(message.localId),
      child:
          menuItems.isEmpty
              ? row
              : FloatingPopover(
                controller: menuController,
                contentBuilder: (_) => ChatMessageMenu(items: menuItems),
                child: row,
              ),
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

  List<MediaPreviewItem> _mediaItemsFor(List<ChatMessage> messages) {
    final fingerprint = messages
        .where((item) => item.messageType == 2 || item.messageType == 4)
        .map(
          (item) => [
            item.localId,
            item.messageType,
            item.mediaUrl,
            item.localFilePath,
            controller.imagePreview(item.localId)?.length,
          ].join('|'),
        )
        .join(';');
    if (fingerprint == _mediaItemsFingerprint) return _mediaItems;
    _mediaItemsFingerprint = fingerprint;
    final baseUrl = ref.read(appEnvironmentProvider).apiBaseUrl;
    _mediaItems = messages
        .where((item) => item.messageType == 2 || item.messageType == 4)
        .map((message) {
          final source = resolveApiUrl(
            message.mediaUrl ?? message.localFilePath ?? '',
            baseUrl,
          );
          return MediaPreviewItem(
            id: message.localId,
            messageId: message.localId,
            type:
                message.messageType == 2
                    ? MediaPreviewType.image
                    : MediaPreviewType.video,
            source: source,
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
    }
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
      builder: (_) => _TransferSheet(controller: transfer),
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
    await showHalfPageSheet<void>(
      context: context,
      options: const HalfPageSheetOptions(heightFactor: .62),
      builder:
          (sheetContext) => SafeArea(
            child: Column(
              children: <Widget>[
                const ListTile(title: Text('选择转发会话'), subtitle: Text('逐条转发')),
                Expanded(
                  child:
                      targets.isEmpty
                          ? const Center(child: Text('没有可转发的会话'))
                          : ListView.builder(
                            itemCount: targets.length,
                            itemBuilder: (_, index) {
                              final target = targets[index];
                              return ListTile(
                                leading: ChatObjectAvatar(
                                  name: target.title,
                                  imageUrl: null,
                                  radius: 18,
                                ),
                                title: Text(target.title),
                                subtitle: Text(
                                  target.preview,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () async {
                                  Navigator.pop(sheetContext);
                                  await _runMessageAction(
                                    () => controller.forwardMessage(
                                      message,
                                      target.id,
                                    ),
                                    success: '消息已转发',
                                  );
                                },
                              );
                            },
                          ),
                ),
              ],
            ),
          ),
    );
  }

  Future<void> _showMergeForwardTargets() async {
    final count = controller.selectedLocalIds.length;
    if (count == 0) return;
    final targets = await controller.loadForwardTargets();
    if (!mounted) return;
    await showHalfPageSheet<void>(
      context: context,
      options: const HalfPageSheetOptions(heightFactor: .62),
      builder:
          (sheetContext) => SafeArea(
            child: Column(
              children: <Widget>[
                ListTile(
                  title: const Text('合并转发'),
                  subtitle: Text('将 $count 条消息作为一张聊天记录发送'),
                ),
                Expanded(
                  child:
                      targets.isEmpty
                          ? const Center(child: Text('没有可转发的会话'))
                          : ListView.builder(
                            itemCount: targets.length,
                            itemBuilder: (_, index) {
                              final target = targets[index];
                              return ListTile(
                                leading: ChatObjectAvatar(
                                  name: target.title,
                                  imageUrl: null,
                                  radius: 18,
                                ),
                                title: Text(target.title),
                                onTap: () async {
                                  Navigator.pop(sheetContext);
                                  await _runMessageAction(
                                    () => controller.forwardSelectedAsHistory(
                                      target.id,
                                    ),
                                    success: '已合并转发 $count 条消息',
                                  );
                                },
                              );
                            },
                          ),
                ),
              ],
            ),
          ),
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

class _MessageRow extends StatelessWidget {
  const _MessageRow({
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
  final ChatMessage message;
  final bool showTime;
  final VoidCallback onUserTap;
  final Future<void> Function() onVoiceOpened;
  final Future<void> Function() onLinkTap;
  final List<MediaPreviewItem> mediaItems;
  final int mediaInitialIndex;
  final AttachmentTransferState attachmentState;
  final Future<void> Function() onAttachmentDownload;
  final Future<void> Function() onAttachmentCancel;
  final Future<void> Function() onAttachmentOpen;
  final Future<void> Function() onAttachmentSaveAs;
  final VoidCallback? onRetry;
  final Uint8List? imageBytes;
  final double? uploadProgress;
  final String apiBaseUrl;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onQuoteTap;
  final Widget? quoteContent;
  final bool showUnreadDivider;
  final bool showPeerRead;
  final VoidCallback? onTap;

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
        child: Center(child: Text('${message.senderName} 撤回了一条消息')),
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
              // Keep the bubble constraint stable across selection-mode changes:
              // 36px is reserved in the maximum width for a checkbox that is
              // only inserted while selecting, and 48px is reserved for avatar
              // plus its gap. This prevents text wrapping and row-height jumps.
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
                            message.senderName,
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
                padding: EdgeInsets.only(right: 47, bottom: 3),
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

class _MentionBottomSheet extends StatefulWidget {
  const _MentionBottomSheet({required this.controller, required this.input});
  final ChatController controller;
  final TextEditingController input;

  @override
  State<_MentionBottomSheet> createState() => _MentionBottomSheetState();
}

class _MentionBottomSheetState extends State<_MentionBottomSheet> {
  late final TextEditingController _search = TextEditingController(
    text: widget.controller.mentionKeyword,
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(ChatMember member) {
    final value = widget.controller.toggleMention(widget.input.text, member);
    widget.input.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    setState(() {});
  }

  void _finish() {
    widget.controller.dismissMention();
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder:
        (context, _) => _MentionPanel(
          members: widget.controller.mentionMembers,
          loading: widget.controller.mentionLoading,
          hasMore: widget.controller.mentionHasMore,
          onLoadMore: widget.controller.loadMoreMentions,
          isSelected:
              (member) => widget.controller.isMemberMentioned(
                member,
                widget.input.text,
              ),
          onSelected: _toggle,
          search: _search,
          onSearchChanged: widget.controller.updateMentionKeyword,
          onComplete: _finish,
          onDismiss: () => Navigator.pop(context, false),
        ),
  );
}

class _MentionPanel extends StatelessWidget {
  const _MentionPanel({
    required this.members,
    required this.loading,
    required this.hasMore,
    required this.onLoadMore,
    required this.isSelected,
    required this.onSelected,
    required this.search,
    required this.onSearchChanged,
    required this.onComplete,
    required this.onDismiss,
  });

  final List<ChatMember> members;
  final bool loading;
  final bool hasMore;
  final Future<void> Function() onLoadMore;
  final bool Function(ChatMember member) isSelected;
  final ValueChanged<ChatMember> onSelected;
  final TextEditingController search;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onComplete;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Material(
    elevation: 10,
    color: Theme.of(context).colorScheme.surface,
    child: SizedBox.expand(
      child: Column(
        children: <Widget>[
          ListTile(
            title: const Text('提及成员'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextButton(onPressed: onComplete, child: const Text('完成')),
                IconButton(
                  tooltip: '关闭',
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: search,
              autofocus: true,
              onChanged: onSearchChanged,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜索成员',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.metrics.extentAfter < 100 &&
                    hasMore &&
                    !loading) {
                  onLoadMore();
                }
                return false;
              },
              child:
                  members.isEmpty && loading
                      ? const SizedBox(
                        height: 72,
                        child: Center(child: CircularProgressIndicator()),
                      )
                      : members.isEmpty
                      ? const SizedBox(
                        height: 72,
                        child: Center(child: Text('未找到可提及的成员')),
                      )
                      : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount:
                            members.length + (loading || hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == members.length) {
                            return SizedBox(
                              height: 42,
                              child: Center(
                                child:
                                    loading
                                        ? const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                        : const Text('上拉加载更多成员'),
                              ),
                            );
                          }
                          final member = members[index];
                          final selected = isSelected(member);
                          return ListTile(
                            dense: true,
                            leading: ChatObjectAvatar(
                              name: member.name,
                              imageUrl:
                                  member.avatarUrl.isEmpty
                                      ? null
                                      : member.avatarUrl,
                              radius: 17,
                            ),
                            title: Text(
                              member.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Checkbox(
                              value: selected,
                              onChanged: (_) => onSelected(member),
                            ),
                            onTap: () => onSelected(member),
                          );
                        },
                      ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.input,
    required this.quoteContentBuilder,
    super.key,
  });
  final ChatController controller;
  final TextEditingController input;
  final Widget Function(ChatMessage quote) quoteContentBuilder;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> with WidgetsBindingObserver {
  final FocusNode _focusNode = FocusNode();
  final PageController _pageController = PageController();
  bool _showFunctions = false;
  bool _voiceMode = false;
  bool _startingRecording = false;
  bool _recording = false;
  bool _cancelRecording = false;
  bool _pointerReleased = false;
  bool _finishingRecording = false;
  StreamSubscription<double>? _levelSubscription;
  Timer? _durationTimer;
  OverlayEntry? _recordingOverlay;
  final Stopwatch _recordingWatch = Stopwatch();
  Duration _recordingDuration = Duration.zero;
  // The waveform is a sliding window: samples are removed from the front and
  // appended at the end, so this must be a growable list.
  final List<double> _levelPercentages = List<double>.filled(
    24,
    0,
    growable: true,
  );
  int _amplitudeSampleCount = 0;
  int _page = 0;
  bool _mentionSheetOpen = false;

  static const _functions = <_ChatFunction>[
    _ChatFunction('相册', Icons.photo_outlined),
    _ChatFunction('拍摄', Icons.camera_alt_outlined),
    _ChatFunction('视频', Icons.videocam_outlined),
    _ChatFunction('文件', Icons.insert_drive_file_outlined, enabled: true),
    _ChatFunction('位置', Icons.location_on_outlined),
    _ChatFunction('名片', Icons.contact_page_outlined),
    _ChatFunction('语音通话', Icons.call_outlined),
    _ChatFunction('视频通话', Icons.video_call_outlined),
    _ChatFunction('红包', Icons.wallet_giftcard_outlined),
    _ChatFunction('收藏', Icons.bookmark_border_rounded),
  ];

  // UI-only visual calibration. The media service provides a 0...100 input
  // level; this mapping removes the idle noise floor before drawing.
  static const _voiceWaveVisualConfig = _VoiceWaveVisualConfig(
    inputFloorPercent: 30,
    inputPeakPercent: 80,
  );
  static const _fallbackFunctionTrayHeight = 238.0;
  double _keyboardTrayHeight = _fallbackFunctionTrayHeight;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _captureKeyboardHeight(),
    );
  }

  @override
  void didChangeMetrics() {
    _captureKeyboardHeight();
  }

  void _captureKeyboardHeight() {
    if (!mounted) return;
    final view = View.of(context);
    final height = view.viewInsets.bottom / view.devicePixelRatio;
    if (height <= 0 || (height - _keyboardTrayHeight).abs() < 1) return;
    setState(() => _keyboardTrayHeight = height);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_levelSubscription?.cancel());
    _durationTimer?.cancel();
    _hideRecordingOverlay();
    if (_recording || _startingRecording) {
      unawaited(widget.controller.cancelVoiceRecording());
    }
    _focusNode.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _toggleFunctions() {
    if (_showFunctions) {
      setState(() => _showFunctions = false);
      _focusNode.requestFocus();
    } else {
      _focusNode.unfocus();
      setState(() => _showFunctions = true);
    }
  }

  void _onInputChanged(String value) {
    widget.controller.updateMentionInput(value);
    if (widget.controller.mentionVisible && !_mentionSheetOpen) {
      unawaited(_showMentionSheet());
    }
  }

  Future<void> _showMentionSheet() async {
    _mentionSheetOpen = true;
    final selected = await showHalfPageSheet<bool>(
      context: context,
      options: const HalfPageSheetOptions(heightFactor: .55),
      builder:
          (_) => _MentionBottomSheet(
            controller: widget.controller,
            input: widget.input,
          ),
    );
    _mentionSheetOpen = false;
    if (selected != true) widget.controller.dismissMention();
    if (mounted) _focusNode.requestFocus();
  }

  void closeInputArea() {
    _focusNode.unfocus();
    if (_showFunctions) setState(() => _showFunctions = false);
  }

  void focusText() {
    if (_voiceMode || _showFunctions) {
      setState(() {
        _voiceMode = false;
        _showFunctions = false;
      });
    }
    _focusNode.requestFocus();
  }

  void cancelActiveRecording() {
    if (!_recording && !_startingRecording) return;
    _pointerReleased = true;
    unawaited(_completeRecording(forceCancel: true));
  }

  void _toggleVoiceMode() {
    _focusNode.unfocus();
    setState(() {
      _showFunctions = false;
      _voiceMode = !_voiceMode;
    });
  }

  Future<void> _startRecording(LongPressStartDetails _) async {
    if (_startingRecording || _recording) return;
    _pointerReleased = false;
    _startingRecording = true;
    _recordingWatch.reset();
    setState(() {
      _cancelRecording = false;
      _recordingDuration = Duration.zero;
      _amplitudeSampleCount = 0;
      _finishingRecording = false;
      _levelPercentages.fillRange(0, _levelPercentages.length, 0);
    });
    try {
      final permitted = await widget.controller.hasVoiceRecordingPermission();
      debugPrint('[voicePermission] microphone=$permitted');
      if (!permitted) {
        _startingRecording = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未获得麦克风权限，请在系统设置中允许录音。')),
          );
        }
        return;
      }
      await widget.controller.startVoiceRecording();
      _startingRecording = false;
      if (_pointerReleased) {
        await widget.controller.cancelVoiceRecording();
        return;
      }
      if (!mounted) return;
      _recordingWatch.start();
      setState(() => _recording = true);
      _showRecordingOverlay();
      _levelSubscription = widget.controller
          .voiceRecordingLevels(const Duration(milliseconds: 70))
          .listen(
            _sampleRecordingLevel,
            onError: (Object error) {
              debugPrint('[voiceAmplitude][failed] error=$error');
            },
          );
      _durationTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!mounted || !_recording) return;
        setState(() => _recordingDuration = _recordingWatch.elapsed);
        _recordingOverlay?.markNeedsBuild();
        if (_recordingDuration >= const Duration(seconds: 60)) {
          unawaited(_completeRecording());
        }
      });
    } catch (error) {
      _startingRecording = false;
      _recordingWatch.stop();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法开始录音：$error')));
    }
  }

  void _sampleRecordingLevel(double levelPercent) {
    if (!_recording || !mounted) return;
    _amplitudeSampleCount++;
    // The media service maps dBFS to 0...100. The UI consumes only that
    // percentage and applies its own configurable display range.
    final inputPercent = levelPercent.clamp(0.0, 100.0);
    final percentage = _voiceWaveVisualConfig.mapInput(inputPercent);
    // Fast attack preserves peaks; a gentler release keeps adjacent samples
    // connected without flattening the contrast between silence and speech.
    final response = percentage > _levelPercentages.last ? 0.94 : 0.30;
    final smoothed =
        _levelPercentages.last * (1 - response) + percentage * response;
    if (_amplitudeSampleCount == 1 || _amplitudeSampleCount % 8 == 0) {
      final height = 5 + smoothed / 100 * 75;
      debugPrint(
        '[voiceWave] sample=$_amplitudeSampleCount '
        'inputPercent=${inputPercent.toStringAsFixed(1)} '
        'displayPercent=${percentage.toStringAsFixed(1)} '
        'smoothedPercent=${smoothed.toStringAsFixed(1)} '
        'height=${height.toStringAsFixed(1)}px',
      );
    }
    setState(() {
      _levelPercentages
        ..removeAt(0)
        ..add(smoothed.clamp(0.0, 100.0));
    });
    _recordingOverlay?.markNeedsBuild();
  }

  void _moveRecording(LongPressMoveUpdateDetails details) {
    final cancel = details.localPosition.dy < -44;
    if (cancel != _cancelRecording) {
      setState(() => _cancelRecording = cancel);
      _recordingOverlay?.markNeedsBuild();
    }
  }

  Future<void> _endRecording(LongPressEndDetails _) async {
    _pointerReleased = true;
    await _completeRecording();
  }

  Future<void> _completeRecording({bool forceCancel = false}) async {
    if (_startingRecording || !_recording || _finishingRecording) return;
    _finishingRecording = true;
    await _levelSubscription?.cancel();
    _levelSubscription = null;
    _durationTimer?.cancel();
    _durationTimer = null;
    _recordingWatch.stop();
    final duration = _recordingWatch.elapsed;
    final cancel =
        forceCancel ||
        _cancelRecording ||
        duration < const Duration(milliseconds: 800);
    setState(() {
      _recording = false;
      _recordingDuration = duration;
    });
    _hideRecordingOverlay();
    if (cancel) {
      await widget.controller.cancelVoiceRecording();
      if (mounted && !_cancelRecording) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('说话时间太短')));
      }
      return;
    }
    await widget.controller.finishVoiceRecording(duration);
  }

  void _showRecordingOverlay() {
    _hideRecordingOverlay();
    _recordingOverlay = OverlayEntry(
      builder:
          (context) => Positioned(
            top: MediaQuery.paddingOf(context).top + kToolbarHeight + 18,
            left: 42,
            right: 42,
            child: IgnorePointer(
              child: Material(
                color: Colors.transparent,
                child: _RecordingPanel(
                  levelPercentages: _levelPercentages,
                  visualConfig: _voiceWaveVisualConfig,
                  duration: _recordingDuration,
                  cancelling: _cancelRecording,
                ),
              ),
            ),
          ),
    );
    Overlay.of(context).insert(_recordingOverlay!);
  }

  void _hideRecordingOverlay() {
    _recordingOverlay?.remove();
    _recordingOverlay = null;
  }

  Future<void> _selectFunction(_ChatFunction item) async {
    if (item.label == '相册') {
      await widget.controller.chooseAndSendImages();
      return;
    }
    if (item.label == '拍摄') {
      await widget.controller.takeAndSendPhoto();
      return;
    }
    if (item.label == '视频') {
      await widget.controller.chooseAndSendVideo();
      return;
    }
    if (item.label == '文件') {
      await widget.controller.chooseAndSendFile();
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${item.label}功能暂未接入')));
  }

  @override
  Widget build(BuildContext context) => Material(
    elevation: 8,
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Row(
              // A growing text field must grow upward. Keep the fixed actions
              // on the bottom edge so their horizontal and vertical anchors do
              // not drift as a long draft gains lines.
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                SizedBox(
                  width: 44,
                  height: 42,
                  child: IconButton(
                    tooltip: _voiceMode ? '切换键盘' : '语音输入',
                    onPressed: _toggleVoiceMode,
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      _voiceMode ? Icons.keyboard_alt_outlined : Icons.mic_none,
                    ),
                  ),
                ),
                Expanded(
                  child:
                      _voiceMode
                          ? GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onLongPressStart: _startRecording,
                            onLongPressMoveUpdate: _moveRecording,
                            onLongPressEnd: _endRecording,
                            child: Container(
                              height: 42,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color:
                                    _recording
                                        ? Theme.of(
                                          context,
                                        ).colorScheme.primaryContainer
                                        : Theme.of(
                                          context,
                                        ).colorScheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _recording
                                    ? (_cancelRecording ? '松开取消' : '松开发送')
                                    : '按住说话',
                              ),
                            ),
                          )
                          : ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 132),
                            child: TextField(
                              controller: widget.input,
                              focusNode: _focusNode,
                              onTap: () {
                                if (_showFunctions) {
                                  setState(() => _showFunctions = false);
                                }
                              },
                              onChanged: _onInputChanged,
                              enabled: !widget.controller.isMuted,
                              minLines: 1,
                              maxLines: 5,
                              textInputAction: TextInputAction.newline,
                              decoration: InputDecoration(
                                hintText:
                                    widget.controller.isMuted
                                        ? '你已被禁言，暂不能发言'
                                        : '输入消息',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                ),
                if (!_voiceMode)
                  SizedBox(
                    width: 44,
                    height: 42,
                    child: IconButton(
                      tooltip: _showFunctions ? '打开键盘' : '更多功能',
                      onPressed: _toggleFunctions,
                      padding: EdgeInsets.zero,
                      icon: AnimatedRotation(
                        turns: _showFunctions ? 0.125 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: const Icon(Icons.add_circle_outline),
                      ),
                    ),
                  ),
                if (!_voiceMode)
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(56, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed:
                        widget.controller.isSending || widget.controller.isMuted
                            ? null
                            : () {
                              final value = widget.input.text;
                              widget.input.clear();
                              widget.controller.send(value);
                            },
                    child: const Text('发送'),
                  ),
              ],
            ),
          ),
          if (widget.controller.quoting case final quote?)
            Padding(
              padding: const EdgeInsets.fromLTRB(54, 0, 12, 8),
              child: ChatQuotePreview(
                senderName: quote.senderName,
                content: widget.quoteContentBuilder(quote),
                onClear: widget.controller.cancelQuote,
              ),
            ),
          // This is the Flutter counterpart of the UniApp keyboard-area: the
          // function panel is swapped inside one stable tray rather than
          // inserted beneath the input row after the system keyboard closes.
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            height: _showFunctions ? _keyboardTrayHeight : 0,
            child: ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                child: _FunctionPanel(
                  items: _functions,
                  pageController: _pageController,
                  page: _page,
                  onPageChanged: (value) => setState(() => _page = value),
                  onSelected: _selectFunction,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _FunctionPanel extends StatelessWidget {
  const _FunctionPanel({
    required this.items,
    required this.pageController,
    required this.page,
    required this.onPageChanged,
    required this.onSelected,
  });

  final List<_ChatFunction> items;
  final PageController pageController;
  final int page;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<_ChatFunction> onSelected;

  @override
  Widget build(BuildContext context) {
    final pageCount = (items.length / 8).ceil();
    return Container(
      height: 238,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
        ),
      ),
      child: Column(
        children: <Widget>[
          Expanded(
            child: PageView.builder(
              controller: pageController,
              itemCount: pageCount,
              onPageChanged: onPageChanged,
              itemBuilder: (context, pageIndex) {
                final start = pageIndex * 8;
                final pageItems = items.skip(start).take(8).toList();
                return GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.18,
                  ),
                  itemCount: pageItems.length,
                  itemBuilder: (context, index) {
                    final item = pageItems[index];
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onSelected(item),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final iconSize = (constraints.maxHeight - 22).clamp(
                            34.0,
                            44.0,
                          );
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Container(
                                width: iconSize,
                                height: iconSize,
                                decoration: BoxDecoration(
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Icon(
                                  item.icon,
                                  size: (iconSize * 0.54).clamp(19.0, 24.0),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Flexible(
                                child: Text(
                                  item.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textScaler: MediaQuery.textScalerOf(
                                    context,
                                  ).clamp(maxScaleFactor: 1.3),
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List<Widget>.generate(
              pageCount,
              (index) => AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: index == page ? 14 : 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
                decoration: BoxDecoration(
                  color:
                      index == page
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordingPanel extends StatelessWidget {
  const _RecordingPanel({
    required this.levelPercentages,
    required this.visualConfig,
    required this.duration,
    required this.cancelling,
  });
  final List<double> levelPercentages;
  final _VoiceWaveVisualConfig visualConfig;
  final Duration duration;
  final bool cancelling;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final seconds = duration.inSeconds;
    return Container(
      height: 142,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 12),
      decoration: BoxDecoration(
        color:
            cancelling
                ? colorScheme.errorContainer.withValues(alpha: 0.96)
                : colorScheme.inverseSurface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Colors.black26,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          Expanded(
            child: CustomPaint(
              painter: _VoiceWavePainter(
                levelPercentages: levelPercentages,
                visualConfig: visualConfig,
                color:
                    cancelling
                        ? colorScheme.error
                        : colorScheme.onInverseSurface,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            cancelling
                ? '松开手指，取消发送'
                : seconds >= 55
                ? '还可以说 ${60 - seconds} 秒'
                : '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
                    '${(seconds % 60).toString().padLeft(2, '0')}  上滑取消',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color:
                  cancelling
                      ? colorScheme.onErrorContainer
                      : colorScheme.onInverseSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceWavePainter extends CustomPainter {
  const _VoiceWavePainter({
    required this.levelPercentages,
    required this.visualConfig,
    required this.color,
  });
  final List<double> levelPercentages;
  final _VoiceWaveVisualConfig visualConfig;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (levelPercentages.isEmpty || size.isEmpty) return;
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round;
    final step = size.width / levelPercentages.length;
    final center = size.height / 2;
    for (var index = 0; index < levelPercentages.length; index++) {
      // The input value has already been mapped to a display percentage.
      final normalized = (levelPercentages[index] / 100).clamp(0.0, 1.0);
      final minHeight = visualConfig.idleBarHeight;
      final maxHeight = math.min(
        visualConfig.peakBarHeight,
        size.height * 0.98,
      );
      final height = minHeight + normalized * (maxHeight - minHeight);
      final x = step * (index + 0.5);
      canvas.drawLine(
        Offset(x, center - height / 2),
        Offset(x, center + height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_VoiceWavePainter oldDelegate) => true;
}

/// Converts the media layer's 0...100 level into the percentage displayed by
/// the chat waveform. Tune the two input thresholds per product/UI needs
/// without changing microphone or dBFS handling.
class _VoiceWaveVisualConfig {
  const _VoiceWaveVisualConfig({
    required this.inputFloorPercent,
    required this.inputPeakPercent,
    this.idleBarHeight = 5,
    this.peakBarHeight = 80,
  }) : assert(inputFloorPercent >= 0),
       assert(inputPeakPercent > inputFloorPercent),
       assert(inputPeakPercent <= 100),
       assert(idleBarHeight > 0),
       assert(peakBarHeight >= idleBarHeight);

  /// An input at or below this percentage is drawn as zero activity.
  final double inputFloorPercent;

  /// An input at or above this percentage is drawn as 100% activity.
  final double inputPeakPercent;

  final double idleBarHeight;
  final double peakBarHeight;

  double mapInput(double inputPercent) => ((inputPercent - inputFloorPercent) /
          (inputPeakPercent - inputFloorPercent) *
          100)
      .clamp(0.0, 100.0);
}

class _ChatFunction {
  const _ChatFunction(this.label, this.icon, {this.enabled = false});
  final String label;
  final IconData icon;
  final bool enabled;
}

class _TransferSheet extends StatefulWidget {
  const _TransferSheet({required this.controller});
  final CallCenterController controller;

  @override
  State<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<_TransferSheet> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _select(TransferTarget target) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('确认转接'),
            content: Text('确定将当前会话转接给“${target.name}”吗？'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('转接'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.controller.transferTo(target);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      // The controller retains the error for this sheet to render.
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      return Material(
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          children: <Widget>[
            ListTile(
              title: const Text('转接给'),
              subtitle: const Text('选择同一店铺内可服务的店主或客服'),
              trailing: IconButton(
                tooltip: '关闭',
                onPressed:
                    controller.isSubmitting
                        ? null
                        : () => Navigator.pop(context, false),
                icon: const Icon(Icons.close),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _search,
                onChanged: controller.updateKeyword,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '搜索店主或客服',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            if (controller.error != null)
              MaterialBanner(
                content: Text('加载或转接失败：${controller.error}'),
                actions: <Widget>[
                  TextButton(
                    onPressed: controller.isLoading ? null : controller.refresh,
                    child: const Text('重试'),
                  ),
                ],
              ),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification.metrics.extentAfter < 100 &&
                      controller.hasMore &&
                      !controller.isLoading) {
                    controller.loadMore();
                  }
                  return false;
                },
                child:
                    controller.targets.isEmpty && controller.isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : controller.targets.isEmpty
                        ? const Center(child: Text('暂无可转接的客服'))
                        : ListView.builder(
                          itemCount:
                              controller.targets.length +
                              (controller.hasMore || controller.isLoading
                                  ? 1
                                  : 0),
                          itemBuilder: (context, index) {
                            if (index == controller.targets.length) {
                              return SizedBox(
                                height: 48,
                                child: Center(
                                  child:
                                      controller.isLoading
                                          ? const SizedBox.square(
                                            dimension: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                          : const Text('上拉加载更多'),
                                ),
                              );
                            }
                            final target = controller.targets[index];
                            final subtitle = <String>[
                              target.roleLabel,
                              if (target.serviceStatusDescription.isNotEmpty)
                                target.serviceStatusDescription,
                            ].join(' · ');
                            return ListTile(
                              enabled: !controller.isSubmitting,
                              leading: ChatObjectAvatar(
                                name: target.name,
                                imageUrl:
                                    target.avatarUrl.isEmpty
                                        ? null
                                        : target.avatarUrl,
                                radius: 20,
                              ),
                              title: Text(target.name),
                              subtitle: Text(subtitle),
                              trailing:
                                  controller.isSubmitting
                                      ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                      : const Icon(Icons.chevron_right),
                              onTap: () => _select(target),
                            );
                          },
                        ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
