import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/browser/desktop_browser_dock_controller.dart';
import '../../../core/browser/desktop_browser_window.dart';
import '../../../core/services/window_service.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/desktop_dialog.dart';
import '../../chat/presentation/chat_page.dart';
import '../../chat_settings/presentation/chat_settings_page.dart';
import '../../contact/presentation/add_friend_page.dart';
import '../../group/presentation/create_group_page.dart';
import '../../mine/presentation/my_qr_code_dialog.dart';
import '../application/session_list_controller.dart';
import '../data/models/session_summary.dart';
import 'desktop_chat_owner_popover.dart';
import 'session_list_item.dart';
import 'session_menu.dart';
import 'signalr_status_bar.dart';

class SelectedDesktopSessionUnitIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void select(String? id) => state = id;
}

/// 全局可访问的桌面端当前选中会话 ID Provider，供通讯录、全局搜索等模块联动跳转聊天
final selectedDesktopSessionUnitIdProvider =
    NotifierProvider<SelectedDesktopSessionUnitIdNotifier, String?>(
      SelectedDesktopSessionUnitIdNotifier.new,
    );

/// 桌面端分栏会话界面 (DesktopSessionSplitView)
///
/// 核心结构：
/// 1. 左列（290px，可拖拽调节宽度）：当前身份切换胶囊、搜索栏、与移动端完全一致的置顶/时间分组会话列表；
/// 2. 右列（自适应）：所选中会话的 [ChatPage] 嵌入渲染，未选会话时展示空状态水印；
/// 3. 支持单击选中右侧展示、双击唤起独立窗口、右键桌面上下文操作菜单。
class DesktopSessionSplitView extends ConsumerStatefulWidget {
  const DesktopSessionSplitView({required this.controller, super.key});

  final SessionListController controller;

  @override
  ConsumerState<DesktopSessionSplitView> createState() =>
      _DesktopSessionSplitViewState();
}

class _CachedDesktopChat {
  final String sessionUnitId;
  String title;
  final int ownerId;
  DateTime lastAccessTime;

  _CachedDesktopChat({
    required this.sessionUnitId,
    required this.title,
    required this.ownerId,
    required this.lastAccessTime,
  });
}

class _DesktopSessionSplitViewState
    extends ConsumerState<DesktopSessionSplitView> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final Map<String, _CachedDesktopChat> _cachedChats = {};
  static const int _maxCachedChats = 6;

  String? _selectedSessionUnitId;
  String? _selectedTitle;
  int? _activeOwnerId;
  String _searchKeyword = '';
  double _sessionPaneWidth = 290.0;
  double _browserPaneWidth = 520.0;
  bool _isDraggingBrowserDivider = false;
  Timer? _avatarHoverTimer;
  Timer? _avatarLeaveTimer;
  OverlayEntry? _contextMenuEntry;

  void _dismissContextMenu() {
    _contextMenuEntry?.remove();
    _contextMenuEntry = null;
  }

  final GlobalKey _browserPlaceholderKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _browserPaneWidth = ref.read(desktopBrowserDockProvider).width;
    _scrollController.addListener(_onScroll);
    _selectedSessionUnitId = ref.read(selectedDesktopSessionUnitIdProvider);
    if (_selectedSessionUnitId != null) {
      final ownerId = widget.controller.currentOwner?.id ?? 0;
      _touchCachedChat(_selectedSessionUnitId!, '聊天', ownerId);
    }
    Future<void>.microtask(() {
      if (mounted) {
        widget.controller.initialize();
      }
    });
  }

  void _touchCachedChat(String sessionUnitId, String title, int ownerId) {
    if (_cachedChats.containsKey(sessionUnitId)) {
      final existing = _cachedChats[sessionUnitId]!;
      existing.lastAccessTime = DateTime.now();
      if (title.isNotEmpty && title != '聊天') {
        existing.title = title;
      }
    } else {
      if (_cachedChats.length >= _maxCachedChats) {
        String? lruKey;
        DateTime? oldestTime;
        for (final entry in _cachedChats.entries) {
          if (entry.key == _selectedSessionUnitId) continue;
          if (oldestTime == null ||
              entry.value.lastAccessTime.isBefore(oldestTime)) {
            oldestTime = entry.value.lastAccessTime;
            lruKey = entry.key;
          }
        }
        lruKey ??= _cachedChats.keys.first;
        _cachedChats.remove(lruKey);
      }
      _cachedChats[sessionUnitId] = _CachedDesktopChat(
        sessionUnitId: sessionUnitId,
        title: title,
        ownerId: ownerId,
        lastAccessTime: DateTime.now(),
      );
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.extentAfter < 200 &&
        widget.controller.hasMore &&
        !widget.controller.isLoading) {
      widget.controller.loadNextPage();
    }
  }

  @override
  void didUpdateWidget(DesktopSessionSplitView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller.currentOwner?.id !=
        widget.controller.currentOwner?.id) {
      _cachedChats.clear();
      setState(() {
        _selectedSessionUnitId = null;
        _selectedTitle = null;
      });
      ref.read(selectedDesktopSessionUnitIdProvider.notifier).select(null);
    }
  }

  @override
  void dispose() {
    _dismissContextMenu();
    _avatarHoverTimer?.cancel();
    _avatarLeaveTimer?.cancel();
    _cachedChats.clear();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onAvatarHover(Rect rect, SessionSummary session) {
    if (kIsWeb ||
        (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux)) {
      return;
    }
    _avatarLeaveTimer?.cancel();
    _avatarHoverTimer?.cancel();
    _avatarHoverTimer = Timer(const Duration(milliseconds: 300), () {
      final raw = session.raw;
      final destination =
          (raw['destination'] as Map?)?.cast<String, dynamic>() ?? {};
      final subjectData = {
        'id': session.destinationId?.toString() ?? session.id,
        'displayName':
            destination['displayName'] ?? destination['name'] ?? session.title,
        'name': destination['name'] ?? session.title,
        'thumbnail': destination['thumbnail'] ?? destination['portrait'],
        'portrait': destination['portrait'],
        'gender': destination['gender'],
        'statusText': destination['statusText'],
        'code': destination['code'],
      };
      ref
          .read(windowServiceProvider)
          .showProfileCardAt(subjectData: subjectData, localRect: rect);
    });
  }

  void _onAvatarLeave() {
    if (kIsWeb ||
        (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux)) {
      return;
    }
    _avatarHoverTimer?.cancel();
    _avatarLeaveTimer?.cancel();
    _avatarLeaveTimer = Timer(const Duration(milliseconds: 200), () {
      ref.read(windowServiceProvider).hideProfileCard();
    });
  }

  void _selectSession(SessionSummary session) {
    _dismissContextMenu();
    final ownerId = widget.controller.currentOwner?.id ?? 0;
    _touchCachedChat(session.id, session.title, ownerId);
    setState(() {
      _selectedSessionUnitId = session.id;
      _selectedTitle = session.title;
    });
    ref.read(selectedDesktopSessionUnitIdProvider.notifier).select(session.id);
  }

  void _openInStandaloneWindow(SessionSummary session) {
    final ownerId = widget.controller.currentOwner?.id;
    ref
        .read(windowServiceProvider)
        .openChat(
          sessionUnitId: session.id,
          ownerId: ownerId,
          title: session.title,
        );
  }

  void _showSessionContextMenu(TapDownDetails details, SessionSummary session) {
    _dismissContextMenu();
    final overlay = Overlay.of(context);
    final renderBox = overlay.context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final screenSize = renderBox.size;
    const double menuWidth = 160.0;
    const double menuEstimatedHeight = 220.0;

    double left = details.globalPosition.dx;
    double top = details.globalPosition.dy;

    if (left + menuWidth > screenSize.width - 8) {
      left = (screenSize.width - menuWidth - 8).clamp(8.0, screenSize.width);
    }
    if (top + menuEstimatedHeight > screenSize.height - 8) {
      top = (screenSize.height - menuEstimatedHeight - 8).clamp(
        8.0,
        screenSize.height,
      );
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    _contextMenuEntry = OverlayEntry(
      builder: (ctx) {
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: TapRegion(
                groupId: 'desktop_session_context_menu',
                onTapOutside: (_) => _dismissContextMenu(),
                child: Material(
                  elevation: 8,
                  shadowColor: Colors.black.withValues(
                    alpha: isDark ? 0.6 : 0.25,
                  ),
                  color: colorScheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color:
                          isDark
                              ? Colors.white.withValues(alpha: 0.12)
                              : colorScheme.outlineVariant.withValues(
                                alpha: 0.5,
                              ),
                      width: 0.8,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    width: menuWidth,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildContextMenuItem(
                          icon: Icons.open_in_new_rounded,
                          label: '在独立窗口打开',
                          onTap: () {
                            _dismissContextMenu();
                            _openInStandaloneWindow(session);
                          },
                        ),
                        Divider(
                          height: 8,
                          thickness: 0.5,
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.35,
                          ),
                        ),
                        _buildContextMenuItem(
                          icon:
                              session.isPinned
                                  ? Icons.push_pin_outlined
                                  : Icons.push_pin_rounded,
                          label: session.isPinned ? '取消置顶' : '置顶聊天',
                          onTap: () async {
                            _dismissContextMenu();
                            await _handleTopping(session);
                          },
                        ),
                        _buildContextMenuItem(
                          icon:
                              session.isImmersed
                                  ? Icons.notifications_active_outlined
                                  : Icons.notifications_off_outlined,
                          label: session.isImmersed ? '开启消息通知' : '消息免打扰',
                          onTap: () async {
                            _dismissContextMenu();
                            await _handleImmersed(session);
                          },
                        ),
                        _buildContextMenuItem(
                          icon: Icons.settings_outlined,
                          label: '聊天设置',
                          onTap: () {
                            _dismissContextMenu();
                            _openChatSettings(session);
                          },
                        ),
                        Divider(
                          height: 8,
                          thickness: 0.5,
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.35,
                          ),
                        ),
                        _buildContextMenuItem(
                          icon: Icons.delete_sweep_outlined,
                          label: '清空聊天记录',
                          iconColor: colorScheme.error,
                          textColor: colorScheme.error,
                          onTap: () async {
                            _dismissContextMenu();
                            await _handleClearMessages(session);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_contextMenuEntry!);
  }

  Widget _buildContextMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? iconColor,
    Color? textColor,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: iconColor ?? colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: textColor ?? colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleTopping(SessionSummary session) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.controller.setTopping(session, !session.isPinned);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(session.isPinned ? '已取消置顶' : '已置顶')),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('操作失败：$e')));
      }
    }
  }

  Future<void> _handleImmersed(SessionSummary session) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.controller.setImmersed(session, !session.isImmersed);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(session.isImmersed ? '已开启消息通知' : '已关闭消息通知')),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('操作失败：$e')));
      }
    }
  }

  void _openChatSettings(SessionSummary session) {
    final ownerId = session.ownerId ?? widget.controller.currentOwner?.id ?? 0;
    if (mounted) {
      showDesktopModalDialog<void>(
        context: context,
        title: '聊天设置 - ${session.title}',
        width: 520,
        height: 640,
        child: ChatSettingsPage(
          ownerId: ownerId,
          sessionUnitId: session.id,
          isDrawer: true,
          onClose: () => Navigator.of(context).pop(),
          onMessagesCleared: () {
            ref.read(sessionListControllerProvider).refreshChanges();
          },
        ),
      );
    }
  }

  Future<void> _handleClearMessages(SessionSummary session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('清空聊天记录'),
            content: Text('确定清空“${session.title}”的全部聊天记录吗？'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('清空'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.controller.clearMessages(session);
      if (mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('聊天记录已清空')));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('操作失败：$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    final currentOwner = widget.controller.currentOwner;
    final currentOwnerId = currentOwner?.id;

    // 核心身份隔离逻辑：当检测到当前聊天身份改变，立即重置右侧聊天窗口选择状态，坚决杜绝串数据
    if (_activeOwnerId != null && _activeOwnerId != currentOwnerId) {
      _cachedChats.clear();
      _selectedSessionUnitId = null;
      _selectedTitle = null;
    }
    _activeOwnerId = currentOwnerId;

    final allSessions = widget.controller.sessions;
    // 监听外部对 selectedDesktopSessionUnitIdProvider 的写入（例如从通讯录点击发消息）
    ref.listen<String?>(selectedDesktopSessionUnitIdProvider, (prev, next) {
      if (next != null && next != _selectedSessionUnitId) {
        final session = allSessions.where((s) => s.id == next).firstOrNull;
        if (session != null) {
          _selectSession(session);
        } else {
          final ownerId = currentOwnerId ?? 0;
          _touchCachedChat(next, '聊天', ownerId);
          setState(() {
            _selectedSessionUnitId = next;
            _selectedTitle = null;
          });
        }
      }
    });

    // 保护：如果当前选中的 session 既不在当前会话列表中，也不在已缓存会话中，且会话列表非空，安全重置选择
    if (_selectedSessionUnitId != null &&
        allSessions.isNotEmpty &&
        !allSessions.any((s) => s.id == _selectedSessionUnitId) &&
        !_cachedChats.containsKey(_selectedSessionUnitId!)) {
      _selectedSessionUnitId = null;
      _selectedTitle = null;
    }

    if (_selectedSessionUnitId != null &&
        !_cachedChats.containsKey(_selectedSessionUnitId!)) {
      final ownerId = currentOwnerId ?? 0;
      _touchCachedChat(
        _selectedSessionUnitId!,
        _selectedTitle ?? '聊天',
        ownerId,
      );
    }

    final filteredSessions =
        _searchKeyword.isEmpty
            ? allSessions
            : allSessions
                .where(
                  (s) => s.title.toLowerCase().contains(
                    _searchKeyword.toLowerCase(),
                  ),
                )
                .toList();

    final listItems = buildSessionListItems(
      filteredSessions,
      hasMore: _searchKeyword.isEmpty ? widget.controller.hasMore : false,
    );

    final listPaneBg =
        isDark ? const Color(0xFF232323) : const Color(0xFFF7F7F7);
    final dividerColor =
        isDark ? const Color(0x1FFFFFFF) : const Color(0x1F000000);

    final dockState = ref.watch(desktopBrowserDockProvider);
    if (!_isDraggingBrowserDivider && _browserPaneWidth != dockState.width) {
      _browserPaneWidth = dockState.width;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        double effectivePaneWidth = _sessionPaneWidth;
        if (totalWidth.isFinite && totalWidth < 760) {
          final maxPane = (totalWidth - 360.0).clamp(180.0, 260.0);
          if (effectivePaneWidth > maxPane) {
            effectivePaneWidth = maxPane;
          }
        }

        return Row(
          children: [
            // ── 会话列表栏 (左列，宽 effectivePaneWidth) ──────────────────────────
            Container(
              width: effectivePaneWidth,
              color: listPaneBg,
              child: Column(
                children: [
                  const SizedBox(height: 12),

                  // 1. 顶部：当前身份胶囊 + 快速发起按钮
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Tooltip(
                            message: '点击切换其它聊天身份',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                DesktopChatOwnerPopover.show(
                                  context,
                                  controller: widget.controller,
                                  anchorOffset: const Offset(70, 48),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      isDark
                                          ? Colors.white.withValues(alpha: 0.06)
                                          : Colors.black.withValues(
                                            alpha: 0.05,
                                          ),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color:
                                        isDark
                                            ? Colors.white.withValues(
                                              alpha: 0.08,
                                            )
                                            : Colors.black.withValues(
                                              alpha: 0.06,
                                            ),
                                    width: 0.5,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    AppAvatar(
                                      name: currentOwner?.name ?? '我',
                                      imageUrl: currentOwner?.imageUrl,
                                      radius: 11,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        currentOwner?.name ?? '请选择身份',
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Icon(
                                      Icons.arrow_drop_down_rounded,
                                      size: 18,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // 发起会话 / 快速添加按钮 (+)
                        PopupMenuButton<String>(
                          tooltip: '发起聊天',
                          icon: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color:
                                  isDark
                                      ? Colors.white.withValues(alpha: 0.06)
                                      : Colors.black.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.add_rounded,
                              size: 19,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          offset: const Offset(0, 36),
                          onSelected: (val) {
                            if (val == 'create_group') {
                              showDesktopModalDialog<void>(
                                context: context,
                                title: '发起群聊',
                                width: 480,
                                height: 560,
                                child: const CreateGroupPage(isDialog: true),
                              );
                            } else if (val == 'add_friend') {
                              showDesktopModalDialog<void>(
                                context: context,
                                title: '添加好友',
                                width: 520,
                                height: 600,
                                child: const AddFriendPage(isDialog: true),
                              );
                            } else if (val == 'scan') {
                              final currentOwner =
                                  ref
                                      .read(sessionListControllerProvider)
                                      .currentOwner;
                              MyQrCodeDialog.show(context, owner: currentOwner);
                            }
                          },
                          itemBuilder:
                              (ctx) => [
                                const PopupMenuItem(
                                  value: 'create_group',
                                  child: Row(
                                    children: [
                                      Icon(Icons.group_add_rounded, size: 18),
                                      SizedBox(width: 10),
                                      Text(
                                        '发起群聊',
                                        style: TextStyle(fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'add_friend',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.person_add_alt_1_rounded,
                                        size: 18,
                                      ),
                                      SizedBox(width: 10),
                                      Text(
                                        '添加好友',
                                        style: TextStyle(fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'scan',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.qr_code_scanner_rounded,
                                        size: 18,
                                      ),
                                      SizedBox(width: 10),
                                      Text(
                                        '扫一扫',
                                        style: TextStyle(fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),

                  // 2. 搜索框
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Container(
                      height: 32,
                      decoration: BoxDecoration(
                        color:
                            isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(fontSize: 12.5),
                        decoration: InputDecoration(
                          hintText: '搜索',
                          hintStyle: TextStyle(
                            fontSize: 12.5,
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.6,
                            ),
                          ),
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            size: 16,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 30,
                          ),
                          suffixIcon:
                              _searchKeyword.isNotEmpty
                                  ? IconButton(
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 14,
                                    ),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchKeyword = '');
                                    },
                                  )
                                  : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 7,
                          ),
                        ),
                        onChanged:
                            (val) => setState(() => _searchKeyword = val),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // 3. 网络与实时连接状态栏（未连接时提示）
                  if (widget.controller.connectionState !=
                      SessionRealtimeStatus.connected)
                    SignalRStatusBar(
                      state: widget.controller.connectionState,
                      onReconnect: widget.controller.reconnectSignalR,
                      errorDescription:
                          widget.controller.signalRErrorDescription,
                      hubUrl: widget.controller.signalRHubUrl,
                    ),

                  if (widget.controller.error != null)
                    MaterialBanner(
                      content: Text(
                        '加载失败：${widget.controller.error}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      actions: [
                        TextButton(
                          onPressed: widget.controller.loadNextPage,
                          child: const Text('重试'),
                        ),
                      ],
                    ),

                  // 4. 会话列表本体（与移动端完全一致的分组、未读、时间分段和项排版）
                  Expanded(
                    child:
                        widget.controller.sessions.isEmpty &&
                                widget.controller.isLoading
                            ? const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                            : filteredSessions.isEmpty
                            ? Center(
                              child: Text(
                                _searchKeyword.isNotEmpty ? '未找到匹配会话' : '暂无会话',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                            )
                            : ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              itemCount: listItems.length + 1,
                              itemBuilder: (context, index) {
                                if (index == listItems.length) {
                                  return _DesktopLoadMoreFooter(
                                    controller: widget.controller,
                                    isSearching: _searchKeyword.isNotEmpty,
                                  );
                                }
                                final item = listItems[index];
                                final session = item.session;
                                final isSelected =
                                    session != null &&
                                    session.id == _selectedSessionUnitId;

                                return SessionListItemView(
                                  key:
                                      session != null
                                          ? ValueKey(
                                            'desktop_session_${session.id}',
                                          )
                                          : null,
                                  item: item,
                                  isSelected: isSelected,
                                  onTap:
                                      session != null
                                          ? () => _selectSession(session)
                                          : null,
                                  onDoubleTap:
                                      session != null
                                          ? () =>
                                              _openInStandaloneWindow(session)
                                          : null,
                                  onSecondaryTapDown:
                                      session != null
                                          ? (details) =>
                                              _showSessionContextMenu(
                                                details,
                                                session,
                                              )
                                          : null,
                                  onAvatarHover:
                                      session != null ? _onAvatarHover : null,
                                  onAvatarLeave: _onAvatarLeave,
                                  onLongPress:
                                      session != null
                                          ? () => SessionMenuSheet.show(
                                            context: context,
                                            controller: widget.controller,
                                            session: session,
                                          )
                                          : null,
                                  showDivider:
                                      index + 1 < listItems.length &&
                                      listItems[index + 1].kind ==
                                          SessionListItemKind.session,
                                  aiRunning:
                                      session != null &&
                                      widget.controller.isAiRunning(session.id),
                                );
                              },
                            ),
                  ),
                ],
              ),
            ),

            // ── 左右拖拽调节宽度的垂直分割手柄 ──────────────────────────
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) {
                setState(() {
                  final maxAllowed = (totalWidth.isFinite
                          ? totalWidth - 320.0
                          : 480.0)
                      .clamp(220.0, 480.0);
                  _sessionPaneWidth = (_sessionPaneWidth + details.delta.dx)
                      .clamp(180.0, maxAllowed);
                });
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: Container(
                  width: 5,
                  color: Colors.transparent,
                  child: Center(
                    child: Container(width: 0.5, color: dividerColor),
                  ),
                ),
              ),
            ),

            // ── 聊天工作区 (右列，自适应，LRU 组件复用池) ──────────────────────
            Expanded(
              child:
                  _selectedSessionUnitId == null
                      ? const _DesktopEmptyChatCanvas()
                      : Stack(
                        fit: StackFit.expand,
                        children: [
                          for (final chat in _cachedChats.values)
                            Offstage(
                              key: ValueKey<String>(
                                'desktop_chat_cache_${chat.sessionUnitId}',
                              ),
                              offstage:
                                  chat.sessionUnitId != _selectedSessionUnitId,
                              child: TickerMode(
                                enabled:
                                    chat.sessionUnitId ==
                                    _selectedSessionUnitId,
                                child: ChatPage(
                                  key: ValueKey<String>(
                                    'chat_${chat.sessionUnitId}',
                                  ),
                                  ownerId: chat.ownerId,
                                  sessionUnitId: chat.sessionUnitId,
                                  title:
                                      chat.sessionUnitId ==
                                              _selectedSessionUnitId
                                          ? (_selectedTitle ?? chat.title)
                                          : chat.title,
                                  isDesktop: true,
                                  onPopOut: () {
                                    final ownerId =
                                        widget.controller.currentOwner?.id;
                                    ref
                                        .read(windowServiceProvider)
                                        .openChat(
                                          sessionUnitId: chat.sessionUnitId,
                                          ownerId: ownerId,
                                          title: chat.title,
                                        );
                                    setState(() {
                                      _cachedChats.remove(chat.sessionUnitId);
                                      if (_selectedSessionUnitId ==
                                          chat.sessionUnitId) {
                                        _selectedSessionUnitId = null;
                                        _selectedTitle = null;
                                      }
                                    });
                                    ref
                                        .read(
                                          selectedDesktopSessionUnitIdProvider
                                              .notifier,
                                        )
                                        .select(null);
                                  },
                                ),
                              ),
                            ),
                        ],
                      ),
            ),

            // ── 浏览器嵌入分栏 (右侧内联 WebView2 组件与拖拽手柄) ────────────────────
            if (dockState.shouldRenderPlaceholder) ...[
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (_) {
                  _isDraggingBrowserDivider = true;
                  _browserPaneWidth =
                      ref.read(desktopBrowserDockProvider).width;
                },
                onHorizontalDragUpdate: (details) {
                  final maxW = (totalWidth - effectivePaneWidth - 360.0).clamp(
                    360.0,
                    960.0,
                  );
                  _browserPaneWidth =
                      (_browserPaneWidth - details.delta.dx)
                          .clamp(360.0, maxW)
                          .toDouble();
                  ref
                      .read(desktopBrowserDockProvider.notifier)
                      .setWidth(_browserPaneWidth, min: 360.0, max: maxW);
                },
                onHorizontalDragEnd: (_) {
                  _isDraggingBrowserDivider = false;
                },
                onHorizontalDragCancel: () {
                  _isDraggingBrowserDivider = false;
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: Container(
                    width: 5,
                    color: Colors.transparent,
                    child: Center(
                      child: Container(width: 0.5, color: dividerColor),
                    ),
                  ),
                ),
              ),
              SizedBox(
                key: _browserPlaceholderKey,
                width:
                    _isDraggingBrowserDivider
                        ? _browserPaneWidth
                        : dockState.width,
                child: DesktopBrowserWindow(
                  key: const ValueKey('inline_docked_browser_window'),
                  initialUrl: dockState.currentUrl ?? 'https://www.bing.com',
                  title: dockState.currentTitle,
                  isInlineDocked: true,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _DesktopLoadMoreFooter extends StatelessWidget {
  const _DesktopLoadMoreFooter({
    required this.controller,
    required this.isSearching,
  });

  final SessionListController controller;
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    if (isSearching) return const SizedBox(height: 16);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (controller.isLoading && controller.sessions.isNotEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (!controller.hasMore && controller.sessions.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            '共有 ${controller.totalCount ?? controller.sessions.length} 个好友',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ),
      );
    }
    return const SizedBox(height: 12);
  }
}

/// 桌面端未选中会话空状态画布
class _DesktopEmptyChatCanvas extends StatelessWidget {
  const _DesktopEmptyChatCanvas();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    final canvasBg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF);

    return Container(
      color: canvasBg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 68,
              color:
                  isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.12),
            ),
            const SizedBox(height: 14),
            Text(
              'Goto IM 桌面端',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '请从左侧列表中选择聊天，或双击打开独立窗口',
              style: TextStyle(
                fontSize: 12.5,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
