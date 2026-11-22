import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/session_announcement.dart';
import '../application/announcement_providers.dart';
import 'widgets/announcement_detail_dialog.dart';
import 'announcement_stat_sheet.dart';
import 'announcement_edit_page.dart';

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

  @override
  void initState() {
    super.initState();
    _controller = AnnouncementListController(
      ref.read(announcementApiProvider),
      widget.sessionId,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('群公告与通知'),
        actions: [
          if (widget.canManage)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: '发布公告',
              onPressed: () async {
                final created = await AnnouncementEditPage.open(
                  context,
                  sessionId: widget.sessionId,
                );
                if (created != null) {
                  _controller.loadList();
                }
              },
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
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
                  Text('当前会话暂无公告', style: TextStyle(color: colorScheme.outline)),
                  if (widget.canManage) ...[
                    const SizedBox(height: 16),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.add),
                      label: const Text('发布首条公告'),
                      onPressed: () async {
                        final created = await AnnouncementEditPage.open(
                          context,
                          sessionId: widget.sessionId,
                        );
                        if (created != null) {
                          _controller.loadList();
                        }
                      },
                    ),
                  ],
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _controller.loadList,
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _controller.items.length,
              itemBuilder: (context, index) {
                final item = _controller.items[index];
                return _buildAnnouncementCard(context, item);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildAnnouncementCard(
    BuildContext context,
    SessionAnnouncement item,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
            canManage: widget.canManage,
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (item.isPinned) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.push_pin, size: 12, color: Colors.red),
                          SizedBox(width: 2),
                          Text(
                            '置顶',
                            style: TextStyle(
                              color: Colors.red,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (item.requireConfirm) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '需确认',
                        style: TextStyle(color: Colors.blue, fontSize: 11),
                      ),
                    ),
                    const SizedBox(width: 8),
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
                  if (widget.canManage)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 18),
                      padding: EdgeInsets.zero,
                      onSelected: (val) async {
                        if (val == 'stat') {
                          AnnouncementStatSheet.show(
                            context,
                            announcementId: item.id,
                            title: item.title,
                          );
                        } else if (val == 'pin') {
                          await _controller.togglePin(item);
                        } else if (val == 'edit') {
                          final updated = await AnnouncementEditPage.open(
                            context,
                            sessionId: widget.sessionId,
                            editItem: item,
                          );
                          if (updated != null) {
                            _controller.loadList();
                          }
                        } else if (val == 'delete') {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('删除公告'),
                              content: Text('确定要删除公告「${item.title}」吗？'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('取消'),
                                ),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.red,
                                  ),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('删除'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await _controller.delete(item.id);
                          }
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'stat',
                          child: Text('查看已读/未读统计'),
                        ),
                        PopupMenuItem(
                          value: 'pin',
                          child: Text(item.isPinned ? '取消置顶' : '置顶此条'),
                        ),
                        const PopupMenuItem(value: 'edit', child: Text('编辑公告')),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('删除', style: TextStyle(color: Colors.red)),
                        ),
                      ],
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
                    item.creationTime.length > 16
                        ? item.creationTime
                            .substring(0, 16)
                            .replaceAll('T', ' ')
                        : item.creationTime,
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
