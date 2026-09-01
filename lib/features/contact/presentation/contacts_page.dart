import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../session/application/session_list_controller.dart';
import '../../user/presentation/profile_page.dart';
import '../application/contacts_controller.dart';
import '../data/models/contact_group.dart';
import 'widgets/alphabet_index_bar.dart';
import 'widgets/contact_group_header.dart';
import 'widgets/contact_row.dart';
import 'widgets/contacts_page_chrome.dart';
import 'widgets/dragging_index_indicator.dart';

class ContactsPage extends ConsumerStatefulWidget {
  const ContactsPage({super.key});

  @override
  ConsumerState<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends ConsumerState<ContactsPage> {
  // 联系人行高与分组标题高度集中配置，修改时会同步影响滚动定位。
  static const _rowExtent = ContactsPageMetrics.rowExtent;
  static const _groupHeaderExtent = ContactsPageMetrics.groupHeaderExtent;
  // 右侧字母索引拖动时，暂时关闭吸顶标题毛玻璃；松手后自动恢复。
  static const _disablePinnedHeaderBlurWhileIndexDragging = true;
  static const _quickActionsExtent = ContactsPageMetrics.quickActionsExtent;
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<String?> _draggingIndex = ValueNotifier<String?>(null);
  final ValueNotifier<String> _activeSurnameInitial = ValueNotifier<String>('');
  final ValueNotifier<String> _activeGroupIndex = ValueNotifier<String>('');
  final ValueNotifier<bool> _isIndexDragging = ValueNotifier<bool>(false);
  final ValueNotifier<PinnedContactGroup?> _pinnedHeader =
      ValueNotifier<PinnedContactGroup?>(null);
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

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
      ),
      child: Scaffold(



        body: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              const ContactsTitleBar(),
              Expanded(
                child: Stack(
                  children: <Widget>[
                    RefreshIndicator(
                      onRefresh: contacts.refresh,
                      child: CustomScrollView(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: <Widget>[
                          const SliverToBoxAdapter(
                            child: ContactsQuickActions(),
                          ),
                          if (contacts.error != null)
                            SliverToBoxAdapter(
                              child: ContactsErrorBanner(
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
                              child: ContactsLoadingSkeleton(),
                            )
                          else if (groups.isEmpty)
                            const SliverFillRemaining(
                              hasScrollBody: false,
                              child: NoContacts(),
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
                    ValueListenableBuilder<PinnedContactGroup?>(
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
                                (context, isDragging, _) => ContactGroupHeader(
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
                              (context, activeKey, _) => AlphabetIndexBar(
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
                    DraggingIndexIndicator(
                      draggingIndexListenable: _draggingIndex,
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
            delegate: ContactGroupHeaderDelegate(
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
              return ContactRow(
                contact: contact,
                showDivider: index + 1 < group.contacts.length,
                onTap: () => _openContactProfile(context, contact, ownerId),
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

  Future<void> _openContactProfile(
    BuildContext context,
    ContactEntry contact,
    int? ownerId,
  ) => openProfilePage(
    context,
    subject: ProfileSubject.contact(contact),
    onSendMessage: () => _openChat(context, contact, ownerId),
  );

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
      _pinnedHeader.value = PinnedContactGroup(group: group);
    }
  }
}
