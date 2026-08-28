import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/file/file_picker_service.dart';
import '../../../core/services/media/media_service.dart';
import '../../../core/services/media/audio_playback_service.dart';
import '../../../core/services/clipboard_service.dart';
import '../../../core/config/app_environment.dart';
import '../../../core/widgets/parametric_chat_bubble.dart';
import '../../auth/application/auth_controller.dart';
import '../application/chat_controller.dart';
import '../data/models/chat_message.dart';
import '../../chat_settings/data/models/chat_member.dart';
import '../../chat_settings/application/chat_settings_controller.dart';
import '../../chat_settings/presentation/member_profile_sheet.dart';
import '../../session/application/session_list_controller.dart';
import '../../session/presentation/chat_object_avatar.dart';
import '../../call_center/application/call_center_controller.dart';
import '../../call_center/data/models/transfer_target.dart';

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
  final Map<String, bool> _timeVisibility = <String, bool>{};
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
      mediaService: ref.read(mediaServiceProvider),
      audioPlaybackService: _audioPlayback,
      signalRGateway: ref.read(signalRGatewayProvider),
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
    builder:
        (context, _) => Scaffold(
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
                  : null,
          appBar: AppBar(
            title: Text(controller.title, overflow: TextOverflow.ellipsis),
            actions: <Widget>[
              if (controller.friend?.isShopkeeperOrWaiter == true)
                IconButton(
                  tooltip: '转接',
                  onPressed: _openTransferSheet,
                  icon: const Icon(Icons.electrical_services_outlined),
                ),
              IconButton(
                tooltip: '聊天设置',
                onPressed: () async {
                  FocusManager.instance.primaryFocus?.unfocus();
                  final cleared = await context.push<bool>(
                    '/chat/${Uri.encodeComponent(widget.sessionUnitId)}/settings'
                    '?ownerId=${widget.ownerId}',
                  );
                  if (cleared == true) {
                    controller.handleMessagesCleared();
                  }
                },
                icon: const Icon(Icons.more_horiz),
              ),
            ],
          ),
          body: Column(
            children: <Widget>[
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    _composerKey.currentState?.closeInputArea();
                  },
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      controller.setViewingLatest(
                        notification.metrics.pixels <= 32,
                      );
                      final isUserPaging =
                          (notification is ScrollUpdateNotification &&
                              notification.dragDetails != null) ||
                          notification is OverscrollNotification;
                      if (isUserPaging &&
                          notification.metrics.extentAfter < 180) {
                        controller.loadMore();
                      }
                      return false;
                    },
                    child:
                        controller.messages.isEmpty
                            ? _EmptyMessagesState(controller: controller)
                            : Align(
                              alignment: Alignment.topCenter,
                              child: ListView.builder(
                                controller: _scrollController,
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                reverse: true,
                                shrinkWrap: true,
                                findChildIndexCallback: (key) {
                                  if (key is! ValueKey<String>) return null;
                                  final index = controller.messages.indexWhere(
                                    (message) => message.localId == key.value,
                                  );
                                  return index < 0 ? null : index;
                                },
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 16,
                                ),
                                itemCount: controller.messages.length + 1,
                                itemBuilder: (context, index) {
                                  if (index == controller.messages.length) {
                                    if (controller.isLoading) {
                                      return const Center(
                                        child: Padding(
                                          padding: EdgeInsets.all(16),
                                          child: CircularProgressIndicator(),
                                        ),
                                      );
                                    }
                                    if (controller.error != null) {
                                      return TextButton(
                                        style: _compactTextButtonStyle,
                                        onPressed: controller.loadMore,
                                        child: Text(
                                          '加载失败，点击重试：${controller.error}',
                                        ),
                                      );
                                    }
                                    return Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child:
                                            controller.hasMore
                                                ? TextButton(
                                                  style:
                                                      _compactTextButtonStyle,
                                                  onPressed:
                                                      controller.loadMore,
                                                  child: const Text('加载更多消息'),
                                                )
                                                : const Text('美好生活从这里开始'),
                                      ),
                                    );
                                  }
                                  final message = controller.messages[index];
                                  final older =
                                      index + 1 < controller.messages.length
                                          ? controller.messages[index + 1]
                                          : null;
                                  return _MessageRow(
                                    key: ValueKey<String>(message.localId),
                                    message: message,
                                    showTime: _showTime(message, older),
                                    onUserTap:
                                        () => _showSenderProfile(message),
                                    onVoiceOpened:
                                        () =>
                                            controller.markVoiceOpened(message),
                                    onRetry:
                                        (message.messageType == 5 ||
                                                    message.messageType == 2 ||
                                                    message.messageType == 4 ||
                                                    message.messageType == 3) &&
                                                message.state == 'failed'
                                            ? () =>
                                                controller.retryFile(message)
                                            : null,
                                    imageBytes: controller.imagePreview(
                                      message.localId,
                                    ),
                                    uploadProgress:
                                        controller.uploadProgress[message
                                            .localId],
                                    apiBaseUrl:
                                        ref
                                            .read(appEnvironmentProvider)
                                            .apiBaseUrl,
                                    selected: controller.selectedLocalIds
                                        .contains(message.localId),
                                    selectionMode: controller.selectionMode,
                                    onTap:
                                        controller.selectionMode
                                            ? () => controller.toggleSelection(
                                              message,
                                            )
                                            : null,
                                    onLongPress:
                                        () => _showMessageActions(message),
                                    onQuoteTap: () => _scrollToQuoted(message),
                                    showUnreadDivider:
                                        message.serverId != null &&
                                        controller.friend?.readMessageId ==
                                            message.serverId &&
                                        index > 0,
                                    showPeerRead:
                                        message.isMine &&
                                        message.serverId != null &&
                                        controller.friend?.peerReadMessageId ==
                                            message.serverId,
                                  );
                                },
                              ),
                            ),
                  ),
                ),
              ),
              if (controller.selectionMode)
                _SelectionBar(
                  count: controller.selectedLocalIds.length,
                  onCancel: controller.cancelSelection,
                  onDelete: () => _deleteSelectedMessages(),
                  onMergeForward: () => _showMergeForwardTargets(),
                )
              else
                SafeArea(
                  top: false,
                  child: _Composer(
                    key: _composerKey,
                    controller: controller,
                    input: input,
                  ),
                ),
            ],
          ),
        ),
  );

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

  Future<void> _showMessageActions(ChatMessage message) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => SafeArea(
            child: Wrap(
              children: <Widget>[
                if (message.messageType == 0)
                  ListTile(
                    leading: const Icon(Icons.copy_outlined),
                    title: const Text('复制'),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await controller.copyMessage(message);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.format_quote),
                  title: const Text('引用'),
                  enabled: message.serverId != null,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    controller.quoteMessage(message);
                    _composerKey.currentState?.focusText();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.checklist),
                  title: const Text('多选'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    controller.beginSelection(message);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('删除'),
                  subtitle: Text(
                    message.serverId == null
                        ? '删除本地待发送消息'
                        : '从当前会话身份删除，并清理本地记录',
                  ),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _runMessageAction(
                      message.serverId == null
                          ? () => controller.deleteMessages(<String>[
                            message.localId,
                          ])
                          : () => controller.deleteRemote(message),
                      success: '消息已删除',
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.undo),
                  title: const Text('撤回'),
                  enabled:
                      message.isMine &&
                      message.serverId != null &&
                      !message.isRollbacked,
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _runMessageAction(
                      () => controller.rollbackMessage(message),
                      success: '消息已撤回',
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.forward),
                  title: const Text('转发'),
                  enabled: message.serverId != null && !message.isRollbacked,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showForwardTargets(message);
                  },
                ),
              ],
            ),
          ),
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
    final transferred = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
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
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * .62,
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
          ),
    );
  }

  Future<void> _showMergeForwardTargets() async {
    final count = controller.selectedLocalIds.length;
    if (count == 0) return;
    final targets = await controller.loadForwardTargets();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * .62,
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
      if (index >= 0 && _scrollController.hasClients) {
        await _scrollController.animateTo(
          (index * 92.0).clamp(0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
        return;
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

class _EmptyMessagesState extends StatelessWidget {
  const _EmptyMessagesState({required this.controller});
  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.error != null) {
      return Center(
        child: TextButton(
          style: _compactTextButtonStyle,
          onPressed: controller.loadMore,
          child: Text('消息加载失败，点击重试：${controller.error}'),
        ),
      );
    }
    return const Center(child: Text('暂无消息'));
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.message,
    required this.showTime,
    required this.onUserTap,
    required this.onVoiceOpened,
    this.onRetry,
    required this.imageBytes,
    required this.uploadProgress,
    required this.apiBaseUrl,
    required this.selected,
    required this.selectionMode,
    required this.onLongPress,
    required this.onQuoteTap,
    required this.showUnreadDivider,
    required this.showPeerRead,
    this.onTap,
    super.key,
  });
  final ChatMessage message;
  final bool showTime;
  final VoidCallback onUserTap;
  final Future<void> Function() onVoiceOpened;
  final VoidCallback? onRetry;
  final Uint8List? imageBytes;
  final double? uploadProgress;
  final String apiBaseUrl;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onLongPress;
  final VoidCallback onQuoteTap;
  final bool showUnreadDivider;
  final bool showPeerRead;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
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
    final text = switch (message.messageType) {
      0 => message.text,
      2 => '[图片]',
      3 => '[语音]',
      4 => '[视频]',
      5 => message.fileName.isEmpty ? '[文件]' : message.fileName,
      _ => message.text.isEmpty ? '[暂不支持的消息]' : message.text,
    };
    if (message.isRollbacked) {
      return Padding(
        padding: const EdgeInsets.all(10),
        child: Center(child: Text('${message.senderName} 撤回了一条消息')),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: onLongPress,
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
                      clipBehavior: Clip.none,
                      children: <Widget>[
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: bubbleWidth),
                          child: ParametricChatBubble(
                            config: ParametricBubbleConfig(
                              side:
                                  message.isMine
                                      ? ParametricBubbleSide.right
                                      : ParametricBubbleSide.left,
                            ),
                            color:
                                message.isMine
                                    ? Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer
                                    : Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                if (message.quoteMessage.isNotEmpty)
                                  InkWell(
                                    onTap: onQuoteTap,
                                    child: Container(
                                      width: double.infinity,
                                      margin: const EdgeInsets.only(bottom: 7),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .surface
                                            .withValues(alpha: .55),
                                        borderRadius: BorderRadius.circular(7),
                                        border: Border(
                                          left: BorderSide(
                                            color:
                                                Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                            width: 3,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        '[${message.quoteSenderName}]：${message.quotePreview}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                      ),
                                    ),
                                  ),
                                if (message.messageType == 5)
                                  _FileMessageCard(message: message)
                                else if (message.messageType == 3)
                                  _VoiceMessageBubble(
                                    message: message,
                                    onOpened: onVoiceOpened,
                                  )
                                else if (message.messageType == 2)
                                  _ImageMessageCard(
                                    message: message,
                                    bytes: imageBytes,
                                    apiBaseUrl: apiBaseUrl,
                                    progress: uploadProgress,
                                  )
                                else if (message.messageType == 4)
                                  _VideoMessageCard(
                                    message: message,
                                    apiBaseUrl: apiBaseUrl,
                                    progress: uploadProgress,
                                  )
                                else if (message.messageType == 0)
                                  MarkdownBody(
                                    data: text,
                                    selectable: true,
                                    shrinkWrap: true,
                                  )
                                else
                                  Text(text),
                              ],
                            ),
                          ),
                        ),
                        if (message.isMine && message.state == 'sending')
                          const Positioned(
                            left: -24,
                            top: 10,
                            child: SizedBox.square(
                              dimension: 17,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        if (message.isMine && message.state == 'failed')
                          Positioned(
                            left: -29,
                            top: 4,
                            child: IconButton(
                              tooltip: '发送失败，点击重试',
                              visualDensity: VisualDensity.compact,
                              onPressed: onRetry,
                              icon: const Icon(
                                Icons.error,
                                color: Colors.red,
                                size: 19,
                              ),
                            ),
                          ),
                      ],
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

class _FileMessageCard extends StatelessWidget {
  const _FileMessageCard({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 230,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Icon(Icons.insert_drive_file_outlined, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message.fileName.isEmpty ? '文件' : message.fileName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const Divider(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                _formatFileSize(message.fileSize),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
            Text(
              message.state == 'sending'
                  ? '发送中'
                  : message.state == 'failed'
                  ? '发送失败'
                  : message.fileSuffix,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: message.state == 'failed' ? Colors.red : null,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }
}

class _VoiceMessageBubble extends ConsumerWidget {
  const _VoiceMessageBubble({required this.message, required this.onOpened});
  final ChatMessage message;
  final Future<void> Function() onOpened;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seconds = (message.audioDuration.inMilliseconds / 1000).ceil();
    final playback = ref.watch(audioPlaybackServiceProvider);
    final playing = playback.isMessagePlaying(message.localId);
    final downloading = playback.downloadingMessageId == message.localId;
    final progress =
        playback.activeMessageId == message.localId &&
                playback.duration.inMilliseconds > 0
            ? playback.position.inMilliseconds /
                playback.duration.inMilliseconds
            : 0.0;
    return InkWell(
      onTap:
          message.state == 'sending'
              ? null
              : () async {
                try {
                  await playback.toggle(
                    messageId: message.localId,
                    localPath: message.localFilePath,
                    url: message.audioUrl,
                    mimeType: message.content['contentType']?.toString(),
                  );
                  if (playback.isMessagePlaying(message.localId)) {
                    await onOpened();
                  }
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('语音播放失败：$error')));
                  }
                }
              },
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: (96.0 + seconds.clamp(0, 30) * 3).clamp(96.0, 186.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children:
                  message.isMine
                      ? <Widget>[
                        if (message.state == 'sending')
                          const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 1.8),
                          ),
                        Expanded(
                          child: Text(
                            seconds <= 0 ? '语音' : '$seconds″',
                            textAlign: TextAlign.right,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Transform.flip(
                          flipX: true,
                          child: _VoicePlaybackIcon(playing: playing),
                        ),
                      ]
                      : <Widget>[
                        _VoicePlaybackIcon(playing: playing),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(seconds <= 0 ? '语音' : '$seconds″'),
                        ),
                        if (message.state == 'sending')
                          const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 1.8),
                          ),
                      ],
            ),
            if (downloading || progress > 0)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: LinearProgressIndicator(
                  minHeight: 2,
                  value: downloading ? playback.downloadProgress : progress,
                ),
              ),
            if (!message.isOpened && !message.isMine)
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(top: 3),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _VoicePlaybackIcon extends StatefulWidget {
  const _VoicePlaybackIcon({required this.playing});
  final bool playing;

  @override
  State<_VoicePlaybackIcon> createState() => _VoicePlaybackIconState();
}

class _VoicePlaybackIconState extends State<_VoicePlaybackIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _VoicePlaybackIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing == oldWidget.playing) return;
    if (widget.playing) {
      _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder:
        (context, _) => CustomPaint(
          size: const Size(24, 24),
          painter: _PlaybackWavePainter(
            color:
                IconTheme.of(context).color ??
                Theme.of(context).colorScheme.onSurface,
            waveCount: widget.playing ? (_controller.value * 3).floor() + 1 : 3,
          ),
        ),
  );
}

class _PlaybackWavePainter extends CustomPainter {
  const _PlaybackWavePainter({required this.color, required this.waveCount});
  final Color color;
  final int waveCount;

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
    canvas.drawCircle(
      Offset(5, size.height / 2),
      1.8,
      paint..style = PaintingStyle.fill,
    );
    paint.style = PaintingStyle.stroke;
    for (var index = 0; index < waveCount.clamp(1, 3); index++) {
      final radius = 5.0 + index * 4;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(5, size.height / 2), radius: radius),
        -0.72,
        1.44,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PlaybackWavePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.waveCount != waveCount;
}

class _ImageMessageCard extends StatelessWidget {
  const _ImageMessageCard({
    required this.message,
    required this.bytes,
    required this.apiBaseUrl,
    required this.progress,
  });
  final ChatMessage message;
  final Uint8List? bytes;
  final String apiBaseUrl;
  final double? progress;

  String get _url {
    final source = message.mediaUrl ?? '';
    final uri = Uri.tryParse(source);
    if (uri?.hasScheme == true || source.isEmpty) return source;
    return Uri.parse(apiBaseUrl).resolve(source).toString();
  }

  @override
  Widget build(BuildContext context) {
    final image =
        bytes != null
            ? Image.memory(bytes!, fit: BoxFit.cover)
            : _url.isNotEmpty
            ? CachedNetworkImage(
              imageUrl: _url,
              fit: BoxFit.cover,
              placeholder:
                  (_, _) => const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              errorWidget:
                  (_, _, _) =>
                      const Icon(Icons.broken_image_outlined, size: 42),
            )
            : const Center(child: Icon(Icons.image_outlined, size: 42));
    return InkWell(
      onTap:
          () => showDialog<void>(
            context: context,
            barrierColor: Colors.black87,
            builder:
                (_) => Dialog.fullscreen(
                  backgroundColor: Colors.black,
                  child: Stack(
                    children: <Widget>[
                      Center(
                        child: InteractiveViewer(
                          minScale: .5,
                          maxScale: 5,
                          child: image,
                        ),
                      ),
                      SafeArea(
                        child: IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
          ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 190,
          height: 190,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              image,
              if (progress != null && progress! < 1)
                ColoredBox(
                  color: Colors.black38,
                  child: Center(
                    child: SizedBox.square(
                      dimension: 46,
                      child: CircularProgressIndicator(
                        value: progress,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoMessageCard extends StatelessWidget {
  const _VideoMessageCard({
    required this.message,
    required this.apiBaseUrl,
    required this.progress,
  });
  final ChatMessage message;
  final String apiBaseUrl;
  final double? progress;

  Uri? get _uri {
    final source = message.mediaUrl ?? message.localFilePath ?? '';
    if (source.isEmpty) return null;
    final parsed = Uri.tryParse(source);
    if (parsed?.hasScheme == true) return parsed;
    if (message.localFilePath != null) return Uri.file(source);
    return Uri.parse(apiBaseUrl).resolve(source);
  }

  @override
  Widget build(BuildContext context) => InkWell(
    onTap:
        _uri == null
            ? null
            : () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => _VideoViewer(uri: _uri!)),
            ),
    child: SizedBox(
      width: 210,
      height: 128,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            const Icon(Icons.play_circle_fill, color: Colors.white, size: 52),
            Positioned(
              left: 8,
              right: 8,
              bottom: 7,
              child: Text(
                message.fileName.isEmpty ? '视频' : message.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white),
              ),
            ),
            if (progress != null && progress! < 1)
              CircularProgressIndicator(value: progress, color: Colors.white),
          ],
        ),
      ),
    ),
  );
}

class _VideoViewer extends StatefulWidget {
  const _VideoViewer({required this.uri});
  final Uri uri;
  @override
  State<_VideoViewer> createState() => _VideoViewerState();
}

class _VideoViewerState extends State<_VideoViewer> {
  late final VideoPlayerController _controller;
  Object? _error;
  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(widget.uri)
      ..initialize()
          .then((_) {
            if (mounted) setState(() {});
          })
          .catchError((Object error) {
            if (mounted) setState(() => _error = error);
          });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
    ),
    body: Center(
      child:
          _error != null
              ? Text(
                '视频加载失败：$_error',
                style: const TextStyle(color: Colors.white),
              )
              : !_controller.value.isInitialized
              ? const CircularProgressIndicator()
              : GestureDetector(
                onTap:
                    () => setState(
                      () =>
                          _controller.value.isPlaying
                              ? _controller.pause()
                              : _controller.play(),
                    ),
                child: AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                ),
              ),
    ),
  );
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.onCancel,
    required this.onDelete,
    required this.onMergeForward,
  });
  final int count;
  final VoidCallback onCancel;
  final VoidCallback onDelete;
  final VoidCallback onMergeForward;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Material(
      elevation: 8,
      child: SizedBox(
        height: 58,
        child: Row(
          children: <Widget>[
            IconButton(
              tooltip: '取消多选',
              onPressed: onCancel,
              icon: const Icon(Icons.close),
            ),
            Expanded(child: Text('已选择 $count 条')),
            IconButton(
              tooltip: '合并转发',
              onPressed: count == 0 ? null : onMergeForward,
              icon: const Icon(Icons.reply_all_outlined),
            ),
            IconButton(
              tooltip: '删除所选消息',
              onPressed: count == 0 ? null : onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    ),
  );
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
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: .55,
    child: AnimatedBuilder(
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
  const _Composer({required this.controller, required this.input, super.key});
  final ChatController controller;
  final TextEditingController input;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
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
  final List<double> _levels = List<double>.filled(24, 0.08, growable: true);
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

  @override
  void dispose() {
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
    final selected = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
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
      _levels.fillRange(0, _levels.length, 0.04);
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

  void _sampleRecordingLevel(double level) {
    if (!_recording || !mounted) return;
    _amplitudeSampleCount++;
    if (_amplitudeSampleCount == 1) {
      debugPrint('[voiceAmplitude] stream=true level=$level');
    }
    // Recorder amplitudes tend to cluster near the low end. Apply a visual
    // (not recording) gain curve so normal speech has a clearly visible wave.
    final normalized = ((level - 0.05) / 0.95).clamp(0.0, 1.0);
    final boosted = 0.10 + math.pow(normalized, 0.42).toDouble() * 0.90;
    // Fast attack makes a spoken syllable immediately noticeable; the slower
    // release keeps the waveform lively without abrupt drop-outs.
    final response = boosted > _levels.last ? 0.88 : 0.46;
    final smoothed = _levels.last * (1 - response) + boosted * response;
    setState(() {
      _levels
        ..removeAt(0)
        ..add(smoothed.clamp(0.06, 1.0));
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
                  levels: _levels,
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
          if (widget.controller.quoting case final quote?)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              padding: const EdgeInsets.only(left: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border(
                  left: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 3,
                  ),
                ),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Text(
                        '引用 ${quote.senderName}：${quote.text.isEmpty ? '[消息]' : quote.text}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '取消引用',
                    onPressed: widget.controller.cancelQuote,
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Row(
              children: <Widget>[
                IconButton(
                  tooltip: _voiceMode ? '切换键盘' : '语音输入',
                  onPressed: _toggleVoiceMode,
                  icon: Icon(
                    _voiceMode ? Icons.keyboard_alt_outlined : Icons.mic_none,
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
                          : TextField(
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
                if (!_voiceMode)
                  IconButton(
                    tooltip: _showFunctions ? '打开键盘' : '更多功能',
                    onPressed: _toggleFunctions,
                    icon: AnimatedRotation(
                      turns: _showFunctions ? 0.125 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const Icon(Icons.add_circle_outline),
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
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child:
                _showFunctions
                    ? _FunctionPanel(
                      items: _functions,
                      pageController: _pageController,
                      page: _page,
                      onPageChanged: (value) => setState(() => _page = value),
                      onSelected: _selectFunction,
                    )
                    : const SizedBox(width: double.infinity),
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
    required this.levels,
    required this.duration,
    required this.cancelling,
  });
  final List<double> levels;
  final Duration duration;
  final bool cancelling;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final seconds = duration.inSeconds;
    return Container(
      height: 126,
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
                levels: levels,
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
  const _VoiceWavePainter({required this.levels, required this.color});
  final List<double> levels;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty || size.isEmpty) return;
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round;
    final step = size.width / levels.length;
    final center = size.height / 2;
    for (var index = 0; index < levels.length; index++) {
      final normalized = levels[index].clamp(0.06, 1.0);
      final height = normalized * size.height * 0.96;
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
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: .62,
    child: AnimatedBuilder(
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
                      onPressed:
                          controller.isLoading ? null : controller.refresh,
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
    ),
  );
}

final ButtonStyle _compactTextButtonStyle = TextButton.styleFrom(
  minimumSize: const Size(0, 40),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);
