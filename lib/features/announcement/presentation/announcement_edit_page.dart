import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/application_providers.dart';
import '../../../core/utils/message_text_formatter.dart';
import '../../../core/widgets/two_line_app_bar_title.dart';
import '../../chat_settings/data/datasources/chat_member_api.dart';
import '../../chat_settings/data/models/chat_member.dart';
import '../../session/presentation/chat_object_avatar.dart';
import '../application/announcement_providers.dart';
import '../data/models/session_announcement.dart';

class AnnouncementEditPage extends ConsumerStatefulWidget {
  const AnnouncementEditPage({
    required this.sessionId,
    this.sessionUnitId,
    this.sessionTitle,
    this.editItem,
    this.permissions,
    super.key,
  });

  final String sessionId;
  final String? sessionUnitId;
  final String? sessionTitle;
  final SessionAnnouncement? editItem;
  final SessionAnnouncementPermissions? permissions;

  static Future<SessionAnnouncement?> open(
    BuildContext context, {
    required String sessionId,
    String? sessionUnitId,
    String? sessionTitle,
    SessionAnnouncement? editItem,
    SessionAnnouncementPermissions? permissions,
  }) {
    return Navigator.of(context).push<SessionAnnouncement>(
      MaterialPageRoute<SessionAnnouncement>(
        builder: (_) => AnnouncementEditPage(
          sessionId: sessionId,
          sessionUnitId: sessionUnitId,
          sessionTitle: sessionTitle,
          editItem: editItem,
          permissions: permissions,
        ),
      ),
    );
  }

  @override
  ConsumerState<AnnouncementEditPage> createState() =>
      _AnnouncementEditPageState();
}

class _AnnouncementEditPageState extends ConsumerState<AnnouncementEditPage> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _sortingController = TextEditingController(text: '0');
  final _changeSummaryController = TextEditingController();

  SessionAnnouncementPermissions? _permissions;
  int _editorType = 1; // 1: 富文本 Markdown, 0: 纯文本
  bool _previewMode = false;
  List<ChatMember>? _cachedMembers;
  bool _isPinned = false;
  bool _isPopup = false;
  bool _requireConfirm = false;
  bool _applyToNewMembers = false;
  bool _resetReceipts = false;
  bool _bumpVersion = true;
  String _expireMode = 'never'; // never | 7d | 30d | custom
  DateTime? _customExpireTime;
  String _publishMode = 'now'; // now | scheduled
  DateTime? _customPublishTime;
  bool _submitting = false;

  String get _effectiveSessionUnitId =>
      (widget.sessionUnitId != null && widget.sessionUnitId!.isNotEmpty)
          ? widget.sessionUnitId!
          : (_permissions?.sessionUnitId.isNotEmpty == true
              ? _permissions!.sessionUnitId
              : widget.sessionId);

  @override
  void initState() {
    super.initState();
    _permissions = widget.permissions;
    if (_permissions == null) {
      final permLookupId =
          (widget.sessionUnitId != null && widget.sessionUnitId!.isNotEmpty)
              ? widget.sessionUnitId!
              : widget.sessionId;
      ref.read(announcementApiProvider).getPermissions(permLookupId).then((value) {
        if (mounted && value != null) {
          setState(() => _permissions = value);
        }
      });
    }
    final item = widget.editItem;
    if (item != null) {
      _titleController.text = item.title;
      _contentController.text = item.content;
      _editorType = item.editorType;
      final effectiveSort = item.sorting > 0 ? item.sorting : (item.isPinned ? 1.0 : 0.0);
      _sortingController.text = effectiveSort.toStringAsFixed(0);
      _isPinned = effectiveSort > 0;
      _isPopup = item.isPopup;
      _requireConfirm = item.requireConfirm;
      _applyToNewMembers = item.applyToNewMembers;
      _bumpVersion = item.status == 1;
      if (item.expireTime != null && item.expireTime!.isNotEmpty) {
        _expireMode = 'custom';
        _customExpireTime = DateTime.tryParse(item.expireTime!);
      }
      if (item.publishTime != null && item.publishTime!.isNotEmpty) {
        _publishMode = 'scheduled';
        _customPublishTime = DateTime.tryParse(item.publishTime!);
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _sortingController.dispose();
    _changeSummaryController.dispose();
    super.dispose();
  }

  void _insertAtCursor(
    String before, [
    String after = '',
    String placeholder = '',
  ]) {
    final text = _contentController.text;
    final selection = _contentController.selection;
    final hasSelection = selection.isValid;
    final start = hasSelection ? selection.start.clamp(0, text.length) : text.length;
    final end = hasSelection ? selection.end.clamp(0, text.length) : text.length;
    final selected = start < end ? text.substring(start, end) : placeholder;
    final inserted = '$before$selected$after';
    final nextText = text.replaceRange(start, end, inserted);
    final cursorOffset =
        selected.isNotEmpty && after.isNotEmpty && start == end
            ? start + before.length
            : start + inserted.length;
    final selectionEnd =
        selected.isNotEmpty && after.isNotEmpty && start == end
            ? start + before.length + selected.length
            : cursorOffset;
    _contentController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection(
        baseOffset: cursorOffset,
        extentOffset: selectionEnd,
      ),
    );
  }

  Future<void> _insertLinkDialog() async {
    final labelCtrl = TextEditingController();
    final urlCtrl = TextEditingController(text: 'https://');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('插入链接'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelCtrl,
              decoration: const InputDecoration(
                labelText: '链接文字',
                hintText: '例如：查看文档',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(
                labelText: '链接地址',
                hintText: 'https://...',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: WeChatPageStyle.primaryButtonStyle(ctx),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('插入'),
          ),
        ],
      ),
    );
    final label = labelCtrl.text.trim();
    final url = urlCtrl.text.trim();
    labelCtrl.dispose();
    urlCtrl.dispose();
    if (confirmed == true && url.isNotEmpty) {
      final effectiveLabel = label.isNotEmpty ? label : url;
      _insertAtCursor('[$effectiveLabel]($url)');
    }
  }

  Future<List<ChatMember>> _loadMembers() async {
    if (_cachedMembers != null) return _cachedMembers!;
    final uid = _effectiveSessionUnitId;
    if (uid.isEmpty) return const <ChatMember>[];
    final api = ChatMemberApi(ref.read(apiClientProvider));
    final page = await api.getMembers(sessionUnitId: uid, limit: 100);
    _cachedMembers = page.items;
    return page.items;
  }

  Future<void> _openMentionMemberPicker() async {
    final membersFuture = _loadMembers();
    final selected = await showModalBottomSheet<({bool all, ChatMember? member})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        var keyword = '';
        return FractionallySizedBox(
          heightFactor: 0.72,
          child: StatefulBuilder(
            builder: (ctx, setSheetState) {
              final theme = Theme.of(ctx);
              final colorScheme = theme.colorScheme;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '选择要 @ 的成员',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: SizedBox(
                      height: 38,
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: '搜索群成员...',
                          prefixIcon: const Icon(Icons.search, size: 18),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          filled: true,
                          fillColor: colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.45),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (v) => setSheetState(() => keyword = v),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: FutureBuilder<List<ChatMember>>(
                      future: membersFuture,
                      builder: (_, snap) {
                        if (snap.connectionState == ConnectionState.waiting &&
                            !snap.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snap.hasError) {
                          return Center(
                            child: Text(
                              '加载成员失败: ${snap.error}',
                              style: TextStyle(color: colorScheme.error),
                            ),
                          );
                        }
                        final allMembers = snap.data ?? const <ChatMember>[];
                        final kw = keyword.trim().toLowerCase();
                        final filtered = kw.isEmpty
                            ? allMembers
                            : allMembers
                                .where(
                                  (m) => m.name.toLowerCase().contains(kw),
                                )
                                .toList(growable: false);

                        return ListView.separated(
                          itemCount: filtered.length + 1,
                          separatorBuilder: (_, _) => const Divider(
                            height: 1,
                            indent: 64,
                          ),
                          itemBuilder: (_, index) {
                            if (index == 0) {
                              return ListTile(
                                leading: CircleAvatar(
                                  radius: 19,
                                  backgroundColor: colorScheme.primary
                                      .withValues(alpha: 0.14),
                                  child: Icon(
                                    Icons.campaign_rounded,
                                    color: colorScheme.primary,
                                    size: 20,
                                  ),
                                ),
                                title: const Text(
                                  '所有人',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                subtitle: const Text(
                                  '@所有人',
                                  style: TextStyle(fontSize: 12),
                                ),
                                onTap: () => Navigator.pop(
                                  ctx,
                                  (all: true, member: null),
                                ),
                              );
                            }
                            final member = filtered[index - 1];
                            return ListTile(
                              leading: ChatObjectAvatar(
                                name: member.name,
                                imageUrl:
                                    member.avatarUrl.isNotEmpty
                                        ? member.avatarUrl
                                        : null,
                                radius: 19,
                                chatObjectId: member.chatObjectId,
                              ),
                              title: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      member.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (member.isCreator) ...[
                                    const SizedBox(width: 6),
                                    _roleTag('群主', Colors.amber),
                                  ] else if (member.isAdmin) ...[
                                    const SizedBox(width: 6),
                                    _roleTag('管理员', Colors.blue),
                                  ],
                                ],
                              ),
                              onTap: () => Navigator.pop(
                                ctx,
                                (all: false, member: member),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    if (selected == null || !mounted) return;
    if (selected.all) {
      _insertAtCursor('@所有人 ');
      return;
    }
    final member = selected.member;
    if (member == null) return;
    if (_editorType == 1) {
      _insertAtCursor('[@${member.name}](im://session-unit/${member.id}) ');
    } else {
      _insertAtCursor('@${member.name} ');
    }
  }

  static Widget _roleTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String? _resolveExpireTimeIso() {
    if (_expireMode == 'never') return null;
    if (_expireMode == '7d') {
      return DateTime.now().add(const Duration(days: 7)).toUtc().toIso8601String();
    }
    if (_expireMode == '30d') {
      return DateTime.now().add(const Duration(days: 30)).toUtc().toIso8601String();
    }
    return _customExpireTime?.toUtc().toIso8601String();
  }

  bool get _canDirectPublish => _permissions?.canPublish ?? true;
  bool get _canPin => _permissions?.canPin ?? true;
  bool get _isEditingPublished => widget.editItem?.status == 1;

  Future<void> _handleSubmit({
    bool saveAsDraft = false,
    bool submitForReview = false,
  }) async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入公告标题')),
      );
      return;
    }
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入公告内容')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final api = ref.read(announcementApiProvider);
      SessionAnnouncement result;
      final parsedSorting = double.tryParse(_sortingController.text.trim()) ?? 0;
      final effectiveSorting =
          _canPin ? (parsedSorting > 0 ? parsedSorting : (_isPinned ? 1.0 : 0.0)) : 0.0;
      final effectivePinned = _canPin && effectiveSorting > 0;
      final expireTimeIso = _resolveExpireTimeIso();
      final publishTimeIso = _publishMode == 'scheduled'
          ? _customPublishTime?.toUtc().toIso8601String()
          : null;
      final summary = _changeSummaryController.text.trim();

      final effectiveSessionUnitId = _effectiveSessionUnitId;

      if (widget.editItem != null) {
        result = await api.update(
          id: widget.editItem!.id,
          sessionUnitId: effectiveSessionUnitId,
          title: title,
          content: content,
          editorType: _editorType,
          isPinned: effectivePinned,
          sorting: effectiveSorting,
          expireTime: expireTimeIso,
          publishTime: publishTimeIso,
          saveAsDraft: saveAsDraft,
          submitForReview: submitForReview,
          bumpVersion: _isEditingPublished && _bumpVersion,
          changeSummary: _isEditingPublished && summary.isNotEmpty ? summary : null,
          expectedVersion: widget.editItem!.version,
          resetReceipts: _resetReceipts,
          applyToNewMembers: _applyToNewMembers,
          isPopup: _isPopup,
          requireConfirm: _requireConfirm,
        );
      } else {
        result = await api.create(
          sessionUnitId: effectiveSessionUnitId,
          title: title,
          content: content,
          editorType: _editorType,
          isPinned: effectivePinned,
          sorting: effectiveSorting,
          expireTime: expireTimeIso,
          publishTime: publishTimeIso,
          saveAsDraft: saveAsDraft,
          submitForReview: submitForReview,
          applyToNewMembers: _applyToNewMembers,
          isPopup: _isPopup,
          requireConfirm: _requireConfirm,
        );
      }

      if (mounted) {
        Navigator.of(context).pop(result);
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $err')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _buildFormatToolButton({
    required String label,
    required VoidCallback onTap,
    String? tooltip,
    bool highlighted = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Tooltip(
        message: tooltip ?? label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: highlighted
                  ? colorScheme.primary.withValues(alpha: 0.12)
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: highlighted ? FontWeight.w600 : FontWeight.w500,
                color: highlighted
                    ? colorScheme.primary
                    : colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final allowPrimaryPublish = _canDirectPublish || _isEditingPublished;
    final divider = Divider(
      height: 1,
      indent: 16,
      color: theme.dividerColor.withValues(alpha: 0.16),
    );

    return Scaffold(
      backgroundColor: WeChatPageStyle.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: WeChatPageStyle.appBarBg(context),
        scrolledUnderElevation: 0.5,
        title: TwoLineAppBarTitle(
          title: widget.editItem != null ? '编辑公告' : '发布公告',
          subtitle: widget.sessionTitle,
        ),
        actions: [
          TextButton(
            onPressed: _submitting ? null : () => _handleSubmit(saveAsDraft: true),
            child: const Text('存草稿'),
          ),
          if (_canDirectPublish &&
              (widget.editItem == null ||
                  widget.editItem!.status == 0 ||
                  widget.editItem!.status == 4))
            TextButton(
              onPressed:
                  _submitting ? null : () => _handleSubmit(submitForReview: true),
              child: const Text('提审'),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SizedBox(
              height: 34,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                onPressed: _submitting
                    ? null
                    : () => allowPrimaryPublish
                        ? _handleSubmit()
                        : _handleSubmit(submitForReview: true),
                child: _submitting
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        allowPrimaryPublish
                            ? (_publishMode == 'scheduled'
                                ? '定时发布'
                                : _isEditingPublished
                                    ? '保存修订'
                                    : '发布')
                            : '提交审核',
                        style: const TextStyle(fontSize: 13),
                      ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          WeChatPageStyle.pageHorizontalPadding,
          10,
          WeChatPageStyle.pageHorizontalPadding,
          24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              decoration: BoxDecoration(
                color: WeChatPageStyle.cardBg(context),
                borderRadius: WeChatPageStyle.cardRadius,
              ),
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
              child: TextField(
                controller: _titleController,
                maxLength: 128,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                decoration: const InputDecoration(
                  hintText: '请输入公告标题...',
                  border: InputBorder.none,
                  counterStyle: TextStyle(fontSize: 11),
                ),
              ),
            ),
            const SizedBox(height: WeChatPageStyle.sectionGap),
            Container(
              decoration: BoxDecoration(
                color: WeChatPageStyle.cardBg(context),
                borderRadius: WeChatPageStyle.cardRadius,
              ),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('富文本', style: TextStyle(fontSize: 12)),
                        selected: _editorType == 1,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => setState(() => _editorType = 1),
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('纯文本', style: TextStyle(fontSize: 12)),
                        selected: _editorType == 0,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => setState(() {
                          _editorType = 0;
                          _previewMode = false;
                        }),
                      ),
                      const Spacer(),
                      if (_editorType == 1)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: () =>
                              setState(() => _previewMode = !_previewMode),
                          icon: Icon(
                            _previewMode
                                ? Icons.edit_outlined
                                : Icons.visibility_outlined,
                            size: 16,
                          ),
                          label: Text(
                            _previewMode ? '继续编辑' : '预览效果',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                    ],
                  ),
                  if (!_previewMode) ...[
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFormatToolButton(
                            label: '@成员',
                            tooltip: '提及群成员',
                            highlighted: true,
                            onTap: _openMentionMemberPicker,
                          ),
                          if (_editorType == 1) ...[
                            _buildFormatToolButton(
                              label: 'H2',
                              tooltip: '标题',
                              onTap: () => _insertAtCursor('## '),
                            ),
                            _buildFormatToolButton(
                              label: 'B',
                              tooltip: '加粗',
                              onTap: () => _insertAtCursor('**', '**', '加粗文字'),
                            ),
                            _buildFormatToolButton(
                              label: 'I',
                              tooltip: '斜体',
                              onTap: () => _insertAtCursor('*', '*', '斜体文字'),
                            ),
                            _buildFormatToolButton(
                              label: 'S',
                              tooltip: '删除线',
                              onTap: () => _insertAtCursor('~~', '~~', '删除文字'),
                            ),
                            _buildFormatToolButton(
                              label: '列表',
                              tooltip: '无序列表',
                              onTap: () => _insertAtCursor('- '),
                            ),
                            _buildFormatToolButton(
                              label: '编号',
                              tooltip: '有序列表',
                              onTap: () => _insertAtCursor('1. '),
                            ),
                            _buildFormatToolButton(
                              label: '待办',
                              tooltip: '任务列表',
                              onTap: () => _insertAtCursor('- [ ] '),
                            ),
                            _buildFormatToolButton(
                              label: '引用',
                              tooltip: '引用块',
                              onTap: () => _insertAtCursor('> '),
                            ),
                            _buildFormatToolButton(
                              label: '代码',
                              tooltip: '行内代码',
                              onTap: () => _insertAtCursor('`', '`', '代码'),
                            ),
                            _buildFormatToolButton(
                              label: '链接',
                              tooltip: '插入链接',
                              onTap: _insertLinkDialog,
                            ),
                            _buildFormatToolButton(
                              label: '分割线',
                              tooltip: '插入分割线',
                              onTap: () => _insertAtCursor('\n---\n'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Divider(
                    height: 1,
                    color: theme.dividerColor.withValues(alpha: 0.16),
                  ),
                  const SizedBox(height: 8),
                  if (_previewMode && _editorType == 1)
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 180),
                      child: SelectionArea(
                        child: MarkdownBody(
                          data: preprocessAnnouncementMarkdownLinks(
                            _contentController.text.trim().isEmpty
                                ? '_暂无正文内容_'
                                : _contentController.text,
                          ),
                          selectable: false,
                          shrinkWrap: true,
                          styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                            p: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
                            pPadding: const EdgeInsets.only(bottom: 4),
                            blockSpacing: 6,
                          ),
                        ),
                      ),
                    )
                  else
                    TextField(
                      controller: _contentController,
                      maxLength: 10000,
                      minLines: 7,
                      maxLines: 14,
                      decoration: InputDecoration(
                        hintText:
                            _editorType == 1
                                ? '支持 Markdown 富文本与 @成员...'
                                : '请输入公告正文内容，可点击上方 @成员 插入提醒...',
                        border: InputBorder.none,
                        counterStyle: TextStyle(
                          fontSize: 11,
                          color: colorScheme.outline,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: WeChatPageStyle.sectionGap),
            Container(
              decoration: BoxDecoration(
                color: WeChatPageStyle.cardBg(context),
                borderRadius: WeChatPageStyle.cardRadius,
              ),
              child: Column(
                children: [
                  if (_canPin) ...[
                    SwitchListTile(
                      title: const Text('置顶公告'),
                      subtitle: const Text('0=不置顶；数字越大越靠前'),
                      value: _isPinned,
                      onChanged: (val) {
                        setState(() {
                          _isPinned = val;
                          final cur =
                              double.tryParse(_sortingController.text.trim()) ?? 0;
                          if (val && cur <= 0) {
                            _sortingController.text = '1';
                          } else if (!val) {
                            _sortingController.text = '0';
                          }
                        });
                      },
                    ),
                    if (_isPinned)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: TextField(
                          controller: _sortingController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '置顶权重（数字越大越靠前）',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    divider,
                  ],
                  ListTile(
                    title: const Text('有效期'),
                    subtitle: Text(
                      _expireMode == 'never'
                          ? '长期有效'
                          : _expireMode == '7d'
                              ? '7 天内有效'
                              : _expireMode == '30d'
                                  ? '30 天内有效'
                                  : (_customExpireTime != null
                                      ? '截止 ${_customExpireTime!.toLocal().toString().substring(0, 16)}'
                                      : '选择截止日期'),
                    ),
                    trailing: DropdownButton<String>(
                      value: _expireMode,
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(value: 'never', child: Text('长期有效')),
                        DropdownMenuItem(value: '7d', child: Text('7天')),
                        DropdownMenuItem(value: '30d', child: Text('30天')),
                        DropdownMenuItem(value: 'custom', child: Text('自定义')),
                      ],
                      onChanged: (val) async {
                        if (val == null) return;
                        if (val == 'custom') {
                          final now = DateTime.now();
                          final pickedDate = await showDatePicker(
                            context: context,
                            initialDate:
                                _customExpireTime ??
                                now.add(const Duration(days: 7)),
                            firstDate: now,
                            lastDate: now.add(const Duration(days: 3650)),
                          );
                          if (pickedDate != null && mounted) {
                            setState(() {
                              _expireMode = 'custom';
                              _customExpireTime = DateTime(
                                pickedDate.year,
                                pickedDate.month,
                                pickedDate.day,
                                23,
                                59,
                              );
                            });
                          }
                        } else {
                          setState(() => _expireMode = val);
                        }
                      },
                    ),
                  ),
                  divider,
                  SwitchListTile(
                    title: const Text('弹窗强提醒'),
                    subtitle: const Text('群成员打开聊天窗口时弹窗提醒'),
                    value: _isPopup,
                    onChanged: (val) => setState(() => _isPopup = val),
                  ),
                  divider,
                  SwitchListTile(
                    title: const Text('要求成员确认收到'),
                    subtitle: const Text('展示“确认收到”按钮并记录确认名单'),
                    value: _requireConfirm,
                    onChanged: (val) => setState(() => _requireConfirm = val),
                  ),
                  divider,
                  SwitchListTile(
                    title: const Text('对新入群 / 重入群成员生效'),
                    subtitle: const Text('关闭时仅对发布时已在群成员生效'),
                    value: _applyToNewMembers,
                    onChanged: (val) => setState(() => _applyToNewMembers = val),
                  ),
                  divider,
                  ListTile(
                    title: const Text('发布方式'),
                    subtitle: Text(
                      _publishMode == 'now'
                          ? '立即发布'
                          : (_customPublishTime != null
                              ? '定时 ${_customPublishTime!.toLocal().toString().substring(0, 16)}'
                              : '选择定时发布时间'),
                    ),
                    trailing: DropdownButton<String>(
                      value: _publishMode,
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(value: 'now', child: Text('立即发布')),
                        DropdownMenuItem(value: 'scheduled', child: Text('定时发布')),
                      ],
                      onChanged: (val) async {
                        if (val == null) return;
                        if (val == 'scheduled') {
                          final now = DateTime.now();
                          final pickedDate = await showDatePicker(
                            context: context,
                            initialDate:
                                _customPublishTime ??
                                now.add(const Duration(days: 1)),
                            firstDate: now,
                            lastDate: now.add(const Duration(days: 365)),
                          );
                          if (pickedDate != null && context.mounted) {
                            final pickedTime = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.fromDateTime(
                                _customPublishTime ??
                                    now.add(const Duration(hours: 1)),
                              ),
                            );
                            if (mounted) {
                              final t =
                                  pickedTime ??
                                  const TimeOfDay(hour: 9, minute: 0);
                              setState(() {
                                _publishMode = 'scheduled';
                                _customPublishTime = DateTime(
                                  pickedDate.year,
                                  pickedDate.month,
                                  pickedDate.day,
                                  t.hour,
                                  t.minute,
                                );
                              });
                            }
                          }
                        } else {
                          setState(() => _publishMode = 'now');
                        }
                      },
                    ),
                  ),
                  if (_isEditingPublished) ...[
                    divider,
                    SwitchListTile(
                      title: Text(
                        '升版修订 (v${(widget.editItem?.version ?? 1) + 1})',
                      ),
                      subtitle: const Text('留存历史版本快照，并要求确认最新版本号'),
                      value: _bumpVersion,
                      onChanged: (val) => setState(() => _bumpVersion = val),
                    ),
                    if (_bumpVersion)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: TextField(
                          controller: _changeSummaryController,
                          maxLength: 300,
                          decoration: const InputDecoration(
                            labelText: '修订说明（可选）',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                  ],
                  if (widget.editItem != null && _requireConfirm) ...[
                    divider,
                    SwitchListTile(
                      title: const Text('修改后要求成员重新确认'),
                      subtitle: const Text('清空既有确认回执'),
                      value: _resetReceipts,
                      onChanged: (val) => setState(() => _resetReceipts = val),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
