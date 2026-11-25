import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/announcement_providers.dart';
import '../data/models/session_announcement.dart';
import '../../chat_settings/data/models/chat_member.dart';
import '../../chat_settings/presentation/member_profile_sheet.dart';
import '../../session/presentation/chat_object_avatar.dart';

class AnnouncementStatSheet extends ConsumerStatefulWidget {
  const AnnouncementStatSheet({
    required this.announcementId,
    required this.title,
    this.sessionUnitId,
    this.initialTabIndex = 0,
    super.key,
  });

  final String announcementId;
  final String title;
  final String? sessionUnitId;
  final int initialTabIndex;

  static Future<void> show(
    BuildContext context, {
    required String announcementId,
    required String title,
    String? sessionUnitId,
    int initialTabIndex = 0,
  }) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 720;
    if (isDesktop) {
      return showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
            child: AnnouncementStatSheet(
              announcementId: announcementId,
              title: title,
              sessionUnitId: sessionUnitId,
              initialTabIndex: initialTabIndex,
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
          sessionUnitId: sessionUnitId,
          initialTabIndex: initialTabIndex,
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
    final safeInitial = widget.initialTabIndex.clamp(0, 4);
    _tabController = TabController(
      length: 5,
      initialIndex: safeInitial,
      vsync: this,
    );
    _controller = AnnouncementStatController(
      ref.read(announcementApiProvider),
      widget.announcementId,
    );
    if (safeInitial != 0) {
      _controller.setFilterType(safeInitial);
    }
  }

  void _switchToTab(int index) {
    final safeIndex = index.clamp(0, 4);
    _tabController.animateTo(safeIndex);
    _controller.setFilterType(safeIndex);
  }

  void _openMemberProfile(SessionAnnouncementMember member) {
    showMemberProfileSheet(
      context,
      ChatMember.fromJson(<String, dynamic>{
        'id': member.sessionUnitId,
        'displayName': member.name,
        'owner': <String, dynamic>{
          'id': member.chatObjectId,
          'displayName': member.name,
          if (member.portrait != null) 'portrait': member.portrait,
        },
      }),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _copyRemindText() async {
    final list = _controller.members;
    if (list.isEmpty) return;
    final names = list.map((m) => m.name.trim()).where((n) => n.isNotEmpty).toList();
    if (names.isEmpty) return;
    final mentions = names.map((n) => '@$n').join(' ');
    final tabIdx = _tabController.index;
    final tip = tabIdx == 4
        ? '请及时确认收到公告'
        : tabIdx == 2
            ? '请及时查看公告'
            : '请关注公告';
    final text = '$mentions $tip《${widget.title}》';
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已复制 ${names.length} 位成员的 @催办文案')),
      );
    }
  }

  Future<void> _sendServerRemind() async {
    try {
      final api = ref.read(announcementApiProvider);
      final unitId = widget.sessionUnitId?.trim() ?? '';
      if (unitId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('缺少当前成员身份，无法发送催办')),
          );
        }
        return;
      }
      final count = await api.remindUnconfirmed(
        widget.announcementId,
        sessionUnitId: unitId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              count > 0 ? '已向群内发送催办提醒（待确认 $count 人）' : '所有成员均已确认',
            ),
          ),
        );
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送催办失败: $err')),
        );
      }
    }
  }

  Future<void> _copyMemberList() async {
    final list = _controller.members;
    if (list.isEmpty) return;
    final lines = <String>[
      '姓名\t角色\t阅读状态\t确认状态\t首次阅读时间',
      ...list.map((m) {
        final role = m.isCreator ? '群主' : (m.isAdmin ? '管理员' : '成员');
        final read = m.firstReadTime != null ? '已读' : '未读';
        final confirmed = m.isConfirmed ? '已确认' : '未确认';
        final time = m.firstReadTime ?? '';
        return '${m.name}\t$role\t$read\t$confirmed\t$time';
      }),
    ];
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已复制 ${list.length} 条成员统计名单')),
      );
    }
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

            // 概览指标卡片网格（点击直接定位对应人员列表）
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _buildStatCard('总人数', '${stat?.totalMemberCount ?? 0}', Colors.grey, () => _switchToTab(0)),
                  const SizedBox(width: 8),
                  _buildStatCard(
                    '已读 (${(stat?.readRate ?? 0).toStringAsFixed(0)}%)',
                    '${stat?.readCount ?? 0}',
                    Colors.green,
                    () => _switchToTab(1),
                  ),
                  const SizedBox(width: 8),
                  _buildStatCard('未读', '${stat?.unreadCount ?? 0}', Colors.orange, () => _switchToTab(2)),
                  const SizedBox(width: 8),
                  _buildStatCard(
                    '已确认 (${(stat?.confirmedRate ?? 0).toStringAsFixed(0)}%)',
                    '${stat?.confirmedCount ?? 0}',
                    Colors.blue,
                    () => _switchToTab(3),
                  ),
                ],
              ),
            ),

            // Tab 栏
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
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
                Tab(
                  text:
                      '待确认 (${((stat?.totalMemberCount ?? 0) - (stat?.confirmedCount ?? 0)).clamp(0, 999999)})',
                ),
              ],
            ),

            // 搜索框与快捷催办/导出操作
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 36,
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
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: '复制 @催办文案',
                    icon: const Icon(Icons.campaign_outlined, size: 20),
                    onPressed: _controller.members.isEmpty ? null : _copyRemindText,
                  ),
                  IconButton(
                    tooltip: '发送群内催办提醒',
                    icon: const Icon(Icons.notifications_active_outlined, size: 20),
                    onPressed: _sendServerRemind,
                  ),
                  IconButton(
                    tooltip: '复制统计名单',
                    icon: const Icon(Icons.copy_all_outlined, size: 20),
                    onPressed: _controller.members.isEmpty ? null : _copyMemberList,
                  ),
                ],
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

  Widget _buildStatCard(
    String label,
    String value,
    Color color,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
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
      ),
    );
  }

  Widget _buildMemberTile(BuildContext context, SessionAnnouncementMember member) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListTile(
      onTap: () => _openMemberProfile(member),
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
