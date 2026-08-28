import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
  static const _rowExtent = 56.0;
  static const _groupHeaderExtent = 40.0;
  static const _quickActionsExtent = _rowExtent * 4;
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<String?> _draggingIndex = ValueNotifier<String?>(null);
  final ValueNotifier<String> _activeSurnameInitial = ValueNotifier<String>('');
  List<double> _groupOffsets = const <double>[];
  List<ContactGroup> _offsetGroups = const <ContactGroup>[];
  String _activeIndex = '';

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
    _syncGroupOffsets(groups);
    if (groups.isNotEmpty &&
        (_activeIndex.isEmpty ||
            !groups.any((group) => group.index == _activeIndex))) {
      _activeIndex = groups.first.index;
      _activeSurnameInitial.value = groups.first.contacts.first.surnameInitial;
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
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
                        if (groups.isNotEmpty)
                          SliverPersistentHeader(
                            pinned: true,
                            delegate: _ContactGroupHeaderDelegate(
                              group: groups.firstWhere(
                                (group) => group.index == _activeIndex,
                              ),
                              activeInitial: _activeSurnameInitial,
                              onSurnameSelected:
                                  (initial) => _scrollToSurname(
                                    groups,
                                    groups.firstWhere(
                                      (group) => group.index == _activeIndex,
                                    ),
                                    initial,
                                  ),
                            ),
                          ),
                        if (groups.isEmpty && contacts.isLoading)
                          const SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(child: CircularProgressIndicator()),
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
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: Center(
                                child: Text(
                                  '共有 ${contacts.totalCount} 位联系人',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (groups.isNotEmpty)
                    Positioned(
                      top: 8,
                      right: 2,
                      bottom: 8,
                      child: _AlphabetIndexBar(
                        keys: groups.map((group) => group.index).toList(),
                        activeKey: _activeIndex,
                        onSelected: (key) => _scrollToGroup(groups, key),
                        onDragging: (key) {
                          if (_draggingIndex.value != key) {
                            _draggingIndex.value = key;
                          }
                        },
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
    );
  }

  List<Widget> _buildGroupSlivers(
    BuildContext context,
    List<ContactGroup> groups,
    int? ownerId,
  ) => groups
      .expand<Widget>(
        (group) => <Widget>[
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

    var offset = _quickActionsExtent + _groupHeaderExtent;
    _groupOffsets = List<double>.generate(groups.length, (index) {
      final groupOffset = offset;
      offset += groups[index].count * _rowExtent;
      return groupOffset;
    }, growable: false);
    _offsetGroups = List<ContactGroup>.of(groups, growable: false);
  }

  double _groupOffset(int targetIndex) {
    if (targetIndex < 0 || targetIndex >= _groupOffsets.length) {
      return _quickActionsExtent + _groupHeaderExtent;
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
    final offset = _groupOffset(groupIndex) + contactIndex * _rowExtent;
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
    final firstContactOffset = _groupOffset(activeIndex);
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
    if (activeIndexKey != _activeIndex && mounted) {
      setState(() => _activeIndex = activeIndexKey);
    }
  }
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
                child: Icon(item.$2, color: Colors.white),
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
  ) => ValueListenableBuilder<String>(
    valueListenable: activeInitial,
    builder:
        (context, surnameInitial, _) => _ContactGroupHeader(
          group: group,
          activeInitial: surnameInitial,
          onSurnameSelected: onSurnameSelected,
        ),
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
  });

  final ContactGroup group;
  final String activeInitial;
  final ValueChanged<String> onSurnameSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final header = Material(
      color: colors.surfaceContainerHighest.withValues(alpha: .72),
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
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 42),
              itemCount: group.surnameInitials.length,
              separatorBuilder: (_, _) => const Text('、'),
              itemBuilder: (context, index) {
                final initial = group.surnameInitials[index];
                final isActive = initial == activeInitial;
                return TextButton(
                  onPressed: () => onSurnameSelected(initial),
                  style: TextButton.styleFrom(
                    foregroundColor:
                        isActive ? colors.primary : colors.onSurfaceVariant,
                    minimumSize: const Size(28, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  child: Text(initial),
                );
              },
            ),
          ),
        ],
      ),
    );
    return SizedBox(
      height: _ContactsPageState._groupHeaderExtent,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: header,
        ),
      ),
    );
  }
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
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border:
          showDivider
              ? Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: .5,
                ),
              )
              : null,
    ),
    child: ListTile(
      leading: ChatObjectAvatar(
        name: contact.displayName,
        imageUrl: contact.avatarUrl.isEmpty ? null : contact.avatarUrl,
        radius: 21,
      ),
      title: Text(
        contact.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onTap,
    ),
  );
}

class _AlphabetIndexBar extends StatefulWidget {
  const _AlphabetIndexBar({
    required this.keys,
    required this.activeKey,
    required this.onSelected,
    required this.onDragging,
  });
  final List<String> keys;
  final String activeKey;
  final ValueChanged<String> onSelected;
  final ValueChanged<String?> onDragging;

  @override
  State<_AlphabetIndexBar> createState() => _AlphabetIndexBarState();
}

class _AlphabetIndexBarState extends State<_AlphabetIndexBar> {
  static const _itemExtent = 19.0;
  static const _verticalPadding = 4.0;
  String? _draggingKey;

  void _selectAt(Offset localPosition) {
    if (widget.keys.isEmpty) return;
    final rawIndex =
        ((localPosition.dy - _verticalPadding) / _itemExtent).floor();
    final index = rawIndex.clamp(0, widget.keys.length - 1).toInt();
    final key = widget.keys[index];
    if (key == _draggingKey) return;
    setState(() => _draggingKey = key);
    widget.onSelected(key);
    widget.onDragging(key);
  }

  void _stopDragging() {
    if (_draggingKey == null) return;
    setState(() => _draggingKey = null);
    widget.onDragging(null);
  }

  @override
  Widget build(BuildContext context) {
    final shownKey = _draggingKey ?? widget.activeKey;
    return Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanDown: (details) => _selectAt(details.localPosition),
        onPanUpdate: (details) => _selectAt(details.localPosition),
        onPanEnd: (_) => _stopDragging(),
        onPanCancel: _stopDragging,
        onTapUp: (_) => _stopDragging(),
        child: Material(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: .78),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: _verticalPadding,
              horizontal: 2,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: widget.keys
                  .map(
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
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
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
