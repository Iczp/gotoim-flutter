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
    this.sessionTitle,
    this.canManage = false,
    super.key,
  });

  final SessionAnnouncement announcement;
  final String? sessionTitle;
  final bool canManage;

  static Future<bool?> show(
    BuildContext context, {
    required SessionAnnouncement announcement,
    String? sessionTitle,
    bool canManage = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AnnouncementDetailDialog(
        announcement: announcement,
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

  @override
  void initState() {
    super.initState();
    _item = widget.announcement;
    // 自动上报已读
    ref.read(announcementApiProvider).recordView(_item.id);
    _loadNavList();
  }

  Future<void> _loadNavList() async {
    final sid = _item.sessionId.trim();
    if (sid.isEmpty) return;
    try {
      final list = await ref.read(announcementApiProvider).getList(
            sessionId: sid,
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
    if (index < 0 || index >= _navList.length || _navLoading) return;
    final target = _navList[index];
    setState(() => _navLoading = true);
    try {
      final api = ref.read(announcementApiProvider);
      final detail = await api.getDetail(target.id);
      if (!mounted) return;
      if (detail != null) {
        setState(() {
          _item = detail;
          _navList = [
            for (var i = 0; i < _navList.length; i++)
              if (i == index) detail else _navList[i],
          ];
        });
        api.recordView(detail.id);
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
    setState(() => _confirming = true);
    try {
      await ref.read(announcementApiProvider).confirm(_item.id);
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
      initialTabIndex: initialTabIndex,
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
        setState(() => _navLoading = true);
        try {
          final api = ref.read(announcementApiProvider);
          final detail = await api.getDetail(id);
          if (mounted && detail != null) {
            setState(() => _item = detail);
            api.recordView(detail.id);
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

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
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
                    child: SelectableText(
                      _item.title,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
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
                ],
              ),
              const Divider(height: 20),
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      height: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colorScheme.outlineVariant),
                      ),
                      child: SingleChildScrollView(
                        child: _item.editorType == 1
                            ? MarkdownBody(
                                data: preprocessAnnouncementMarkdownLinks(_item.content),
                                selectable: true,
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
                            : SelectableText.rich(
                                TextSpan(
                                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                                  children: parseMessageTagsToSpans(
                                    _item.content,
                                    parseMentions: true,
                                    textStyle:
                                        theme.textTheme.bodyMedium?.copyWith(height: 1.6) ??
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
              const Divider(height: 20),
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
                      if (widget.canManage)
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
        ),
      ),
    );
  }
}
