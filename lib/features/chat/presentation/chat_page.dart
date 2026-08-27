import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/file/file_picker_service.dart';
import '../../../core/services/media/media_service.dart';
import '../application/chat_controller.dart';
import '../data/models/chat_message.dart';
import '../../chat_settings/data/models/chat_member.dart';
import '../../chat_settings/presentation/member_profile_sheet.dart';
import '../../session/application/session_list_controller.dart';
import '../../session/presentation/chat_object_avatar.dart';

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

class _ChatPageState extends ConsumerState<ChatPage> {
  late final ChatController controller;
  final input = TextEditingController();
  final GlobalKey<_ComposerState> _composerKey = GlobalKey<_ComposerState>();
  final Map<String, bool> _timeVisibility = <String, bool>{};
  int _timeVisibilityResetMarker = 0;

  @override
  void initState() {
    super.initState();
    controller = ChatController(
      ref.read(messageRepositoryProvider),
      ref.read(sessionRepositoryProvider),
      filePickerService: ref.read(filePickerServiceProvider),
      mediaService: ref.read(mediaServiceProvider),
      ownerId: widget.ownerId,
      sessionUnitId: widget.sessionUnitId,
      initialTitle: widget.title,
    )..initialize();
  }

  @override
  void dispose() {
    controller.dispose();
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder:
        (context, _) => Scaffold(
          appBar: AppBar(
            title: Text(controller.title, overflow: TextOverflow.ellipsis),
            actions: <Widget>[
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
                                    onRetry:
                                        (message.messageType == 5 ||
                                                    message.messageType == 3) &&
                                                message.state == 'failed'
                                            ? () =>
                                                controller.retryFile(message)
                                            : null,
                                  );
                                },
                              ),
                            ),
                  ),
                ),
              ),
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
    this.onRetry,
    super.key,
  });
  final ChatMessage message;
  final bool showTime;
  final VoidCallback onUserTap;
  final VoidCallback? onRetry;

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
    return Column(
      children: <Widget>[
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
            final bubbleWidth = constraints.maxWidth * 0.68;
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (message.isMine && message.state == 'sending')
                        const Padding(
                          padding: EdgeInsets.only(right: 7),
                          child: SizedBox.square(
                            dimension: 17,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      if (message.isMine && message.state == 'failed')
                        IconButton(
                          tooltip: '发送失败，点击重试',
                          visualDensity: VisualDensity.compact,
                          onPressed: onRetry,
                          icon: const Icon(
                            Icons.error,
                            color: Colors.red,
                            size: 19,
                          ),
                        ),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: bubbleWidth),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color:
                                message.isMine
                                    ? Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer
                                    : Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 9,
                            ),
                            child:
                                message.messageType == 5
                                    ? _FileMessageCard(message: message)
                                    : message.messageType == 3
                                    ? _VoiceMessageBubble(message: message)
                                    : Text(text),
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
              children:
                  message.isMine
                      ? <Widget>[content, const SizedBox(width: 8), avatar]
                      : <Widget>[avatar, const SizedBox(width: 8), content],
            );
          },
        ),
        const SizedBox(height: 8),
      ],
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

class _VoiceMessageBubble extends StatelessWidget {
  const _VoiceMessageBubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final seconds = (message.audioDuration.inMilliseconds / 1000).ceil();
    return SizedBox(
      width: (96.0 + seconds.clamp(0, 30) * 3).clamp(96.0, 186.0),
      child: Row(
        children: <Widget>[
          Icon(
            message.isMine
                ? Icons.graphic_eq_rounded
                : Icons.multitrack_audio_rounded,
            size: 22,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(seconds <= 0 ? '语音' : '$seconds″')),
          if (message.state == 'sending')
            const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 1.8),
            ),
        ],
      ),
    );
  }
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
  Timer? _levelTimer;
  final Stopwatch _recordingWatch = Stopwatch();
  Duration _recordingDuration = Duration.zero;
  final List<double> _levels = List<double>.filled(24, 0.08);
  int _page = 0;

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
    _levelTimer?.cancel();
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

  void closeInputArea() {
    _focusNode.unfocus();
    if (_showFunctions) setState(() => _showFunctions = false);
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
    });
    try {
      await widget.controller.startVoiceRecording();
      _startingRecording = false;
      if (_pointerReleased) {
        await widget.controller.cancelVoiceRecording();
        return;
      }
      if (!mounted) return;
      _recordingWatch.start();
      setState(() => _recording = true);
      _levelTimer = Timer.periodic(
        const Duration(milliseconds: 80),
        (_) => _sampleRecordingLevel(),
      );
    } catch (error) {
      _startingRecording = false;
      _recordingWatch.stop();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法开始录音：$error')));
    }
  }

  Future<void> _sampleRecordingLevel() async {
    if (!_recording) return;
    try {
      final level = await widget.controller.voiceRecordingLevel();
      if (!mounted || !_recording) return;
      setState(() {
        _levels
          ..removeAt(0)
          ..add(level);
        _recordingDuration = _recordingWatch.elapsed;
      });
    } catch (_) {
      // A transient amplitude read must not terminate an active recording.
    }
  }

  void _moveRecording(LongPressMoveUpdateDetails details) {
    final cancel = details.localPosition.dy < -44;
    if (cancel != _cancelRecording) {
      setState(() => _cancelRecording = cancel);
    }
  }

  Future<void> _endRecording(LongPressEndDetails _) async {
    _pointerReleased = true;
    if (_startingRecording || !_recording) return;
    _levelTimer?.cancel();
    _recordingWatch.stop();
    final duration = _recordingWatch.elapsed;
    final cancel =
        _cancelRecording || duration < const Duration(milliseconds: 800);
    setState(() {
      _recording = false;
      _recordingDuration = duration;
    });
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

  Future<void> _selectFunction(_ChatFunction item) async {
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
                            minLines: 1,
                            maxLines: 5,
                            textInputAction: TextInputAction.newline,
                            decoration: const InputDecoration(
                              hintText: '输入消息',
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
                        widget.controller.isSending
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
          if (_recording)
            _RecordingPanel(
              levels: _levels,
              duration: _recordingDuration,
              cancelling: _cancelRecording,
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
      height: 112,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 10),
      color:
          cancelling
              ? colorScheme.errorContainer
              : colorScheme.surfaceContainerLowest,
      child: Column(
        children: <Widget>[
          Expanded(
            child: CustomPaint(
              painter: _VoiceWavePainter(
                levels: levels,
                color: cancelling ? colorScheme.error : colorScheme.primary,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            cancelling
                ? '松开手指，取消发送'
                : '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
                    '${(seconds % 60).toString().padLeft(2, '0')}  上滑取消',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color:
                  cancelling
                      ? colorScheme.onErrorContainer
                      : colorScheme.onSurfaceVariant,
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
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round;
    final step = size.width / levels.length;
    final center = size.height / 2;
    for (var index = 0; index < levels.length; index++) {
      final normalized = levels[index].clamp(0.06, 1.0);
      final height = normalized * size.height * 0.9;
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

final ButtonStyle _compactTextButtonStyle = TextButton.styleFrom(
  minimumSize: const Size(0, 40),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);
