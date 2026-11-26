import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/utils/message_text_formatter.dart';
import '../../../chat_settings/data/models/chat_member.dart';
import '../../../chat_settings/presentation/member_profile_sheet.dart';
import '../../application/announcement_providers.dart';
import '../../data/models/session_announcement.dart';
import '../announcement_stat_sheet.dart';

class AnnouncementDetailDialog extends ConsumerStatefulWidget {
  const AnnouncementDetailDialog({
    required this.announcement,
    this.sessionUnitId,
    this.sessionTitle,
    this.canManage = false,
    this.isBottomSheet = false,
    super.key,
  });

  final SessionAnnouncement announcement;
  final String? sessionUnitId;
  final String? sessionTitle;
  final bool canManage;
  final bool isBottomSheet;

  static Future<bool?> show(
    BuildContext context, {
    required SessionAnnouncement announcement,
    String? sessionUnitId,
    String? sessionTitle,
    bool canManage = false,
  }) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    if (isMobile) {
      return showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          final sheetHeight = (MediaQuery.sizeOf(sheetContext).height * 0.65)
              .clamp(360.0, 680.0);
          return SizedBox(
            height: sheetHeight,
            child: AnnouncementDetailDialog(
              announcement: announcement,
              sessionUnitId: sessionUnitId,
              sessionTitle: sessionTitle,
              canManage: canManage,
              isBottomSheet: true,
            ),
          );
        },
      );
    }
    return showDialog<bool>(
      context: context,
      builder: (_) => AnnouncementDetailDialog(
        announcement: announcement,
        sessionUnitId: sessionUnitId,
        sessionTitle: sessionTitle,
        canManage: canManage,
      ),
    );
  }

  @override
  ConsumerState<AnnouncementDetailDialog> createState() =>
      _AnnouncementDetailDialogState();
}

class _AnnouncementDetailDialogState
    extends ConsumerState<AnnouncementDetailDialog> {
  late SessionAnnouncement _item;
  List<SessionAnnouncement> _navList = const [];
  bool _confirming = false;
  bool _navLoading = false;

  String get _effectiveSessionUnitId => (widget.sessionUnitId ?? '').trim();

  @override
  void initState() {
    super.initState();
    _item = widget.announcement;
    // 自动上报已读
    if (_effectiveSessionUnitId.isNotEmpty) {
      ref
          .read(announcementApiProvider)
          .recordView(_item.id, sessionUnitId: _effectiveSessionUnitId);
    }
    if (_item.content.isEmpty) {
      _loadDetail();
    }
    _loadNavList();
  }

  Future<void> _loadDetail() async {
    final uid = _effectiveSessionUnitId;
    if (uid.isEmpty) return;
    final detail = await ref
        .read(announcementApiProvider)
        .getDetail(_item.id, sessionUnitId: uid);
    if (mounted && detail != null) {
      setState(() => _item = detail);
    }
  }

  Future<void> _loadNavList() async {
    final uid = _effectiveSessionUnitId;
    if (uid.isEmpty) return;
    try {
      final list = await ref.read(announcementApiProvider).getList(
            sessionUnitId: uid,
            maxResultCount: 100,
          );
      if (!mounted) return;
      setState(() {
        _navList = list;
      });
    } catch (_) {
      // ignore nav list error
    }
  }

  int get _currentIndex => _navList.indexWhere((e) => e.id == _item.id);
  bool get _hasPrev => _currentIndex > 0;
  bool get _hasNext => _currentIndex >= 0 && _currentIndex < _navList.length - 1;

  Future<void> _navigateToIndex(int index) async {
    final uid = _effectiveSessionUnitId;
    if (index < 0 || index >= _navList.length || _navLoading || uid.isEmpty) return;
    final target = _navList[index];
    setState(() => _navLoading = true);
    try {
      final api = ref.read(announcementApiProvider);
      final detail = await api.getDetail(target.id, sessionUnitId: uid);
      if (!mounted) return;
      if (detail != null) {
        setState(() {
          _item = detail;
          _navList = [
            for (var i = 0; i < _navList.length; i++)
              if (i == index) detail else _navList[i],
          ];
        });
        api.recordView(detail.id, sessionUnitId: uid);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('切换公告失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _navLoading = false);
    }
  }

  Future<void> _handleConfirm() async {
    final uid = _effectiveSessionUnitId;
    if (uid.isEmpty) return;
    setState(() => _confirming = true);
    try {
      await ref
          .read(announcementApiProvider)
          .confirm(_item.id, sessionUnitId: uid);
      if (mounted) {
        setState(() {
          _item = _item.copyWith(
            isSelfConfirmed: true,
            confirmedCount: _item.confirmedCount + 1,
          );
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已确认收到公告')),
        );
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  void _openStat({int initialTabIndex = 0}) {
    Navigator.of(context).pop();
    AnnouncementStatSheet.show(
      context,
      announcementId: _item.id,
      title: _item.title,
      sessionUnitId: _effectiveSessionUnitId,
      initialTabIndex: initialTabIndex,
    );
  }

  Future<void> _showRevisionsDialog() async {
    final uid = _effectiveSessionUnitId;
    if (uid.isEmpty) return;
    final revisions = await ref
        .read(announcementApiProvider)
        .getRevisions(_item.id, sessionUnitId: uid);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('历史修订版本'),
        content: SizedBox(
          width: 440,
          height: 340,
          child: revisions.isEmpty
              ? const Center(child: Text('暂无历史修订记录'))
              : ListView.separated(
                  itemCount: revisions.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, idx) {
                    final rev = revisions[idx];
                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(ctx).colorScheme.outlineVariant,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(ctx)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'v${rev.version}',
                                  style: TextStyle(
                                    color: Theme.of(ctx).colorScheme.primary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  rev.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '修订人: ${rev.editorName ?? "管理员"}'
                            '${rev.changeSummary != null && rev.changeSummary!.isNotEmpty ? " · ${rev.changeSummary}" : ""}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(ctx).colorScheme.outline,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            rev.content,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _openMemberById(String id, String displayName, {String? avatar}) {
    if (id.isEmpty) return;
    showMemberProfileSheet(
      context,
      ChatMember.fromJson(<String, dynamic>{
        'id': id,
        'displayName': displayName,
        'owner': <String, dynamic>{
          if (int.tryParse(id) != null) 'id': int.parse(id),
          'displayName': displayName,
          if (avatar != null) 'portrait': avatar,
        },
      }),
    );
  }

  Future<void> _handleAppLinkTap(String text, String? href) async {
    final rawHref = (href ?? '').trim();
    if (rawHref.isEmpty) return;
    final parsed = parseAppLinkUri(rawHref);
    if (parsed == null) return;

    final id = parsed.id;
    switch (parsed.route) {
      case 'session-unit':
      case 'chat-object':
        _openMemberById(id, text.isNotEmpty ? text : '成员 $id');
        return;
      case 'announcement':
        if (id.isEmpty) return;
        final idx = _navList.indexWhere((e) => e.id == id);
        if (idx >= 0) {
          await _navigateToIndex(idx);
          return;
        }
        final uid = _effectiveSessionUnitId;
        if (uid.isEmpty) return;
        setState(() => _navLoading = true);
        try {
          final api = ref.read(announcementApiProvider);
          final detail = await api.getDetail(id, sessionUnitId: uid);
          if (mounted && detail != null) {
            setState(() => _item = detail);
            api.recordView(detail.id, sessionUnitId: uid);
          }
        } finally {
          if (mounted) setState(() => _navLoading = false);
        }
        return;
      case 'copy':
        final copyText = parsed.params['text'] ?? id;
        if (copyText.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: copyText));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已复制到剪贴板')),
            );
          }
        }
        return;
      case 'mention':
        final mentionName = (parsed.params['name'] ?? text).replaceFirst(RegExp(r'^@'), '').trim();
        if (mentionName.isNotEmpty && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('提及成员: @$mentionName')),
          );
        }
        return;
      case 'settings':
        if (mounted) {
          Navigator.of(context).pop();
          context.push('/settings');
        }
        return;
      case 'nav':
        final tab = parsed.params['tab'];
        if (mounted && tab == 'workbench') {
          Navigator.of(context).pop();
          context.push('/workbench');
        }
        return;
      case 'announcement-stat':
        final statTab = parsed.params['tab'];
        final tabIdx = switch (statTab) {
          'read' => 1,
          'unread' => 2,
          'confirmed' => 3,
          'unconfirmed' => 4,
          _ => 0,
        };
        if (mounted && widget.canManage) {
          _openStat(initialTabIndex: tabIdx);
        }
        return;
      case 'file':
      case 'browser':
        final targetUrl = (parsed.params['url'] ?? id).trim();
        if (targetUrl.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: targetUrl));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已复制链接: $targetUrl')),
            );
          }
        }
        return;
      default:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('暂不支持快捷指令: ${parsed.route}')),
          );
        }
    }
  }

  void _showImagePreview(String imageUrl, String? caption) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black87,
        insetPadding: const EdgeInsets.all(24),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Center(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      '图片加载失败',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              ),
            ),
            if (caption != null && caption.trim().isNotEmpty)
              Positioned(
                left: 16,
                right: 56,
                bottom: 16,
                child: Text(
                  caption,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openPublisherProfile() {
    final unitId = _item.publisherSessionUnitId;
    final chatObjectId = _item.publisherChatObjectId;
    if (unitId.isEmpty && chatObjectId.isEmpty) return;
    final name = _item.publisherName ?? '管理员';
    showMemberProfileSheet(
      context,
      ChatMember.fromJson(<String, dynamic>{
        'id': unitId.isNotEmpty ? unitId : chatObjectId,
        'displayName': name,
        'owner': <String, dynamic>{
          if (chatObjectId.isNotEmpty) 'id': int.tryParse(chatObjectId) ?? chatObjectId,
          'displayName': name,
          if (_item.publisherAvatar != null) 'portrait': _item.publisherAvatar,
        },
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = (screenSize.width * 0.62).clamp(420.0, 820.0);
    final dialogHeight = (screenSize.height * 0.62).clamp(320.0, 680.0);
    final headerTitle = (widget.sessionTitle?.trim().isNotEmpty == true)
        ? '${widget.sessionTitle!.trim()} 公告'
        : '公告详情';

    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        widget.isBottomSheet ? 6 : 12,
        16,
        widget.isBottomSheet ? 10 : 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.isBottomSheet)
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          Row(
                children: [
                  Expanded(
                    child: Text(
                      headerTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colorScheme.outline,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (_item.isPinned) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '置顶',
                        style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: SelectionArea(
                      child: Text(
                        _item.title,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '发布人: ',
                        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline),
                      ),
                      InkWell(
                        onTap: _openPublisherProfile,
                        borderRadius: BorderRadius.circular(4),
                        child: Text(
                          _item.publisherName ?? '管理员',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    _item.creationTime.length > 16
                        ? _item.creationTime.substring(0, 16).replaceAll('T', ' ')
                        : _item.creationTime,
                    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline),
                  ),
                  if (_item.reviewerName != null && _item.reviewerName!.isNotEmpty)
                    Text(
                      '审核人: ${_item.reviewerName}',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.indigo),
                    ),
                  if (_item.reviewRemark != null && _item.reviewRemark!.isNotEmpty)
                    Text(
                      '审核意见: ${_item.reviewRemark}',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.indigo),
                    ),
                ],
              ),
              const Divider(height: 12),
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      height: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colorScheme.outlineVariant),
                      ),
                      child: SingleChildScrollView(
                        child: SelectionArea(
                          child: _item.editorType == 1
                              ? MarkdownBody(
                                  data: preprocessAnnouncementMarkdownLinks(_item.content),
                                  selectable: false,
                                  shrinkWrap: true,
                                  styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                                    p: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                                    pPadding: const EdgeInsets.only(bottom: 4),
                                    blockSpacing: 6,
                                  ),
                                  onTapLink: (text, href, _) =>
                                      _handleAppLinkTap(text, href),
                                  imageBuilder: (uri, title, alt) {
                                    final imageUrl = uri.toString();
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                      child: GestureDetector(
                                        onTap: () => _showImagePreview(imageUrl, alt ?? title),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: ConstrainedBox(
                                            constraints: const BoxConstraints(
                                              maxHeight: 280,
                                            ),
                                            child: Image.network(
                                              imageUrl,
                                              fit: BoxFit.contain,
                                              errorBuilder: (_, _, _) => Container(
                                                padding: const EdgeInsets.all(12),
                                                decoration: BoxDecoration(
                                                  color: colorScheme.surfaceContainerHighest,
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.broken_image_outlined,
                                                      size: 18,
                                                      color: colorScheme.outline,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Flexible(
                                                      child: Text(
                                                        alt?.isNotEmpty == true ? alt! : '图片加载失败',
                                                        style: theme.textTheme.bodySmall,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                )
                              : Text.rich(
                                  TextSpan(
                                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
                                    children: parseMessageTagsToSpans(
                                      _item.content,
                                      parseMentions: true,
                                      textStyle:
                                          theme.textTheme.bodyMedium?.copyWith(height: 1.55) ??
                                          const TextStyle(),
                                      linkStyle: (theme.textTheme.bodyMedium ?? const TextStyle())
                                          .copyWith(
                                        color: colorScheme.primary,
                                        decoration: TextDecoration.underline,
                                      ),
                                      onSessionUnitTap: (uid, name) =>
                                          _openMemberById(uid, name),
                                      onChatObjectTap: (oid, name) =>
                                          _openMemberById(oid, name),
                                      onAppLinkTap: (node) =>
                                          _handleAppLinkTap(node.text, node.href),
                                      onMentionTap: (name) =>
                                          _handleAppLinkTap('@$name', 'im://mention?name=${Uri.encodeComponent(name)}'),
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                    if (_navLoading)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(child: CircularProgressIndicator()),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 12),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (widget.canManage)
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        InkWell(
                          onTap: () => _openStat(initialTabIndex: 1),
                          borderRadius: BorderRadius.circular(4),
                          child: Text(
                            '已读 ${_item.readCount} 人',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => _openStat(initialTabIndex: 2),
                          borderRadius: BorderRadius.circular(4),
                          child: Text(
                            '未读',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.orange.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (_item.requireConfirm) ...[
                          InkWell(
                            onTap: () => _openStat(initialTabIndex: 3),
                            borderRadius: BorderRadius.circular(4),
                            child: Text(
                              '已确认 ${_item.confirmedCount} 人',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () => _openStat(initialTabIndex: 4),
                            borderRadius: BorderRadius.circular(4),
                            child: Text(
                              '待确认',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.orange.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ],
                    )
                  else
                    Text(
                      '已读 ${_item.readCount} 人'
                      '${_item.requireConfirm ? " · 已确认 ${_item.confirmedCount} 人" : ""}',
                      style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline),
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_navList.length > 1) ...[
                        IconButton(
                          tooltip: '上一条',
                          icon: const Icon(Icons.chevron_left, size: 20),
                          visualDensity: VisualDensity.compact,
                          onPressed: (_hasPrev && !_navLoading)
                              ? () => _navigateToIndex(_currentIndex - 1)
                              : null,
                        ),
                        if (_currentIndex >= 0)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              '${_currentIndex + 1} / ${_navList.length}',
                              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline),
                            ),
                          ),
                        IconButton(
                          tooltip: '下一条',
                          icon: const Icon(Icons.chevron_right, size: 20),
                          visualDensity: VisualDensity.compact,
                          onPressed: (_hasNext && !_navLoading)
                              ? () => _navigateToIndex(_currentIndex + 1)
                              : null,
                        ),
                      ],
                      if (widget.canManage && _item.version > 1)
                        IconButton(
                          tooltip: '历史版本',
                          icon: const Icon(Icons.history, size: 18),
                          visualDensity: VisualDensity.compact,
                          onPressed: _showRevisionsDialog,
                        ),
                      if (widget.canManage || _item.canViewStat)
                        IconButton(
                          tooltip: '查看统计',
                          icon: const Icon(Icons.pie_chart_outline, size: 18),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _openStat(),
                        ),
                      if (_item.requireConfirm) ...[
                        const SizedBox(width: 4),
                        FilledButton.icon(
                          icon: const Icon(Icons.check_circle_outline, size: 16),
                          label: Text(
                            _item.isSelfConfirmed
                                ? '已确认'
                                : (_item.isExpired ? '已过期' : '确认收到'),
                          ),
                          onPressed:
                              (_item.isSelfConfirmed || _item.isExpired || _confirming)
                                  ? null
                                  : _handleConfirm,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
    );

    if (widget.isBottomSheet) {
      return Material(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(top: false, child: content),
      );
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: content,
      ),
    );
  }
}
