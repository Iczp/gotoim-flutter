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

  bool _isPinned = false;
  bool _isPopup = false;
  bool _requireConfirm = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final item = widget.editItem;
    if (item != null) {
      _titleController.text = item.title;
      _contentController.text = item.content;
      _isPinned = item.isPinned;
      _isPopup = item.isPopup;
      _requireConfirm = item.requireConfirm;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
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
      if (widget.editItem != null) {
        result = await api.update(
          id: widget.editItem!.id,
          title: title,
          content: content,
          isPinned: _isPinned,
          isPopup: _isPopup,
          requireConfirm: _requireConfirm,
        );
      } else {
        result = await api.create(
          sessionId: widget.sessionId,
          title: title,
          content: content,
          isPinned: _isPinned,
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
                      subtitle: const Text('在聊天界面顶部横幅展示 (单会话唯一)'),
                      value: _isPinned,
                      onChanged: (val) => setState(() => _isPinned = val),
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
