import 'package:flutter/material.dart';

import '../../../../core/widgets/floating_popover.dart';
import '../../data/models/chat_message.dart';

typedef ChatMessageItemBuilder =
    Widget Function(BuildContext context, ChatMessage message, int index);

/// Owns message-list layout, paging gestures, and its loading states.
///
/// The caller supplies item rendering and behavior callbacks so the list stays
/// presentational and does not depend on the chat controller.
class ChatMessageList extends StatelessWidget {
  const ChatMessageList({
    required this.messages,
    this.transientItems = const <Widget>[],
    required this.scrollController,
    required this.isLoading,
    required this.hasMore,
    required this.error,
    required this.onViewingLatestChanged,
    required this.onLoadMore,
    required this.onTapOutside,
    required this.itemBuilder,
    super.key,
  });

  final List<ChatMessage> messages;
  final List<Widget> transientItems;
  final ScrollController scrollController;
  final bool isLoading;
  final bool hasMore;
  final Object? error;
  final ValueChanged<bool> onViewingLatestChanged;
  final Future<void> Function() onLoadMore;
  final VoidCallback onTapOutside;
  final ChatMessageItemBuilder itemBuilder;

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    // A listener observes pointer input without joining Flutter's gesture
    // arena. This keeps the surrounding chat region from competing with the
    // ListView's vertical-drag recognizer.
    onPointerDown: (_) {
      FloatingPopover.hideAll();
      onTapOutside();
    },
    child: NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification ||
            notification is UserScrollNotification ||
            notification is OverscrollNotification) {
          FloatingPopover.hideAll();
        }
        onViewingLatestChanged(notification.metrics.pixels <= 32);
        final isUserPaging =
            (notification is ScrollUpdateNotification &&
                notification.dragDetails != null) ||
            notification is OverscrollNotification;
        if (isUserPaging && notification.metrics.extentAfter < 180) {
          onLoadMore();
        }
        return false;
      },
      child:
          messages.isEmpty && transientItems.isEmpty
              ? _EmptyMessagesState(
                isLoading: isLoading,
                error: error,
                onRetry: onLoadMore,
              )
              : Align(
                alignment: Alignment.topCenter,
                child: ListView.builder(
                  controller: scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  reverse: true,
                  shrinkWrap: true,
                  findChildIndexCallback: (key) {
                    if (key is! ValueKey<String>) return null;
                    final index = messages.indexWhere(
                      (message) => message.localId == key.value,
                    );
                    return index < 0 ? null : index;
                  },
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 16,
                  ),
                  itemCount: transientItems.length + messages.length + 1,
                  itemBuilder: (context, index) {
                    if (index < transientItems.length) {
                      return transientItems[index];
                    }
                    final messageIndex = index - transientItems.length;
                    if (messageIndex == messages.length) {
                      return _ChatHistoryFooter(
                        isLoading: isLoading,
                        hasMore: hasMore,
                        error: error,
                        onLoadMore: onLoadMore,
                      );
                    }
                    final message = messages[messageIndex];
                    return itemBuilder(context, message, messageIndex);
                  },
                ),
              ),
    ),
  );
}

class _EmptyMessagesState extends StatelessWidget {
  const _EmptyMessagesState({
    required this.isLoading,
    required this.error,
    required this.onRetry,
  });

  final bool isLoading;
  final Object? error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Center(
        child: TextButton(
          onPressed: onRetry,
          child: Text('消息加载失败，点击重试：$error'),
        ),
      );
    }
    return const Center(child: Text('暂无消息'));
  }
}

class _ChatHistoryFooter extends StatelessWidget {
  const _ChatHistoryFooter({
    required this.isLoading,
    required this.hasMore,
    required this.error,
    required this.onLoadMore,
  });

  final bool isLoading;
  final bool hasMore;
  final Object? error;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (error != null) {
      return TextButton(onPressed: onLoadMore, child: Text('加载失败，点击重试：$error'));
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child:
            hasMore
                ? TextButton(onPressed: onLoadMore, child: const Text('加载更多消息'))
                : const Text('美好生活从这里开始'),
      ),
    );
  }
}
