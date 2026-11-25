import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/announcement_providers.dart';
import '../data/models/session_announcement.dart';
import 'announcement_manage_page.dart';
import 'widgets/announcement_detail_dialog.dart';

class AnnouncementListPage extends ConsumerStatefulWidget {
  const AnnouncementListPage({
    required this.sessionId,
    this.canManage = false,
    super.key,
  });

  final String sessionId;
  final bool canManage;

  static Future<void> open(
    BuildContext context, {
    required String sessionId,
    bool canManage = false,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AnnouncementListPage(
          sessionId: sessionId,
          canManage: canManage,
        ),
      ),
    );
  }

  @override
  ConsumerState<AnnouncementListPage> createState() =>
      _AnnouncementListPageState();
}

class _AnnouncementListPageState extends ConsumerState<AnnouncementListPage> {
  late AnnouncementListController _controller;
  String _keyword = '';
  bool _onlyUnconfirmed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnnouncementListController(
      ref.read(announcementApiProvider),
      widget.sessionId,
      includeDrafts: false,
      statusFilter: 1,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openManage() async {
    await AnnouncementManagePage.open(
      context,
      sessionId: widget.sessionId,
    );
    await _controller.loadList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final perms = _controller.permissions;
        final hasManagementRole = perms?.hasManagementRole ?? widget.canManage;
        final showManageEntry = perms?.hasManageEntry ?? widget.canManage;
        final pendingCount = perms?.pendingReviewCount ?? 0;
        final manageLabel = hasManagementRole ? '管理' : '我的投稿';

        return Scaffold(
          appBar: AppBar(
            title: const Text('群公告'),
            actions: [
              if (showManageEntry)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Badge(
                    isLabelVisible: pendingCount > 0,
                    label: Text('$pendingCount'),
                    child: TextButton.icon(
                      icon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
                      label: Text(manageLabel),
                      onPressed: _openManage,
                    ),
                  ),
                ),
            ],
          ),
          body: _buildBody(context, theme, colorScheme, showManageEntry, manageLabel),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    bool showManageEntry,
    String manageLabel,
  ) {
    if (_controller.loading && _controller.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_controller.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.campaign_outlined,
              size: 64,
              color: colorScheme.outlineVariant,
            ),
            const SizedBox(height: 12),
            Text('当前会话暂无已发布公告', style: TextStyle(color: colorScheme.outline)),
            if (showManageEntry) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.tune),
                label: Text('打开$manageLabel'),
                onPressed: _openManage,
              ),
            ],
          ],
        ),
      );
    }

    final kw = _keyword.trim().toLowerCase();
    final filteredItems = _controller.items.where((item) {
      if (_onlyUnconfirmed &&
          (!item.requireConfirm ||
              item.isSelfConfirmed ||
              item.isExpired ||
              !item.isEffectiveForCurrentUser)) {
        return false;
      }
      if (kw.isEmpty) return true;
      return item.title.toLowerCase().contains(kw) ||
          item.content.toLowerCase().contains(kw);
    }).toList(growable: false);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: '搜索公告标题或内容...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: colorScheme.outlineVariant),
                      ),
                    ),
                    onChanged: (val) => setState(() => _keyword = val),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('仅看未确认', style: TextStyle(fontSize: 12)),
                selected: _onlyUnconfirmed,
                visualDensity: VisualDensity.compact,
                onSelected: (selected) => setState(() => _onlyUnconfirmed = selected),
              ),
            ],
          ),
        ),
        Expanded(
          child: filteredItems.isEmpty
              ? Center(
                  child: Text(
                    '无匹配公告',
                    style: TextStyle(color: colorScheme.outline),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _controller.loadList,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: filteredItems.length,
                    itemBuilder: (context, index) {
                      final item = filteredItems[index];
                      return _buildAnnouncementCard(context, item);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildAnnouncementCard(
    BuildContext context,
    SessionAnnouncement item,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasManagementRole = _controller.permissions?.hasManagementRole ?? widget.canManage;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          AnnouncementDetailDialog.show(
            context,
            announcement: item,
            canManage: hasManagementRole,
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'v${item.version}',
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (item.isPinned) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.push_pin, size: 12, color: Colors.red),
                          const SizedBox(width: 2),
                          Text(
                            item.sorting > 1 ? '置顶(${item.sorting.toStringAsFixed(0)})' : '置顶',
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (item.isExpired) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '已过期',
                        style: TextStyle(color: colorScheme.outline, fontSize: 11),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (item.requireConfirm) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (item.isSelfConfirmed ? Colors.green : Colors.blue)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item.isSelfConfirmed ? '已确认' : '需确认',
                        style: TextStyle(
                          color: item.isSelfConfirmed ? Colors.green : Colors.blue,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      item.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                item.content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${item.publisherName ?? "管理员"} · ${item.creationTime.length > 16 ? item.creationTime.substring(0, 16).replaceAll("T", " ") : item.creationTime}',
                    style: TextStyle(fontSize: 11, color: colorScheme.outline),
                  ),
                  Row(
                    children: [
                      Icon(
                        Icons.remove_red_eye_outlined,
                        size: 14,
                        color: colorScheme.outline,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${item.readCount}',
                        style: TextStyle(fontSize: 12, color: colorScheme.outline),
                      ),
                      if (item.requireConfirm) ...[
                        const SizedBox(width: 12),
                        const Icon(
                          Icons.check_circle_outline,
                          size: 14,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${item.confirmedCount}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
