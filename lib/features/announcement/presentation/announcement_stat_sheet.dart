import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/announcement_providers.dart';
import '../data/models/session_announcement.dart';
import '../../session/presentation/chat_object_avatar.dart';

class AnnouncementStatSheet extends ConsumerStatefulWidget {
  const AnnouncementStatSheet({
    required this.announcementId,
    required this.title,
    super.key,
  });

  final String announcementId;
  final String title;

  static Future<void> show(
    BuildContext context, {
    required String announcementId,
    required String title,
  }) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 720;
    if (isDesktop) {
      return showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
            child: AnnouncementStatSheet(
              announcementId: announcementId,
              title: title,
            ),
          ),
        ),
      );
    }

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.85,
        child: AnnouncementStatSheet(
          announcementId: announcementId,
          title: title,
        ),
      ),
    );
  }

  @override
  ConsumerState<AnnouncementStatSheet> createState() =>
      _AnnouncementStatSheetState();
}

class _AnnouncementStatSheetState extends ConsumerState<AnnouncementStatSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final AnnouncementStatController _controller;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _controller = AnnouncementStatController(
      ref.read(announcementApiProvider),
      widget.announcementId,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final stat = _controller.stat;

        return Column(
          children: [
            // 头部标题栏
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '公告统计 - ${widget.title}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // 概览指标卡片网格
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _buildStatCard('总人数', '${stat?.totalMemberCount ?? 0}', Colors.grey),
                  const SizedBox(width: 8),
                  _buildStatCard(
                    '已读 (${(stat?.readRate ?? 0).toStringAsFixed(0)}%)',
                    '${stat?.readCount ?? 0}',
                    Colors.green,
                  ),
                  const SizedBox(width: 8),
                  _buildStatCard('未读', '${stat?.unreadCount ?? 0}', Colors.orange),
                  const SizedBox(width: 8),
                  _buildStatCard(
                    '已确认 (${(stat?.confirmedRate ?? 0).toStringAsFixed(0)}%)',
                    '${stat?.confirmedCount ?? 0}',
                    Colors.blue,
                  ),
                ],
              ),
            ),

            // Tab 栏
            TabBar(
              controller: _tabController,
              labelColor: colorScheme.primary,
              unselectedLabelColor: colorScheme.outline,
              indicatorSize: TabBarIndicatorSize.label,
              onTap: (index) {
                _controller.setFilterType(index);
              },
              tabs: [
                const Tab(text: '全部'),
                Tab(text: '已读 (${stat?.readCount ?? 0})'),
                Tab(text: '未读 (${stat?.unreadCount ?? 0})'),
                Tab(text: '已确认 (${stat?.confirmedCount ?? 0})'),
              ],
            ),

            // 搜索框
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: SizedBox(
                height: 38,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: '搜索姓名...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: colorScheme.outlineVariant),
                    ),
                  ),
                  onChanged: (text) => _controller.setKeyword(text),
                ),
              ),
            ),

            // 成员列表
            Expanded(
              child: _controller.loadingMembers && _controller.members.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _controller.members.isEmpty
                      ? Center(
                          child: Text(
                            '无成员数据',
                            style: TextStyle(color: colorScheme.outline),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _controller.members.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final member = _controller.members[index];
                            return _buildMemberTile(context, member);
                          },
                        ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(color: color, fontSize: 11)),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberTile(BuildContext context, SessionAnnouncementMember member) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListTile(
      leading: ChatObjectAvatar(
        name: member.name,
        imageUrl: member.portrait,
        size: 38,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              member.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          if (member.isCreator) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('群主', style: TextStyle(color: Colors.amber, fontSize: 10)),
            ),
          ] else if (member.isAdmin) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('管理员', style: TextStyle(color: Colors.blue, fontSize: 10)),
            ),
          ],
        ],
      ),
      subtitle: Text(
        member.firstReadTime != null
            ? '首次阅读: ${member.firstReadTime!.length > 16 ? member.firstReadTime!.substring(0, 16).replaceAll("T", " ") : member.firstReadTime}'
            : '未查看',
        style: TextStyle(
          fontSize: 11,
          color: member.firstReadTime != null ? colorScheme.outline : Colors.orange,
        ),
      ),
      trailing: member.isConfirmed
          ? const Chip(
              label: Text('已确认', style: TextStyle(fontSize: 11, color: Colors.green)),
              backgroundColor: Color(0x1500FF00),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            )
          : member.firstReadTime != null
              ? const Chip(
                  label: Text('未确认', style: TextStyle(fontSize: 11)),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                )
              : null,
    );
  }
}
