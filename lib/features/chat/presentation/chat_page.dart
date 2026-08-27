import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/file/file_picker_service.dart';
import '../application/chat_controller.dart';
import '../data/models/chat_message.dart';
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
  final Map<String, bool> _timeVisibility = <String, bool>{};

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
              IconButton(onPressed: () {}, icon: const Icon(Icons.more_horiz)),
            ],
          ),
          body: Column(
            children: <Widget>[
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
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
                child: _Composer(controller: controller, input: input),
              ),
            ],
          ),
        ),
  );

  bool _showTime(ChatMessage current, ChatMessage? older) {
    return _timeVisibility.putIfAbsent(current.localId, () {
      if (current.createdAt == null || older?.createdAt == null) {
        return older == null;
      }
      return current.createdAt!.difference(older!.createdAt!).abs() >
          const Duration(minutes: 5);
    });
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
    this.onRetry,
    super.key,
  });
  final ChatMessage message;
  final bool showTime;
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
            final avatar = ChatObjectAvatar(
              name: message.senderName,
              imageUrl: message.senderAvatarUrl,
              radius: 18,
            );
            final content = Expanded(
              child: Column(
                crossAxisAlignment:
                    message.isMine
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      message.senderName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
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

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.input});
  final ChatController controller;
  final TextEditingController input;

  @override
  Widget build(BuildContext context) => Material(
    elevation: 8,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        children: <Widget>[
          IconButton(onPressed: () {}, icon: const Icon(Icons.mic_none)),
          Expanded(
            child: TextField(
              controller: input,
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
            tooltip: '发送文件',
            onPressed: controller.chooseAndSendFile,
            icon: const Icon(Icons.add_circle_outline),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(56, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed:
                controller.isSending
                    ? null
                    : () {
                      final value = input.text;
                      input.clear();
                      controller.send(value);
                    },
            child: const Text('发送'),
          ),
        ],
      ),
    ),
  );
}

final ButtonStyle _compactTextButtonStyle = TextButton.styleFrom(
  minimumSize: const Size(0, 40),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);
