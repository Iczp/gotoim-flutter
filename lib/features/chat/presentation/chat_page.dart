import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/file/file_picker_service.dart';
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
                                        message.messageType == 5 &&
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
                IconButton(onPressed: () {}, icon: const Icon(Icons.mic_none)),
                Expanded(
                  child: TextField(
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
                IconButton(
                  tooltip: _showFunctions ? '打开键盘' : '更多功能',
                  onPressed: _toggleFunctions,
                  icon: AnimatedRotation(
                    turns: _showFunctions ? 0.125 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(Icons.add_circle_outline),
                  ),
                ),
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
