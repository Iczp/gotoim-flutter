import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/announcement_providers.dart';
import '../data/models/session_announcement.dart';
import 'announcement_edit_page.dart';
import 'announcement_stat_sheet.dart';
import 'widgets/announcement_detail_dialog.dart';

class AnnouncementManagePage extends ConsumerStatefulWidget {
  const AnnouncementManagePage({
    required this.sessionId,
    this.sessionUnitId,
    this.sessionTitle,
    this.isEmbedded = false,
    this.onChanged,
    super.key,
  });

  final String sessionId;
  final String? sessionUnitId;
  final String? sessionTitle;
  final bool isEmbedded;
  final VoidCallback? onChanged;

  static Future<bool?> open(
    BuildContext context, {
    required String sessionId,
    String? sessionUnitId,
    String? sessionTitle,
  }) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AnnouncementManagePage(
          sessionId: sessionId,
          sessionUnitId: sessionUnitId,
          sessionTitle: sessionTitle,
        ),
      ),
    );
  }

  @override
  ConsumerState<AnnouncementManagePage> createState() => _AnnouncementManagePageState();
}

class _AnnouncementManagePageState extends ConsumerState<AnnouncementManagePage> {
  late AnnouncementListController _controller;
  int? _selectedStatus; // null=全部, 3=待审核, 1=已发布, 0=草稿, 4=已驳回, 2=已撤回
  String _keyword = '';
  bool _hasChanged = false;

  @override
  void initState() {
    super.initState();
    _controller = AnnouncementListController(
      ref.read(announcementApiProvider),
      widget.sessionId,
      includeDrafts: true,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openCreate({SessionAnnouncement? editItem}) async {
    final saved = await AnnouncementEditPage.open(
      context,
      sessionId: widget.sessionId,
      editItem: editItem,
      permissions: _controller.permissions,
    );
    if (saved != null) {
      _hasChanged = true;
      await _controller.loadList();
      widget.onChanged?.call();
    }
  }

  Future<void> _showReviewDialog(SessionAnnouncement item, bool approved) async {
    final remarkCtrl = TextEditingController();
    var sendNotify = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(approved ? '审核通过并发布' : '驳回公告'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '《${item.title}》',
                style: const TextStyle(fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: remarkCtrl,
                maxLines: 3,
                maxLength: 500,
                decoration: InputDecoration(
                  hintText: approved ? '可选填写审核意见...' : '请填写驳回原因（建议填写）',
                  border: const OutlineInputBorder(),
                ),
              ),
              if (approved)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('群内发送通知卡片', style: TextStyle(fontSize: 13)),
                  value: sendNotify,
                  onChanged: (v) => setDialogState(() => sendNotify = v),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: approved
                  ? null
                  : FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(approved ? '通过' : '驳回'),
            ),
          ],
        ),
      ),
    );
    final remark = remarkCtrl.text.trim();
    remarkCtrl.dispose();
    if (confirmed != true || !mounted) return;

    try {
      await _controller.review(
        item.id,
        approved: approved,
        remark: remark.isEmpty ? null : remark,
        sendMessageNotification: sendNotify,
      );
      _hasChanged = true;
      widget.onChanged?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(approved ? '审核已通过' : '已驳回公告')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('审核操作失败: $e')),
        );
      }
    }
  }

  Future<void> _showPinWeightDialog(SessionAnnouncement item) async {
    final weightCtrl = TextEditingController(
      text: (item.sorting > 0 ? item.sorting : (item.isPinned ? 1 : 0)).toStringAsFixed(0),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('调整置顶权重'),
        content: TextField(
          controller: weightCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: '0 表示不置顶，数字越大越靠前',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    final w = double.tryParse(weightCtrl.text.trim()) ?? 0;
    weightCtrl.dispose();
    if (confirmed == true) {
      await ref.read(announcementApiProvider).setPinned(
            id: item.id,
            isPinned: w > 0,
            sorting: w,
          );
      _hasChanged = true;
      await _controller.loadList();
      widget.onChanged?.call();
    }
  }

  Future<void> _handleDelete(SessionAnnouncement item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除公告'),
        content: Text('确定要删除公告「${item.title}」吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _controller.delete(item.id);
      _hasChanged = true;
      widget.onChanged?.call();
    }
  }

  ({String label, Color color}) _statusBadge(SessionAnnouncement item, ColorScheme cs) {
    switch (item.status) {
      case 3:
        return (label: '待审核', color: Colors.indigo);
      case 1:
        return (label: '已发布', color: Colors.green);
      case 0:
        return (label: item.publishTime != null ? '定时' : '草稿', color: Colors.amber.shade800);
      case 4:
        return (label: '已驳回', color: Colors.red);
      case 2:
        return (label: '已撤回', color: cs.outline);
      default:
        return (label: '未知', color: cs.outline);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          Navigator.of(context).pop(_hasChanged);
        }
      },
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final perms = _controller.permissions;
          final allItems = _controller.items;
          final kw = _keyword.trim().toLowerCase();

          final pendingCount = allItems.where((e) => e.status == 3).length;
          final publishedCount = allItems.where((e) => e.status == 1).length;
          final draftCount = allItems.where((e) => e.status == 0).length;
          final rejectedCount = allItems.where((e) => e.status == 4).length;
          final revokedCount = allItems.where((e) => e.status == 2).length;

          final filtered = allItems.where((item) {
            if (_selectedStatus != null && item.status != _selectedStatus) return false;
            if (kw.isEmpty) return true;
            return item.title.toLowerCase().contains(kw) ||
                item.content.toLowerCase().contains(kw) ||
                (item.publisherName ?? '').toLowerCase().contains(kw);
          }).toList(growable: false);

          final canCreate = perms?.canCreate ?? true;
          final canPublish = perms?.canPublish ?? false;

          final body = Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    _filterChip('全部 (${allItems.length})', null),
                    const SizedBox(width: 6),
                    _filterChip('待审核 ($pendingCount)', 3),
                    const SizedBox(width: 6),
                    _filterChip('已发布 ($publishedCount)', 1),
                    const SizedBox(width: 6),
                    _filterChip('草稿 ($draftCount)', 0),
                    const SizedBox(width: 6),
                    _filterChip('已驳回 ($rejectedCount)', 4),
                    const SizedBox(width: 6),
                    _filterChip('已撤回 ($revokedCount)', 2),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 36,
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: '搜索标题、内容或发布人...',
                            prefixIcon: const Icon(Icons.search, size: 18),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide(color: colorScheme.outlineVariant),
                            ),
                          ),
                          onChanged: (v) => setState(() => _keyword = v),
                        ),
                      ),
                    ),
                    if (widget.isEmbedded && canCreate) ...[
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        icon: const Icon(Icons.add, size: 16),
                        label: Text(canPublish ? '新建公告' : '投稿'),
                        onPressed: () => _openCreate(),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: _controller.loading && allItems.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : filtered.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '当前筛选状态下暂无公告',
                                  style: TextStyle(color: colorScheme.outline),
                                ),
                                if (canCreate && allItems.isEmpty) ...[
                                  const SizedBox(height: 12),
                                  FilledButton.tonalIcon(
                                    icon: const Icon(Icons.add),
                                    label: Text(canPublish ? '发布公告' : '提交公告审阅'),
                                    onPressed: () => _openCreate(),
                                  ),
                                ],
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _controller.loadList,
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) =>
                                  _buildManageCard(context, filtered[index]),
                            ),
                          ),
              ),
            ],
          );

          if (widget.isEmbedded) {
            return body;
          }

          return Scaffold(
            appBar: AppBar(
              title: Text(perms?.hasManagementRole != false ? '公告管理与审核' : '我的公告投稿'),
              actions: [
                if (canCreate)
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: canPublish ? '新建公告' : '投稿公告',
                    onPressed: () => _openCreate(),
                  ),
              ],
            ),
            body: body,
          );
        },
      ),
    );
  }

  Widget _filterChip(String label, int? statusValue) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: _selectedStatus == statusValue,
      visualDensity: VisualDensity.compact,
      onSelected: (_) => setState(() => _selectedStatus = statusValue),
    );
  }

  Widget _buildManageCard(BuildContext context, SessionAnnouncement item) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final badge = _statusBadge(item, colorScheme);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          AnnouncementDetailDialog.show(
            context,
            announcement: item,
            sessionTitle: widget.sessionTitle,
            canManage: true,
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _pill(badge.label, badge.color),
                  const SizedBox(width: 6),
                  _pill('v${item.version}', colorScheme.primary),
                  if (item.isPinned) ...[
                    const SizedBox(width: 6),
                    _pill(
                      item.sorting > 1
                          ? '置顶(${item.sorting.toStringAsFixed(0)})'
                          : '置顶',
                      Colors.red,
                    ),
                  ],
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.title,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                item.content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(
                    '发布人: ${item.publisherName ?? "成员"}',
                    style: TextStyle(fontSize: 11, color: colorScheme.outline),
                  ),
                  if (item.reviewerName != null && item.reviewerName!.isNotEmpty)
                    Text(
                      '审核人: ${item.reviewerName}'
                      '${item.reviewRemark != null && item.reviewRemark!.isNotEmpty ? " (${item.reviewRemark})" : ""}',
                      style: const TextStyle(fontSize: 11, color: Colors.indigo),
                    )
                  else if (item.reviewRemark != null && item.reviewRemark!.isNotEmpty)
                    Text(
                      '审核意见: ${item.reviewRemark}',
                      style: const TextStyle(fontSize: 11, color: Colors.redAccent),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.end,
                children: [
                  if (item.canApprove && item.status == 3) ...[
                    FilledButton.tonal(
                      onPressed: () => _showReviewDialog(item, true),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      child: const Text('审核通过', style: TextStyle(fontSize: 12)),
                    ),
                    OutlinedButton(
                      onPressed: () => _showReviewDialog(item, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      child: const Text('驳回', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                  if (item.canSubmitReview)
                    OutlinedButton(
                      onPressed: () async {
                        await _controller.submitReview(item.id);
                        _hasChanged = true;
                        widget.onChanged?.call();
                      },
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      child: const Text('提交审核', style: TextStyle(fontSize: 12)),
                    ),
                  if (item.canPublish && item.status == 0)
                    FilledButton.tonal(
                      onPressed: () async {
                        await _controller.publish(item.id);
                        _hasChanged = true;
                        widget.onChanged?.call();
                      },
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      child: const Text('立即发布', style: TextStyle(fontSize: 12)),
                    ),
                  if (item.canViewStat && item.status == 1)
                    TextButton(
                      onPressed: () => AnnouncementStatSheet.show(
                        context,
                        announcementId: item.id,
                        title: item.title,
                        sessionUnitId: widget.sessionUnitId,
                      ),
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      child: Text('统计 (${item.readCount})', style: const TextStyle(fontSize: 12)),
                    ),
                  if (item.canPin && item.status == 1)
                    TextButton(
                      onPressed: () => _showPinWeightDialog(item),
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      child: Text(item.isPinned ? '权重(${item.sorting.toStringAsFixed(0)})' : '置顶',
                          style: const TextStyle(fontSize: 12)),
                    ),
                  if (item.canEdit)
                    TextButton(
                      onPressed: () => _openCreate(editItem: item),
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      child: Text(item.status == 1 ? '修订升版' : '编辑',
                          style: const TextStyle(fontSize: 12)),
                    ),
                  if (item.canRevoke && item.status == 1)
                    TextButton(
                      onPressed: () async {
                        await _controller.revoke(item.id);
                        _hasChanged = true;
                        widget.onChanged?.call();
                      },
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      child: const Text('撤回', style: TextStyle(fontSize: 12)),
                    ),
                  if (item.canDelete)
                    TextButton(
                      onPressed: () => _handleDelete(item),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('删除', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
