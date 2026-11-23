import 'package:flutter/material.dart';

import '../application/session_list_controller.dart';

/// 会话分类 Tab 配置项。
class SessionTabItem {
  const SessionTabItem({required this.key, required this.label});

  final SessionTabKey key;
  final String label;
}

/// 全部会话分类 Tab 定义（对齐 Electron `SessionList.vue`）。
const List<SessionTabItem> kSessionCategoryTabs = <SessionTabItem>[
  SessionTabItem(key: SessionTabKey.all, label: '全部'),
  SessionTabItem(key: SessionTabKey.direct, label: '单聊'),
  SessionTabItem(key: SessionTabKey.room, label: '群聊'),
  SessionTabItem(key: SessionTabKey.square, label: '广场'),
  SessionTabItem(key: SessionTabKey.subscription, label: '订阅号'),
  SessionTabItem(key: SessionTabKey.official, label: '服务号'),
  SessionTabItem(key: SessionTabKey.robot, label: '机器人'),
  SessionTabItem(key: SessionTabKey.customer, label: '客服商户'),
];

/// 按容器可用宽度动态拆分可见 Tab 与折叠至“更多”菜单的 Tab，并汇总被隐藏 Tab 的未读角标总和。
({
  List<SessionTabItem> visible,
  List<SessionTabItem> overflow,
  int overflowUnread,
})
splitSessionCategoryTabs({
  required double availableWidth,
  required Map<SessionTabKey, int> unreadCounts,
  required double Function(SessionTabItem item, int unread) measureTabWidth,
  required double Function(int overflowUnread) measureMoreWidth,
  double gap = 4.0,
}) {
  if (!availableWidth.isFinite || availableWidth <= 0) {
    final visible = kSessionCategoryTabs.take(3).toList(growable: false);
    final overflow = kSessionCategoryTabs.skip(3).toList(growable: false);
    final overflowUnread = overflow.fold<int>(
      0,
      (sum, item) => sum + (unreadCounts[item.key] ?? 0),
    );
    return (visible: visible, overflow: overflow, overflowUnread: overflowUnread);
  }

  var totalAllWidth = 0.0;
  for (var i = 0; i < kSessionCategoryTabs.length; i++) {
    final item = kSessionCategoryTabs[i];
    final unread = unreadCounts[item.key] ?? 0;
    totalAllWidth += measureTabWidth(item, unread) + (i > 0 ? gap : 0);
  }
  if (totalAllWidth <= availableWidth) {
    return (
      visible: kSessionCategoryTabs,
      overflow: const <SessionTabItem>[],
      overflowUnread: 0,
    );
  }

  // 两遍收敛：先按全部隐藏角标保守预留“更多”宽度，再按实际隐藏集合重算一次，避免边缘抖动。
  var totalUnreadHint = 0;
  for (var i = 1; i < kSessionCategoryTabs.length; i++) {
    totalUnreadHint += unreadCounts[kSessionCategoryTabs[i].key] ?? 0;
  }

  ({
    List<SessionTabItem> visible,
    List<SessionTabItem> overflow,
    int overflowUnread,
  })
  splitWithMoreWidth(double moreWidth) {
    final budget = (availableWidth - moreWidth - gap).clamp(0.0, availableWidth);
    final visible = <SessionTabItem>[];
    final overflow = <SessionTabItem>[];
    var used = 0.0;
    var overflowed = false;

    for (var i = 0; i < kSessionCategoryTabs.length; i++) {
      final item = kSessionCategoryTabs[i];
      final unread = unreadCounts[item.key] ?? 0;
      final itemWidth = measureTabWidth(item, unread) + (i > 0 ? gap : 0);
      if (!overflowed && (i == 0 || used + itemWidth <= budget)) {
        visible.add(item);
        used += itemWidth;
      } else {
        overflowed = true;
        overflow.add(item);
      }
    }

    final overflowUnread = overflow.fold<int>(
      0,
      (sum, item) => sum + (unreadCounts[item.key] ?? 0),
    );
    return (
      visible: visible,
      overflow: overflow,
      overflowUnread: overflowUnread,
    );
  }

  final firstPass = splitWithMoreWidth(measureMoreWidth(totalUnreadHint));
  final exactMoreWidth = measureMoreWidth(firstPass.overflowUnread);
  return splitWithMoreWidth(exactMoreWidth);
}

/// 自适应宽度的会话分类 Tab 栏：
/// 1. 自动测量宽度，无横向滚动条；
/// 2. 溢出项自动折叠至“更多 v”下拉菜单；
/// 3. “更多”按钮角标精准等于所有被隐藏 Tab 的未读角标总和。
class SessionCategoryTabs extends StatelessWidget {
  const SessionCategoryTabs({
    required this.activeTab,
    required this.tabUnreadCounts,
    required this.onSelectTab,
    this.onDoubleTapTab,
    super.key,
  });

  final SessionTabKey activeTab;
  final Map<SessionTabKey, int> tabUnreadCounts;
  final ValueChanged<SessionTabKey> onSelectTab;
  final ValueChanged<SessionTabKey>? onDoubleTapTab;

  static const double _tabGap = 4.0;
  static const double _horizontalPadding = 10.0;

  double _measureTextWidth(
    BuildContext context,
    String text,
    TextStyle style,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    return painter.width.ceilToDouble();
  }

  double _measureBadgeWidth(BuildContext context, int unread) {
    if (unread <= 0) return 0;
    final label = unread > 99 ? '99+' : '$unread';
    final textW = _measureTextWidth(
      context,
      label,
      const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, height: 1.0),
    );
    return 4.0 + (textW + 8.0).clamp(16.0, 44.0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    final borderColor =
        isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.06);

    const labelStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      height: 1.2,
    );

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: _horizontalPadding,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor, width: 0.6)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth =
              constraints.maxWidth.isFinite ? constraints.maxWidth : 280.0;

          double measureTab(SessionTabItem item, int unread) {
            final textW = _measureTextWidth(context, item.label, labelStyle);
            final badgeW = _measureBadgeWidth(context, unread);
            return textW + 16.0 + badgeW + 2.0; // 左右 padding 各 8 + 2px 容差
          }

          SessionTabItem? activeOverflowCandidate;
          double measureMore(int overflowUnread) {
            final moreLabel = activeOverflowCandidate?.label ?? '更多';
            final textW = _measureTextWidth(context, moreLabel, labelStyle);
            final badgeW = _measureBadgeWidth(context, overflowUnread);
            return textW + 16.0 + 16.0 + badgeW + 4.0; // 含下拉箭头 14 + 间距
          }

          var split = splitSessionCategoryTabs(
            availableWidth: availableWidth,
            unreadCounts: tabUnreadCounts,
            measureTabWidth: measureTab,
            measureMoreWidth: measureMore,
            gap: _tabGap,
          );

          final activeOverflow =
              split.overflow.where((t) => t.key == activeTab).firstOrNull;
          if (activeOverflow != null && activeOverflow.label != '更多') {
            activeOverflowCandidate = activeOverflow;
            split = splitSessionCategoryTabs(
              availableWidth: availableWidth,
              unreadCounts: tabUnreadCounts,
              measureTabWidth: measureTab,
              measureMoreWidth: measureMore,
              gap: _tabGap,
            );
          }

          final isMoreActive = split.overflow.any((t) => t.key == activeTab);
          final moreDisplayLabel =
              split.overflow
                  .where((t) => t.key == activeTab)
                  .firstOrNull
                  ?.label ??
              '更多';

          return Row(
            children: [
              for (var i = 0; i < split.visible.length; i++) ...[
                if (i > 0) const SizedBox(width: _tabGap),
                Flexible(
                  fit: FlexFit.loose,
                  child: _TabPillButton(
                    label: split.visible[i].label,
                    unreadCount: tabUnreadCounts[split.visible[i].key] ?? 0,
                    isActive: activeTab == split.visible[i].key,
                    isDark: isDark,
                    colorScheme: colorScheme,
                    onTap: () => onSelectTab(split.visible[i].key),
                    onDoubleTap:
                        onDoubleTapTab == null
                            ? null
                            : () => onDoubleTapTab!(split.visible[i].key),
                  ),
                ),
              ],
              if (split.overflow.isNotEmpty) ...[
                const SizedBox(width: _tabGap),
                _MoreOverflowTabButton(
                  label: moreDisplayLabel,
                  overflowTabs: split.overflow,
                  tabUnreadCounts: tabUnreadCounts,
                  overflowUnreadCount: split.overflowUnread,
                  activeTab: activeTab,
                  isActive: isMoreActive,
                  isDark: isDark,
                  colorScheme: colorScheme,
                  onSelectTab: onSelectTab,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _TabPillButton extends StatelessWidget {
  const _TabPillButton({
    required this.label,
    required this.unreadCount,
    required this.isActive,
    required this.isDark,
    required this.colorScheme,
    required this.onTap,
    this.onDoubleTap,
  });

  final String label;
  final int unreadCount;
  final bool isActive;
  final bool isDark;
  final ColorScheme colorScheme;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final bgColor =
        isActive
            ? colorScheme.primary.withValues(alpha: isDark ? 0.18 : 0.10)
            : Colors.transparent;
    final fgColor =
        isActive ? colorScheme.primary : colorScheme.onSurfaceVariant;

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    color: fgColor,
                    height: 1.2,
                  ),
                ),
              ),
              if (unreadCount > 0) ...[
                const SizedBox(width: 4),
                _TabUnreadBadge(count: unreadCount),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreOverflowTabButton extends StatelessWidget {
  const _MoreOverflowTabButton({
    required this.label,
    required this.overflowTabs,
    required this.tabUnreadCounts,
    required this.overflowUnreadCount,
    required this.activeTab,
    required this.isActive,
    required this.isDark,
    required this.colorScheme,
    required this.onSelectTab,
  });

  final String label;
  final List<SessionTabItem> overflowTabs;
  final Map<SessionTabKey, int> tabUnreadCounts;
  final int overflowUnreadCount;
  final SessionTabKey activeTab;
  final bool isActive;
  final bool isDark;
  final ColorScheme colorScheme;
  final ValueChanged<SessionTabKey> onSelectTab;

  @override
  Widget build(BuildContext context) {
    final bgColor =
        isActive
            ? colorScheme.primary.withValues(alpha: isDark ? 0.18 : 0.10)
            : Colors.transparent;
    final fgColor =
        isActive ? colorScheme.primary : colorScheme.onSurfaceVariant;

    return PopupMenuButton<SessionTabKey>(
      tooltip: '更多会话分类',
      padding: EdgeInsets.zero,
      offset: const Offset(0, 32),
      onSelected: onSelectTab,
      itemBuilder: (context) => [
        for (final tab in overflowTabs)
          PopupMenuItem<SessionTabKey>(
            value: tab.key,
            height: 36,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tab.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          tab.key == activeTab
                              ? FontWeight.w600
                              : FontWeight.w400,
                      color:
                          tab.key == activeTab
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                    ),
                  ),
                ),
                if ((tabUnreadCounts[tab.key] ?? 0) > 0) ...[
                  const SizedBox(width: 8),
                  _TabUnreadBadge(count: tabUnreadCounts[tab.key]!),
                ],
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: fgColor,
                height: 1.2,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: fgColor),
            if (overflowUnreadCount > 0) ...[
              const SizedBox(width: 4),
              _TabUnreadBadge(count: overflowUnreadCount),
            ],
          ],
        ),
      ),
    );
  }
}

class _TabUnreadBadge extends StatelessWidget {
  const _TabUnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final text = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFF4D4F),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          height: 1.0,
        ),
      ),
    );
  }
}
