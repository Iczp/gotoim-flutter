import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/models/chat_message.dart';

/// 消息上下文菜单排版模式。
enum ChatMessageMenuLayoutMode {
  /// 单行模式（一行最多 4 项，超出带“更多”图标）
  singleRow,

  /// 双行模式（默认，每行最多 4 项，两行最多 8 项，超出带“更多”图标）
  doubleRow,
}

/// 消息菜单项定义。
class ChatMessageMenuItem {
  const ChatMessageMenuItem({
    required this.id,
    required this.label,
    required this.icon,
    this.enabled = true,
    this.destructive = false,
    this.onTap,
  });

  final String id;
  final String label;
  final IconData icon;
  final bool enabled;
  final bool destructive;
  final FutureOr<void> Function()? onTap;
}

/// 消息菜单构建上下文。
class ChatMessageMenuContext {
  const ChatMessageMenuContext({
    required this.message,
    this.canRecall = false,
    this.canDelete = true,
    this.canRetry = false,
    this.canSelect = true,
    this.isEarpiece = false,
    this.onAction,
  });

  final ChatMessage message;
  final bool canRecall;
  final bool canDelete;
  final bool canRetry;
  final bool canSelect;
  final bool isEarpiece;
  final FutureOr<void> Function(String id, ChatMessage message)? onAction;
}

/// 消息长按菜单构建器。
class ChatMessageMenuBuilder {
  const ChatMessageMenuBuilder();

  List<ChatMessageMenuItem> build(ChatMessageMenuContext context) {
    final message = context.message;
    // 系统消息不展示菜单
    if (message.messageType == 1) {
      return const [];
    }

    // 撤回的消息只支持删除
    if (message.isRollbacked) {
      return context.canDelete
          ? [
              _item(
                'delete',
                '删除',
                Icons.delete_outline,
                context,
                destructive: true,
              ),
            ]
          : const [];
    }

    // 发送失败的消息支持重试和删除
    if (message.state == 'failed') {
      return [
        if (context.canRetry) _item('retry', '重新发送', Icons.refresh, context),
        if (context.canDelete)
          _item(
            'delete',
            '删除',
            Icons.delete_outline,
            context,
            destructive: true,
          ),
      ];
    }

    // 发送中的消息只支持删除
    if (message.state == 'sending') {
      return context.canDelete
          ? [
              _item(
                'delete',
                '删除',
                Icons.delete_outline,
                context,
                destructive: true,
              ),
            ]
          : const [];
    }

    // 正常状态消息
    final items = <ChatMessageMenuItem>[
      _item('quote', '引用', Icons.format_quote_outlined, context),
      if (message.messageType == 0 && message.text.isNotEmpty) ...[
        _item('copy', '复制', Icons.copy_outlined, context),
        _item('selectText', '选择', Icons.highlight_outlined, context),
      ],
      if (message.messageType == 3) ...[
        if (context.isEarpiece)
          _item('speaker', '扬声器播放', Icons.volume_up_outlined, context)
        else
          _item('earpiece', '听筒播放', Icons.phone_in_talk_outlined, context),
      ],
      if (message.messageType == 4) ...[
        _item('playVideo', '播放', Icons.play_circle_outline, context),
      ],
      _item('forward', '转发', Icons.forward_outlined, context),
      if (context.canSelect)
        _item('select', '多选', Icons.checklist_outlined, context),
    ];

    if (message.isMine && context.canRecall) {
      items.add(_item('recall', '撤回', Icons.undo_outlined, context));
    }

    if (context.canDelete) {
      items.add(
        _item('delete', '删除', Icons.delete_outline, context, destructive: true),
      );
    }

    return items;
  }

  ChatMessageMenuItem _item(
    String id,
    String label,
    IconData icon,
    ChatMessageMenuContext context, {
    bool destructive = false,
  }) =>
      ChatMessageMenuItem(
        id: id,
        label: label,
        icon: icon,
        destructive: destructive,
        onTap: () => context.onAction?.call(id, context.message),
      );
}

/// 消息长按浮层菜单组件。
///
/// 规格特性：
/// 1. 每行 4 个项；
/// 2. 菜单排版：上方图标，下方文字（换行）；
/// 3. 支持单行与双行排版（默认双行 `doubleRow`）；
/// 4. 超过展示上限时，最后一项自动变为“更多”图标，点击切换展示剩余菜单项。
class ChatMessageMenu extends StatefulWidget {
  const ChatMessageMenu({
    required this.items,
    this.layoutMode = ChatMessageMenuLayoutMode.doubleRow,
    this.itemsPerRow = 4,
    super.key,
  });

  final List<ChatMessageMenuItem> items;
  final ChatMessageMenuLayoutMode layoutMode;
  final int itemsPerRow;

  @override
  State<ChatMessageMenu> createState() => _ChatMessageMenuState();
}

class _ChatMessageMenuState extends State<ChatMessageMenu> {
  int _pageIndex = 0;

  int get _maxItemsPerPage =>
      widget.layoutMode == ChatMessageMenuLayoutMode.doubleRow
          ? widget.itemsPerRow * 2
          : widget.itemsPerRow;

  List<List<ChatMessageMenuItem>> get _pages {
    final maxPer = _maxItemsPerPage;
    if (widget.items.length <= maxPer) {
      return [widget.items];
    }

    // 分页：第一页放 maxPer - 1 个，最后一个放“更多”；第二页放剩余的（如果还有超出则继续）
    final pageSize = maxPer - 1;
    final List<List<ChatMessageMenuItem>> pages = [];
    for (var i = 0; i < widget.items.length; i += pageSize) {
      final end = (i + pageSize < widget.items.length)
          ? i + pageSize
          : widget.items.length;
      pages.add(widget.items.sublist(i, end));
    }
    return pages;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final pages = _pages;
    final currentPageItems = pages[_pageIndex.clamp(0, pages.length - 1)];
    final hasNextPage = _pageIndex < pages.length - 1;
    final hasPrevPage = _pageIndex > 0;

    // 组装当前页渲染项目
    final List<Widget> tiles = [];

    // 如果在第二页或之后，第一项提供“返回”
    if (hasPrevPage) {
      tiles.add(
        _MenuItemTile(
          item: ChatMessageMenuItem(
            id: '__back__',
            label: '返回',
            icon: Icons.arrow_back,
            onTap: () => setState(() => _pageIndex--),
          ),
        ),
      );
    }

    // 渲染常规菜单项
    for (final item in currentPageItems) {
      tiles.add(_MenuItemTile(item: item));
    }

    // 如果有下一页，最后一项追加“更多”
    if (hasNextPage) {
      tiles.add(
        _MenuItemTile(
          item: ChatMessageMenuItem(
            id: '__more__',
            label: '更多',
            icon: Icons.more_horiz,
            onTap: () => setState(() => _pageIndex++),
          ),
        ),
      );
    }

    // 按每行 4 个分行
    final List<Widget> rows = [];
    for (var i = 0; i < tiles.length; i += widget.itemsPerRow) {
      final end = (i + widget.itemsPerRow < tiles.length)
          ? i + widget.itemsPerRow
          : tiles.length;
      final rowChildren = tiles.sublist(i, end);

      rows.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.start,
          children: rowChildren,
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          color: isDark
              ? theme.colorScheme.surfaceContainerHighest
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.dividerColor.withValues(alpha: 0.15),
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows,
        ),
      ),
    );
  }
}

/// 单个图标在上、文字在下的菜单按钮。
class _MenuItemTile extends StatelessWidget {
  const _MenuItemTile({required this.item});

  final ChatMessageMenuItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = item.destructive
        ? theme.colorScheme.error
        : (item.enabled
            ? theme.colorScheme.onSurface
            : theme.disabledColor);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: item.enabled
            ? () {
                HapticFeedback.lightImpact();
                item.onTap?.call();
              }
            : null,
        child: Container(
          width: 56,
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                item.icon,
                size: 20,
                color: color,
              ),
              const SizedBox(height: 4),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
