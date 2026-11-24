import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/session_announcement.dart';
import '../application/announcement_providers.dart';

class AnnouncementEditPage extends ConsumerStatefulWidget {
  const AnnouncementEditPage({
    required this.sessionId,
    this.editItem,
    super.key,
  });

  final String sessionId;
  final SessionAnnouncement? editItem;

  static Future<SessionAnnouncement?> open(
    BuildContext context, {
    required String sessionId,
    SessionAnnouncement? editItem,
  }) {
    return Navigator.of(context).push<SessionAnnouncement>(
      MaterialPageRoute<SessionAnnouncement>(
        builder: (_) => AnnouncementEditPage(
          sessionId: sessionId,
          editItem: editItem,
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

  bool _isPinned = false;
  bool _isPopup = false;
  bool _requireConfirm = false;
  bool _applyToNewMembers = false;
  String _expireMode = 'never'; // never | 7d | 30d | custom
  DateTime? _customExpireTime;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final item = widget.editItem;
    if (item != null) {
      _titleController.text = item.title;
      _contentController.text = item.content;
      final effectiveSort = item.sorting > 0 ? item.sorting : (item.isPinned ? 1.0 : 0.0);
      _sortingController.text = effectiveSort.toStringAsFixed(0);
      _isPinned = effectiveSort > 0;
      _isPopup = item.isPopup;
      _requireConfirm = item.requireConfirm;
      _applyToNewMembers = item.applyToNewMembers;
      if (item.expireTime != null && item.expireTime!.isNotEmpty) {
        _expireMode = 'custom';
        _customExpireTime = DateTime.tryParse(item.expireTime!);
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _sortingController.dispose();
    super.dispose();
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

  Future<void> _handleSubmit() async {
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
      final effectiveSorting = parsedSorting > 0 ? parsedSorting : (_isPinned ? 1.0 : 0.0);
      final effectivePinned = effectiveSorting > 0;
      final expireTimeIso = _resolveExpireTimeIso();

      if (widget.editItem != null) {
        result = await api.update(
          id: widget.editItem!.id,
          title: title,
          content: content,
          isPinned: effectivePinned,
          sorting: effectiveSorting,
          expireTime: expireTimeIso,
          applyToNewMembers: _applyToNewMembers,
          isPopup: _isPopup,
          requireConfirm: _requireConfirm,
        );
      } else {
        result = await api.create(
          sessionId: widget.sessionId,
          title: title,
          content: content,
          isPinned: effectivePinned,
          sorting: effectiveSorting,
          expireTime: expireTimeIso,
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
          SnackBar(content: Text('发布失败: $err')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.editItem != null ? '编辑公告' : '发布新公告'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: FilledButton(
              onPressed: _submitting ? null : _handleSubmit,
              child: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('发布'),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _titleController,
              maxLength: 128,
              decoration: const InputDecoration(
                labelText: '公告标题',
                hintText: '简明醒目的标题',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _contentController,
              maxLength: 10000,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: '公告内容',
                hintText: '详细正文内容...',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('置顶公告'),
                      subtitle: const Text('0=不置顶；数字越大越置顶（支持多条置顶）'),
                      value: _isPinned,
                      onChanged: (val) {
                        setState(() {
                          _isPinned = val;
                          final cur = double.tryParse(_sortingController.text.trim()) ?? 0;
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
                    const Divider(height: 1),
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
                              initialDate: _customExpireTime ?? now.add(const Duration(days: 7)),
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
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('弹窗强提醒'),
                      subtitle: const Text('群成员打开聊天窗口时弹窗提醒'),
                      value: _isPopup,
                      onChanged: (val) => setState(() => _isPopup = val),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('要求成员确认收到'),
                      subtitle: const Text('展示“确认收到”按钮并记录确认名单'),
                      value: _requireConfirm,
                      onChanged: (val) => setState(() => _requireConfirm = val),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('对新入群 / 重入群成员生效'),
                      subtitle: const Text('关闭时仅对发布时已在群成员生效'),
                      value: _applyToNewMembers,
                      onChanged: (val) => setState(() => _applyToNewMembers = val),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
