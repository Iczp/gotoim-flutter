import 'package:flutter/material.dart';

import '../../../../core/widgets/floating_popover.dart';
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
    this.transientItems = const <Widget>[],
    required this.scrollController,
    required this.isLoading,
    required this.hasMore,
    required this.error,
    required this.onViewingLatestChanged,
    required this.onLoadMore,
    required this.onTapOutside,
    required this.itemBuilder,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
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
  final EdgeInsetsGeometry padding;

  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList> {
  final Set<String> _knownLocalIds = <String>{};
  final Set<String> _animatingLocalIds = <String>{};
  bool _isInitialLoaded = false;

  @override
  void initState() {
    super.initState();
    _seedInitialMessages();
  }

  @override
  void didUpdateWidget(covariant ChatMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isInitialLoaded) {
      _seedInitialMessages();
      return;
    }
    // 识别新收/发送的新消息：仅对列表头部（最新端）新增的未知消息启用滑入动画
    if (widget.messages.isNotEmpty && oldWidget.messages.isNotEmpty) {
      for (var i = 0; i < widget.messages.length; i++) {
        final message = widget.messages[i];
        if (_knownLocalIds.contains(message.localId)) {
          // 遇到已认识的消息，说明头部新增的新消息已全部检索完毕
          break;
        }
        // 标记此新消息播放入场动画
        _animatingLocalIds.add(message.localId);
      }
    }
    // 将所有新消息 ID 记入已知集合
    for (final message in widget.messages) {
      _knownLocalIds.add(message.localId);
    }
  }

  void _seedInitialMessages() {
    if (widget.messages.isNotEmpty) {
      for (final message in widget.messages) {
        _knownLocalIds.add(message.localId);
      }
      _isInitialLoaded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        FloatingPopover.hideAll();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: widget.onTapOutside,
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollUpdateNotification ||
                notification is UserScrollNotification ||
                notification is OverscrollNotification) {
              FloatingPopover.hideAll();
            }
            widget.onViewingLatestChanged(notification.metrics.pixels <= 32);
            // In reverse: true ListView, older history is at maxScrollExtent (extentAfter -> 0).
            // Trigger loading earlier (300px threshold) without requiring active finger drag
            // so fling/momentum scrolling loads smoothly.
            if (widget.hasMore &&
                !widget.isLoading &&
                widget.error == null &&
                notification.metrics.extentAfter < 300) {
              widget.onLoadMore();
            }
            return false;
          },
          child:
              widget.messages.isEmpty && widget.transientItems.isEmpty
                  ? _EmptyMessagesState(
                    isLoading: widget.isLoading,
                    error: widget.error,
                    onRetry: widget.onLoadMore,
                  )
                  : Align(
                    alignment: Alignment.topCenter,
                    child: RawScrollbar(
                      controller: widget.scrollController,
                      thumbVisibility: false, // 仅在手指拖拽/滑动时显现，停止后自动淡出
                      thumbColor:
                          isDark
                              ? Colors.white.withValues(alpha: 0.28)
                              : Colors.black.withValues(alpha: 0.22),
                      thickness: 3.0, // 极细 3px
                      radius: const Radius.circular(2),
                      fadeDuration: const Duration(milliseconds: 250),
                      timeToFade: const Duration(milliseconds: 800),
                      interactive: false, // 纯指示条，不干扰气泡长按或手势
                      child: ListView.builder(
                        controller: widget.scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.manual,
                        reverse: true,
                        shrinkWrap: true,
                        findChildIndexCallback: (key) {
                          if (key is! ValueKey<String>) return null;
                          final index = widget.messages.indexWhere(
                            (message) => message.localId == key.value,
                          );
                          return index < 0
                              ? null
                              : widget.transientItems.length + index;
                        },
                        padding: widget.padding,
                        itemCount:
                            widget.transientItems.length +
                            widget.messages.length +
                            1,
                        itemBuilder: (context, index) {
                          if (index < widget.transientItems.length) {
                            return widget.transientItems[index];
                          }
                          final messageIndex =
                              index - widget.transientItems.length;
                          if (messageIndex == widget.messages.length) {
                            return _ChatHistoryFooter(
                              isLoading: widget.isLoading,
                              hasMore: widget.hasMore,
                              error: widget.error,
                              onLoadMore: widget.onLoadMore,
                            );
                          }
                          final message = widget.messages[messageIndex];
                          final shouldAnimate = _animatingLocalIds.contains(
                            message.localId,
                          );
                          return _MessageEntryTransition(
                            key: ValueKey<String>(message.localId),
                            animate: shouldAnimate,
                            onAnimationEnd: () {
                              _animatingLocalIds.remove(message.localId);
                            },
                            child: widget.itemBuilder(
                              context,
                              message,
                              messageIndex,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
        ),
      ),
    );
  }
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

class _ChatHistoryFooter extends StatefulWidget {
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
  State<_ChatHistoryFooter> createState() => _ChatHistoryFooterState();
}

class _ChatHistoryFooterState extends State<_ChatHistoryFooter> {
  @override
  void initState() {
    super.initState();
    _checkAutoLoad();
  }

  @override
  void didUpdateWidget(covariant _ChatHistoryFooter oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkAutoLoad();
  }

  void _checkAutoLoad() {
    if (widget.hasMore && !widget.isLoading && widget.error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            widget.hasMore &&
            !widget.isLoading &&
            widget.error == null) {
          widget.onLoadMore();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading || (widget.hasMore && widget.error == null)) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (widget.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: TextButton.icon(
            onPressed: widget.onLoadMore,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: Text('加载失败，点击重试：${widget.error}'),
          ),
        ),
      );
    }
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          '美好生活从这里开始',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ),
    );
  }
}

/// 消息入场过渡组件：
/// 1. 对于初次加载的历史消息（[animate] 为 false），直接静态呈现，避免整屏消息抖动；
/// 2. 对于新收或新发送的消息（[animate] 为 true），配合高度平滑展开、向上滑入位移与透明度淡入，
///    实现自然流畅的新消息涌入视觉效果。
class _MessageEntryTransition extends StatefulWidget {
  const _MessageEntryTransition({
    required this.child,
    this.animate = false,
    this.onAnimationEnd,
    super.key,
  });

  final Widget child;
  final bool animate;
  final VoidCallback? onAnimationEnd;

  @override
  State<_MessageEntryTransition> createState() =>
      _MessageEntryTransitionState();
}

class _MessageEntryTransitionState extends State<_MessageEntryTransition>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _curvedAnimation;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      final controller = AnimationController(
        duration: const Duration(milliseconds: 260),
        vsync: this,
      );
      _curvedAnimation = CurvedAnimation(
        parent: controller,
        curve: Curves.easeOutCubic,
      );
      _controller = controller;
      controller.forward().then((_) {
        if (mounted) {
          widget.onAnimationEnd?.call();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate || _controller == null || _curvedAnimation == null) {
      return widget.child;
    }

    final animation = _curvedAnimation!;
    return SizeTransition(
      sizeFactor: animation,
      alignment: Alignment.bottomCenter, // 在 reverse 列表中向底部对齐展开
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.22), // 从下方 22% 处平滑向上滑入
          end: Offset.zero,
        ).animate(animation),
        child: FadeTransition(
          opacity: animation,
          child: widget.child,
        ),
      ),
    );
  }
}
