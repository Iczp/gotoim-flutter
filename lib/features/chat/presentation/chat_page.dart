import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/chat_controller.dart';
import '../data/models/chat_message.dart';

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

  @override
  void initState() {
    super.initState();
    controller = ChatController(
      ref.read(messageRepositoryProvider),
      ownerId: widget.ownerId,
      sessionUnitId: widget.sessionUnitId,
    )..loadMore();
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
            title: Text(widget.title, overflow: TextOverflow.ellipsis),
            actions: <Widget>[
              IconButton(onPressed: () {}, icon: const Icon(Icons.more_horiz)),
            ],
          ),
          body: Column(
            children: <Widget>[
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification.metrics.extentAfter < 180) {
                      controller.loadMore();
                    }
                    return false;
                  },
                  child: ListView.builder(
                    reverse: true,
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
                            onPressed: controller.loadMore,
                            child: Text('加载失败，点击重试：${controller.error}'),
                          );
                        }
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              controller.hasMore ? '加载更多消息' : '美好生活从这里开始',
                            ),
                          ),
                        );
                      }
                      final message = controller.messages[index];
                      final older =
                          index + 1 < controller.messages.length
                              ? controller.messages[index + 1]
                              : null;
                      return _MessageRow(
                        message: message,
                        showTime: _showTime(message, older),
                      );
                    },
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
    if (current.createdAt == null || older?.createdAt == null) {
      return older == null;
    }
    return current.createdAt!.difference(older!.createdAt!).abs() >
        const Duration(minutes: 5);
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({required this.message, required this.showTime});
  final ChatMessage message;
  final bool showTime;

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
      5 => '[文件]',
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
        Align(
          alignment:
              message.isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (message.isMine && message.state == 'failed')
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.error, color: Colors.red, size: 18),
                ),
              Flexible(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color:
                        message.isMine
                            ? Theme.of(context).colorScheme.primaryContainer
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
                    child: Text(text),
                  ),
                ),
              ),
            ],
          ),
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
            onPressed: () {},
            icon: const Icon(Icons.add_circle_outline),
          ),
          FilledButton(
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
