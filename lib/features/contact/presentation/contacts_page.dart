import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../session/application/session_list_controller.dart';
import '../../session/presentation/chat_object_avatar.dart';
import '../application/contacts_controller.dart';
import '../data/models/contact_group.dart';

class ContactsPage extends ConsumerStatefulWidget {
  const ContactsPage({super.key});

  @override
  ConsumerState<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends ConsumerState<ContactsPage> {
  // 联系人行高与分组标题高度集中配置，修改时会同步影响滚动定位。
  static const _rowExtent = 56.0;
  static const _groupHeaderExtent = 36.0;
  static const _titleBarExtent = 56.0;
  // 右侧字母索引拖动时，暂时关闭吸顶标题毛玻璃；松手后自动恢复。
  static const _disablePinnedHeaderBlurWhileIndexDragging = true;
  static const _quickActionsExtent = _rowExtent * 4;
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<String?> _draggingIndex = ValueNotifier<String?>(null);
  final ValueNotifier<String> _activeSurnameInitial = ValueNotifier<String>('');
  final ValueNotifier<String> _activeGroupIndex = ValueNotifier<String>('');
  final ValueNotifier<bool> _isIndexDragging = ValueNotifier<bool>(false);
  final ValueNotifier<_PinnedContactGroup?> _pinnedHeader =
      ValueNotifier<_PinnedContactGroup?>(null);
  List<double> _groupOffsets = const <double>[];
  List<ContactGroup> _offsetGroups = const <ContactGroup>[];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateActiveIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(sessionListControllerProvider).initialize();
    });
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_updateActiveIndex)
      ..dispose();
    _draggingIndex.dispose();
    _activeSurnameInitial.dispose();
    _activeGroupIndex.dispose();
    _isIndexDragging.dispose();
    _pinnedHeader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(sessionListControllerProvider);
    final contacts = ref.watch(contactsControllerProvider);
    final ownerId = sessions.currentOwner?.id;
    if (ownerId != null && contacts.ownerId != ownerId) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(contactsControllerProvider).initialize(ownerId),
      );
    }
    final groups = contacts.groups;
    final isInitialLoading =
        groups.isEmpty && (contacts.isLoading || contacts.ownerId != ownerId);
    _syncGroupOffsets(groups);
    if (groups.isNotEmpty &&
        (_activeGroupIndex.value.isEmpty ||
            !groups.any((group) => group.index == _activeGroupIndex.value))) {
      _activeGroupIndex.value = groups.first.index;
      _activeSurnameInitial.value = groups.first.contacts.first.surnameInitial;
    }

    final headerColor = _contactHeaderBackground(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: headerColor,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              const _ContactsTitleBar(),
              Expanded(
                child: Stack(
                  children: <Widget>[
                    RefreshIndicator(
                      onRefresh: contacts.refresh,
                      child: CustomScrollView(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: <Widget>[
                          const SliverToBoxAdapter(child: _QuickActions()),
                          if (contacts.error != null)
                            SliverToBoxAdapter(
                              child: _ContactsError(
                                error: contacts.error!,
                                hasContacts: groups.isNotEmpty,
                                onRetry:
                                    groups.isEmpty
                                        ? () => ref
                                            .read(contactsControllerProvider)
                                            .initialize(ownerId)
                                        : contacts.refresh,
                              ),
                            ),
                          if (isInitialLoading)
                            const SliverToBoxAdapter(
                              child: _ContactsLoadingSkeleton(),
                            )
                          else if (groups.isEmpty)
                            const SliverFillRemaining(
                              hasScrollBody: false,
                              child: _NoContacts(),
                            )
                          else
                            ..._buildGroupSlivers(context, groups, ownerId),
                          if (groups.isNotEmpty)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 20,
                                ),
                                child: Center(
                                  child: Text(
                                    '共有 ${contacts.totalCount} 位联系人',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    ValueListenableBuilder<_PinnedContactGroup?>(
                      valueListenable: _pinnedHeader,
                      builder: (context, header, _) {
                        if (header == null) return const SizedBox.shrink();
                        return Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: ValueListenableBuilder<bool>(
                            valueListenable: _isIndexDragging,
                            builder:
                                (context, isDragging, _) => _ContactGroupHeader(
                                  group: header.group,
                                  activeInitial: _activeSurnameInitial.value,
                                  activeInitialListenable:
                                      _activeSurnameInitial,
                                  onSurnameSelected:
                                      (initial) => _scrollToSurname(
                                        groups,
                                        header.group,
                                        initial,
                                      ),
                                  showBlur:
                                      !_disablePinnedHeaderBlurWhileIndexDragging ||
                                      !isDragging,
                                ),
                          ),
                        );
                      },
                    ),
                    if (groups.isNotEmpty)
                      Positioned(
                        top: 8,
                        right: 2,
                        bottom: 8,
                        child: ValueListenableBuilder<String>(
                          valueListenable: _activeGroupIndex,
                          builder:
                              (context, activeKey, _) => _AlphabetIndexBar(
                                keys:
                                    groups.map((group) => group.index).toList(),
                                activeKey: activeKey,
                                onSelected:
                                    (key) => _scrollToGroup(groups, key),
                                onScrollToTop: _scrollToTop,
                                onScrollToBottom: _scrollToBottom,
                                onDragging: (key) {
                                  if (_draggingIndex.value != key) {
                                    _draggingIndex.value = key;
                                  }
                                  final isDragging = key != null;
                                  if (_isIndexDragging.value != isDragging) {
                                    _isIndexDragging.value = isDragging;
                                  }
                                },
                              ),
                        ),
                      ),
                    ValueListenableBuilder<String?>(
                      valueListenable: _draggingIndex,
                      builder: (context, key, _) {
                        if (key == null) return const SizedBox.shrink();
                        return IgnorePointer(
                          child: Center(
                            child: Container(
                              width: 80,
                              height: 80,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: .58),
                                shape: BoxShape.circle,
                                boxShadow: <BoxShadow>[
                                  BoxShadow(
                                    color: Theme.of(context).colorScheme.primary
                                        .withValues(alpha: .52),
                                    blurRadius: 24,
                                    spreadRadius: 5,
                                  ),
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: .36),
                                    blurRadius: 14,
                                  ),
                                ],
                              ),
                              child: Text(
                                key,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 36,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildGroupSlivers(
    BuildContext context,
    List<ContactGroup> groups,
    int? ownerId,
  ) => groups
      .expand<Widget>(
        (group) => <Widget>[
          SliverPersistentHeader(
            delegate: _ContactGroupHeaderDelegate(
              group: group,
              activeInitial: _activeSurnameInitial,
              onSurnameSelected:
                  (initial) => _scrollToSurname(groups, group, initial),
            ),
          ),
          SliverFixedExtentList(
            itemExtent: _rowExtent,
            delegate: SliverChildBuilderDelegate((context, index) {
              final contact = group.contacts[index];
              return _ContactRow(
                contact: contact,
                showDivider: index + 1 < group.contacts.length,
                onTap: () => _openChat(context, contact, ownerId),
              );
            }, childCount: group.contacts.length),
          ),
        ],
      )
      .toList(growable: false);

  void _openChat(BuildContext context, ContactEntry contact, int? ownerId) {
    context.push(
      '/chat/${Uri.encodeComponent(contact.id)}'
      '?ownerId=${contact.ownerId ?? ownerId ?? 0}'
      '&title=${Uri.encodeQueryComponent(contact.displayName)}',
    );
  }

  void _syncGroupOffsets(List<ContactGroup> groups) {
    final unchanged =
        groups.length == _offsetGroups.length &&
        Iterable<int>.generate(groups.length).every(
          (index) =>
              identical(groups[index], _offsetGroups[index]) &&
              groups[index].count == _offsetGroups[index].count,
        );
    if (unchanged) return;

    var offset = _quickActionsExtent;
    _groupOffsets = List<double>.generate(groups.length, (index) {
      final groupOffset = offset;
      offset += _groupHeaderExtent + groups[index].count * _rowExtent;
      return groupOffset;
    }, growable: false);
    _offsetGroups = List<ContactGroup>.of(groups, growable: false);
  }

  double _groupOffset(int targetIndex) {
    if (targetIndex < 0 || targetIndex >= _groupOffsets.length) {
      return _quickActionsExtent;
    }
    return _groupOffsets[targetIndex];
  }

  void _scrollToGroup(List<ContactGroup> groups, String key) {
    final index = groups.indexWhere((group) => group.index == key);
    if (index < 0 || !_scrollController.hasClients) {
      return;
    }
    _scrollController.jumpTo(
      _groupOffset(index).clamp(0, _scrollController.position.maxScrollExtent),
    );
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollToSurname(
    List<ContactGroup> groups,
    ContactGroup group,
    String surname,
  ) {
    final groupIndex = groups.indexOf(group);
    final contactIndex = group.contacts.indexWhere(
      (contact) => contact.surnameInitial == surname,
    );
    if (groupIndex < 0 || contactIndex < 0 || !_scrollController.hasClients) {
      return;
    }
    final offset =
        _groupOffset(groupIndex) +
        _groupHeaderExtent +
        contactIndex * _rowExtent -
        _groupHeaderExtent;
    _scrollController.animateTo(
      offset.clamp(0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  void _updateActiveIndex() {
    final groups = ref.read(contactsControllerProvider).groups;
    if (groups.isEmpty || !_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    if (offset < _quickActionsExtent) {
      if (_pinnedHeader.value != null) {
        _pinnedHeader.value = null;
      }
      return;
    }
    var low = 0;
    var high = groups.length - 1;
    var activeIndex = 0;
    final targetOffset = offset;
    while (low <= high) {
      final middle = (low + high) ~/ 2;
      if (targetOffset >= _groupOffset(middle)) {
        activeIndex = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    final group = groups[activeIndex];
    final firstContactOffset = _groupOffset(activeIndex) + _groupHeaderExtent;
    final visibleContactIndex =
        ((offset + _groupHeaderExtent - firstContactOffset) / _rowExtent)
            .floor()
            .clamp(0, group.contacts.length - 1);
    final activeIndexKey = group.index;
    final activeSurname =
        group.contacts[visibleContactIndex.toInt()].surnameInitial;
    if (activeSurname != _activeSurnameInitial.value) {
      _activeSurnameInitial.value = activeSurname;
    }
    if (activeIndexKey != _activeGroupIndex.value) {
      _activeGroupIndex.value = activeIndexKey;
    }
    final pinnedHeader = _pinnedHeader.value;
    if (pinnedHeader == null || pinnedHeader.group != group) {
      _pinnedHeader.value = _PinnedContactGroup(group: group);
    }
  }
}

class _PinnedContactGroup {
  const _PinnedContactGroup({required this.group});

  final ContactGroup group;
}

/// 通讯录状态栏、标题栏和分组标题的统一背景色。
/// 默认跟随工作台 AppBar 的 [ColorScheme.surface]；如需只调整通讯录，改这里。
/// 保持不透明，避免 Android 状态栏与应用内标题栏出现合成后的色差。
Color _contactHeaderBackground(BuildContext context) =>
    Theme.of(context).colorScheme.surface;

class _ContactsTitleBar extends StatelessWidget {
  const _ContactsTitleBar();

  @override
  Widget build(BuildContext context) => Material(
    color: _contactHeaderBackground(context),
    child: SizedBox(
      height: _ContactsPageState._titleBarExtent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: <Widget>[
            Text('通讯录', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            IconButton(
              tooltip: '搜索联系人',
              onPressed:
                  () => ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('联系人搜索将在下一步接入'))),
              icon: const Icon(Icons.search),
            ),
            IconButton(
              tooltip: '添加好友',
              onPressed:
                  () => ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('添加好友功能即将接入'))),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
    ),
  );
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  static const _items = <(String, IconData, Color)>[
    ('添加好友', Icons.person_add_alt_1_rounded, Color(0xfff59e0b)),
    ('附近', Icons.person_pin_circle_outlined, Color(0xff049565)),
    ('群聊', Icons.groups_rounded, Color(0xff4f90e0)),
    ('广场', Icons.star_rounded, Color(0xfff34f4f)),
  ];

  @override
  Widget build(BuildContext context) => Column(
    children: _items
        .map(
          (item) => SizedBox(
            height: _ContactsPageState._rowExtent,
            child: ListTile(
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: item.$3,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  item.$2,
                  color: const Color.fromRGBO(255, 255, 255, 0.5),
                ),
              ),
              title: Text(item.$1),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap:
                  () => ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('${item.$1}功能即将接入'))),
            ),
          ),
        )
        .toList(growable: false),
  );
}

class _ContactGroupHeaderDelegate extends SliverPersistentHeaderDelegate {
  _ContactGroupHeaderDelegate({
    required this.group,
    required this.activeInitial,
    required this.onSurnameSelected,
  });

  final ContactGroup group;
  final ValueListenable<String> activeInitial;
  final ValueChanged<String> onSurnameSelected;

  @override
  double get minExtent => _ContactsPageState._groupHeaderExtent;
  @override
  double get maxExtent => _ContactsPageState._groupHeaderExtent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => _ContactGroupHeader(
    group: group,
    activeInitial: activeInitial.value,
    onSurnameSelected: onSurnameSelected,
    showBlur: false,
  );

  @override
  bool shouldRebuild(covariant _ContactGroupHeaderDelegate oldDelegate) =>
      group != oldDelegate.group || activeInitial != oldDelegate.activeInitial;
}

class _ContactGroupHeader extends StatelessWidget {
  const _ContactGroupHeader({
    required this.group,
    required this.activeInitial,
    required this.onSurnameSelected,
    this.activeInitialListenable,
    this.showBlur = true,
  });

  final ContactGroup group;
  final String activeInitial;
  final ValueListenable<String>? activeInitialListenable;
  final ValueChanged<String> onSurnameSelected;
  final bool showBlur;

  @override
  Widget build(BuildContext context) {
    final header = Material(
      color: _contactHeaderBackground(context),
      child: Row(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 4),
            child: Text(
              group.index,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            '(${group.count})',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(width: 8),
          _ContactSurnameInitialBar(
            group: group,
            activeInitial: activeInitial,
            activeInitialListenable: activeInitialListenable,
            onSelected: onSurnameSelected,
          ),
        ],
      ),
    );
    return SizedBox(
      height: _ContactsPageState._groupHeaderExtent,
      child:
          showBlur
              ? ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: header,
                ),
              )
              : header,
    );
  }
}

class _ContactSurnameInitialBar extends StatefulWidget {
  const _ContactSurnameInitialBar({
    required this.group,
    required this.activeInitial,
    required this.activeInitialListenable,
    required this.onSelected,
  });

  final ContactGroup group;
  final String activeInitial;
  final ValueListenable<String>? activeInitialListenable;
  final ValueChanged<String> onSelected;

  @override
  State<_ContactSurnameInitialBar> createState() =>
      _ContactSurnameInitialBarState();
}

class _ContactSurnameInitialBarState extends State<_ContactSurnameInitialBar> {
  final ScrollController _scrollController = ScrollController();
  late Map<String, GlobalKey> _initialKeys = _createInitialKeys();
  late String _currentInitial = widget.activeInitial;

  Map<String, GlobalKey> _createInitialKeys() => <String, GlobalKey>{
    for (final initial in widget.group.surnameInitials) initial: GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    widget.activeInitialListenable?.addListener(_onActiveInitialChanged);
  }

  @override
  void didUpdateWidget(covariant _ContactSurnameInitialBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeInitialListenable != widget.activeInitialListenable) {
      oldWidget.activeInitialListenable?.removeListener(
        _onActiveInitialChanged,
      );
      widget.activeInitialListenable?.addListener(_onActiveInitialChanged);
    }
    if (oldWidget.group != widget.group) {
      _initialKeys = _createInitialKeys();
      _currentInitial = widget.activeInitial;
    }
  }

  @override
  void dispose() {
    widget.activeInitialListenable?.removeListener(_onActiveInitialChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onActiveInitialChanged() {
    final nextInitial = widget.activeInitialListenable!.value;
    if (nextInitial == _currentInitial || !mounted) return;
    setState(() => _currentInitial = nextInitial);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final targetContext = _initialKeys[nextInitial]?.currentContext;
      if (mounted && targetContext != null) {
        Scrollable.ensureVisible(
          targetContext,
          alignment: .5,
          duration: Duration.zero,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(right: 42),
        child: Row(
          children: widget.group.surnameInitials
              .expand<Widget>((initial) sync* {
                yield KeyedSubtree(
                  key: _initialKeys[initial],
                  child: _buildButton(
                    initial,
                    initial == _currentInitial,
                    colors,
                  ),
                );
                if (initial != widget.group.surnameInitials.last) {
                  yield const Text('、');
                }
              })
              .toList(growable: false),
        ),
      ),
    );
  }

  Widget _buildButton(String initial, bool isActive, ColorScheme colors) =>
      TextButton(
        onPressed: () => widget.onSelected(initial),
        style: TextButton.styleFrom(
          foregroundColor: isActive ? colors.primary : colors.onSurfaceVariant,
          minimumSize: const Size(28, 32),
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
        child: Text(initial),
      );
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.contact,
    required this.showDivider,
    required this.onTap,
  });
  final ContactEntry contact;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          const SizedBox(width: 16),
          ChatObjectAvatar(
            name: contact.displayName,
            imageUrl: contact.avatarUrl.isEmpty ? null : contact.avatarUrl,
            radius: 21,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: _ContactsPageState._rowExtent,
              alignment: Alignment.centerLeft,
              decoration:
                  showDivider
                      ? BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: Theme.of(
                              context,
                            ).dividerColor.withValues(alpha: .35),
                            width: .5,
                          ),
                        ),
                      )
                      : null,
              child: Text(
                contact.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _AlphabetIndexBar extends StatefulWidget {
  const _AlphabetIndexBar({
    required this.keys,
    required this.activeKey,
    required this.onSelected,
    required this.onScrollToTop,
    required this.onScrollToBottom,
    required this.onDragging,
  });
  final List<String> keys;
  final String activeKey;
  final ValueChanged<String> onSelected;
  final VoidCallback onScrollToTop;
  final VoidCallback onScrollToBottom;
  final ValueChanged<String?> onDragging;

  @override
  State<_AlphabetIndexBar> createState() => _AlphabetIndexBarState();
}

class _AlphabetIndexBarState extends State<_AlphabetIndexBar> {
  static const _itemExtent = 19.0;
  static const _jumpItemExtent = 26.0;
  static const _verticalPadding = 4.0;
  String? _draggingKey;
  String? _jumpTarget;
  String? _pendingKey;
  bool _selectionScheduled = false;

  void _selectAt(Offset localPosition) {
    if (widget.keys.isEmpty) return;
    final contentY = localPosition.dy - _verticalPadding;
    if (contentY < _jumpItemExtent) {
      if (_jumpTarget == 'top') return;
      _jumpTarget = 'top';
      _stopDragging(clearJumpTarget: false);
      widget.onScrollToTop();
      return;
    }
    final alphabetEnd = _jumpItemExtent + widget.keys.length * _itemExtent;
    if (contentY >= alphabetEnd) {
      if (_jumpTarget == 'bottom') return;
      _jumpTarget = 'bottom';
      _stopDragging(clearJumpTarget: false);
      widget.onScrollToBottom();
      return;
    }
    _jumpTarget = null;
    final rawIndex = ((contentY - _jumpItemExtent) / _itemExtent).floor();
    final index = rawIndex.clamp(0, widget.keys.length - 1).toInt();
    final key = widget.keys[index];
    if (key == _draggingKey) return;
    setState(() => _draggingKey = key);
    widget.onDragging(key);
    _scheduleSelection(key);
  }

  void _scheduleSelection(String key) {
    _pendingKey = key;
    if (_selectionScheduled) return;
    _selectionScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _selectionScheduled = false;
      final selectedKey = _pendingKey;
      _pendingKey = null;
      if (mounted && selectedKey != null) {
        widget.onSelected(selectedKey);
      }
    });
  }

  void _stopDragging({bool clearJumpTarget = true}) {
    if (clearJumpTarget) _jumpTarget = null;
    if (_draggingKey != null) {
      setState(() => _draggingKey = null);
      widget.onDragging(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shownKey = _draggingKey ?? widget.activeKey;
    final isTouching = _draggingKey != null;
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanDown: (details) => _selectAt(details.localPosition),
            onPanUpdate: (details) => _selectAt(details.localPosition),
            onPanEnd: (_) => _stopDragging(),
            onPanCancel: _stopDragging,
            onTapUp: (_) => _stopDragging(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: isTouching ? .88 : .22),
                borderRadius: BorderRadius.circular(16),
                boxShadow:
                    isTouching
                        ? <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .12),
                            blurRadius: 8,
                          ),
                        ]
                        : null,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: _verticalPadding,
                  horizontal: 2,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _AlphabetJumpIcon(icon: Icons.vertical_align_top_rounded),
                    ...widget.keys.map(
                      (key) => SizedBox(
                        width: 28,
                        height: _itemExtent,
                        child: Center(
                          child: Text(
                            key,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight:
                                  key == shownKey
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                              color:
                                  key == shownKey
                                      ? colors.primary.withValues(
                                        alpha: isTouching ? 1 : .56,
                                      )
                                      : colors.onSurfaceVariant.withValues(
                                        alpha: isTouching ? .9 : .36,
                                      ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    _AlphabetJumpIcon(
                      icon: Icons.vertical_align_bottom_rounded,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlphabetJumpIcon extends StatelessWidget {
  const _AlphabetJumpIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 28,
      height: _AlphabetIndexBarState._jumpItemExtent,
      child: Center(
        child: Icon(
          icon,
          size: 16,
          color: colors.onSurfaceVariant.withValues(alpha: .42),
        ),
      ),
    );
  }
}

class _ContactsError extends StatelessWidget {
  const _ContactsError({
    required this.error,
    required this.hasContacts,
    required this.onRetry,
  });
  final Object error;
  final bool hasContacts;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => MaterialBanner(
    content: Text(hasContacts ? '在线通讯录更新失败，正在显示本地联系人。' : '通讯录加载失败：$error'),
    actions: <Widget>[TextButton(onPressed: onRetry, child: const Text('重试'))],
  );
}

class _NoContacts extends StatelessWidget {
  const _NoContacts();

  @override
  Widget build(BuildContext context) => const Center(child: Text('暂无联系人'));
}

class _ContactsLoadingSkeleton extends StatelessWidget {
  const _ContactsLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: <Widget>[
          Container(
            height: _ContactsPageState._groupHeaderExtent,
            color: color,
          ),
          ...List<Widget>.generate(
            7,
            (index) => SizedBox(
              height: _ContactsPageState._rowExtent,
              child: Row(
                children: <Widget>[
                  const SizedBox(width: 16),
                  CircleAvatar(radius: 21, backgroundColor: color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: index.isEven ? .42 : .58,
                        child: Container(height: 14, color: color),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
