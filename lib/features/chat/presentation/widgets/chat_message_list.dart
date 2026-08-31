import 'package:flutter/material.dart';

import '../../data/models/chat_message.dart';

typedef ChatMessageItemBuilder =
    Widget Function(BuildContext context, ChatMessage message, int index);

/// Owns message-list layout, paging gestures, and its loading states.
///
/// The caller supplies item rendering and behavior callbacks so the list stays
/// presentational and does not depend on the chat controller.
class ChatMessageList extends StatefulWidget {
  const ChatMessageList({
    required this.messages,
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
  final ScrollController scrollController;
  final bool isLoading;
  final bool hasMore;
  final Object? error;
  final ValueChanged<bool> onViewingLatestChanged;
  final Future<void> Function() onLoadMore;
  final VoidCallback onTapOutside;
  final ChatMessageItemBuilder itemBuilder;

  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList> {
  static const _listVerticalPadding = 32.0;
  final Map<String, GlobalKey> _contentKeys = <String, GlobalKey>{};
  double _viewportHeight = 0;
  double _bottomSpacerHeight = 0;
  bool _measurementScheduled = false;

  GlobalKey _contentKeyFor(String id) =>
      _contentKeys.putIfAbsent(id, GlobalKey.new);

  void _scheduleBottomSpacerMeasurement() {
    if (_measurementScheduled) return;
    _measurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementScheduled = false;
      if (!mounted || _viewportHeight <= 0) return;

      final keys = <GlobalKey>[
        _contentKeyFor('_history_footer'),
        ...widget.messages.map((message) => _contentKeyFor(message.localId)),
      ];
      final renderBoxes = keys
          .map((key) => key.currentContext?.findRenderObject() as RenderBox?)
          .toList(growable: false);
      // If any item is not built, the list exceeds the viewport. Do not add a
      // spacer so the normal lazy ListView behavior remains unchanged.
      if (renderBoxes.any((renderBox) => renderBox == null)) {
        _setBottomSpacerHeight(0);
        return;
      }
      final contentHeight = renderBoxes.fold<double>(
        0,
        (total, renderBox) => total + renderBox!.size.height,
      );
      _setBottomSpacerHeight(
        (_viewportHeight - _listVerticalPadding - contentHeight).clamp(
          0,
          double.infinity,
        ),
      );
    });
  }

  void _setBottomSpacerHeight(double value) {
    if ((value - _bottomSpacerHeight).abs() < 0.5) return;
    setState(() => _bottomSpacerHeight = value);
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    // A listener observes pointer input without joining Flutter's gesture
    // arena. This keeps the surrounding chat region from competing with the
    // ListView's vertical-drag recognizer.
    onPointerDown: (_) => widget.onTapOutside(),
    child: LayoutBuilder(
      builder: (context, constraints) {
        _viewportHeight = constraints.maxHeight;
        _scheduleBottomSpacerMeasurement();
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            widget.onViewingLatestChanged(notification.metrics.pixels <= 32);
            final isUserPaging =
                (notification is ScrollUpdateNotification &&
                    notification.dragDetails != null) ||
                notification is OverscrollNotification;
            if (isUserPaging && notification.metrics.extentAfter < 180) {
              widget.onLoadMore();
            }
            return false;
          },
          child:
              widget.messages.isEmpty
                  ? _EmptyMessagesState(
                    isLoading: widget.isLoading,
                    error: widget.error,
                    onRetry: widget.onLoadMore,
                  )
                  : ListView.builder(
                    controller: widget.scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    reverse: true,
                    findChildIndexCallback: (key) {
                      if (key is! ValueKey<String>) return null;
                      final index = widget.messages.indexWhere(
                        (message) => message.localId == key.value,
                      );
                      return index < 0 ? null : index + 1;
                    },
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 16,
                    ),
                    itemCount: widget.messages.length + 2,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return SizedBox(height: _bottomSpacerHeight);
                      }
                      if (index == widget.messages.length + 1) {
                        return KeyedSubtree(
                          key: _contentKeyFor('_history_footer'),
                          child: _ChatHistoryFooter(
                            isLoading: widget.isLoading,
                            hasMore: widget.hasMore,
                            error: widget.error,
                            onLoadMore: widget.onLoadMore,
                          ),
                        );
                      }
                      final messageIndex = index - 1;
                      final message = widget.messages[messageIndex];
                      return KeyedSubtree(
                        key: _contentKeyFor(message.localId),
                        child: widget.itemBuilder(
                          context,
                          message,
                          messageIndex,
                        ),
                      );
                    },
                  ),
        );
      },
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
