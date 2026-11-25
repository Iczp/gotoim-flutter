import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/session_announcement.dart';
import '../application/announcement_providers.dart';

class AnnouncementEditPage extends ConsumerStatefulWidget {
  const AnnouncementEditPage({
    required this.sessionId,
    this.sessionUnitId,
    this.editItem,
    this.permissions,
    super.key,
  });

  final String sessionId;
  final String? sessionUnitId;
  final SessionAnnouncement? editItem;
  final SessionAnnouncementPermissions? permissions;

  static Future<SessionAnnouncement?> open(
    BuildContext context, {
    required String sessionId,
    String? sessionUnitId,
    SessionAnnouncement? editItem,
    SessionAnnouncementPermissions? permissions,
  }) {
    return Navigator.of(context).push<SessionAnnouncement>(
      MaterialPageRoute<SessionAnnouncement>(
        builder: (_) => AnnouncementEditPage(
          sessionId: sessionId,
          sessionUnitId: sessionUnitId,
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

      final effectiveSessionUnitId =
          (widget.sessionUnitId != null && widget.sessionUnitId!.isNotEmpty)
              ? widget.sessionUnitId!
              : (_permissions?.sessionUnitId.isNotEmpty == true
                  ? _permissions!.sessionUnitId
                  : widget.sessionId);

      if (widget.editItem != null) {
        result = await api.update(
          id: widget.editItem!.id,
          sessionUnitId: effectiveSessionUnitId,
          title: title,
          content: content,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allowPrimaryPublish = _canDirectPublish || _isEditingPublished;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.editItem != null ? '编辑公告' : '发布新公告'),
        actions: [
          TextButton(
            onPressed: _submitting ? null : () => _handleSubmit(saveAsDraft: true),
            child: const Text('存草稿'),
          ),
          if (_canDirectPublish && (widget.editItem == null || widget.editItem!.status == 0 || widget.editItem!.status == 4))
            TextButton(
              onPressed: _submitting ? null : () => _handleSubmit(submitForReview: true),
              child: const Text('提审'),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _submitting
                  ? null
                  : () => allowPrimaryPublish
                      ? _handleSubmit()
                      : _handleSubmit(submitForReview: true),
              child: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      allowPrimaryPublish
                          ? (_publishMode == 'scheduled'
                              ? '定时发布'
                              : _isEditingPublished
                                  ? '保存修订'
                                  : '发布')
                          : '提交审核',
                    ),
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
                    if (_canPin) ...[
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
                    const Divider(height: 1),
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
                              initialDate: _customPublishTime ?? now.add(const Duration(days: 1)),
                              firstDate: now,
                              lastDate: now.add(const Duration(days: 365)),
                            );
                            if (pickedDate != null && context.mounted) {
                              final pickedTime = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.fromDateTime(
                                  _customPublishTime ?? now.add(const Duration(hours: 1)),
                                ),
                              );
                              if (mounted) {
                                final t = pickedTime ?? const TimeOfDay(hour: 9, minute: 0);
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
                      const Divider(height: 1),
                      SwitchListTile(
                        title: Text('升版修订 (v${(widget.editItem?.version ?? 1) + 1})'),
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
                      const Divider(height: 1),
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
            ),
          ],
        ),
      ),
    );
  }
}
