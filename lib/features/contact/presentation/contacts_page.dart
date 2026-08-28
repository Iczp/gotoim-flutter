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
  String _activeIndex = '';
  String? _draggingIndex;

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
    if (_activeIndex.isEmpty && groups.isNotEmpty) {
      _activeIndex = groups.first.index;
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _ContactsTopBar(totalCount: contacts.totalCount),
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
                          if (_draggingIndex != key && mounted) {
                            setState(() => _draggingIndex = key);
                          }
                        },
                      ),
                    ),
                  if (_draggingIndex case final key?)
                    IgnorePointer(
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
          SliverPersistentHeader(
            pinned: true,
            delegate: _ContactGroupHeaderDelegate(
              group: group,
              activeInitial: _activeIndex,
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

  double _groupOffset(List<ContactGroup> groups, int targetIndex) {
    var offset = _quickActionsExtent;
    for (var index = 0; index < targetIndex; index++) {
      offset += _groupHeaderExtent + groups[index].count * _rowExtent;
    }
    return offset;
  }

  void _scrollToGroup(List<ContactGroup> groups, String key) {
    final index = groups.indexWhere((group) => group.index == key);
    if (index < 0 || !_scrollController.hasClients) {
      return;
    }
    _scrollController.animateTo(
      _groupOffset(groups, index),
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
        _groupOffset(groups, groupIndex) +
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
    var active = groups.first.index;
    for (var index = 0; index < groups.length; index++) {
      if (offset + _groupHeaderExtent >= _groupOffset(groups, index)) {
        active = groups[index].index;
      } else {
        break;
      }
    }
    if (active != _activeIndex && mounted) {
      setState(() => _activeIndex = active);
    }
  }
}

class _ContactsTopBar extends StatelessWidget {
  const _ContactsTopBar({required this.totalCount});
  final int totalCount;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 56,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: <Widget>[
          Text('通讯录', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(width: 8),
          if (totalCount > 0)
            Text('($totalCount)', style: Theme.of(context).textTheme.bodySmall),
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
  final String activeInitial;
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
  ) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHighest,
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
  }

  @override
  bool shouldRebuild(covariant _ContactGroupHeaderDelegate oldDelegate) =>
      group != oldDelegate.group || activeInitial != oldDelegate.activeInitial;
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
