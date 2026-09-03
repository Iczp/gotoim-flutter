import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/app_avatar.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../session/application/session_list_controller.dart';
import '../../session/data/models/session_summary.dart';
import '../application/chat_settings_controller.dart';

/// 修改群名称独立页面
///
/// 参考 UniApp 路径: `src/pages/im/sessions/group-name.vue`
class GroupNamePage extends ConsumerStatefulWidget {
  const GroupNamePage({
    required this.ownerId,
    required this.sessionUnitId,
    this.initialTitle,
    super.key,
  });

  final int ownerId;
  final String sessionUnitId;
  final String? initialTitle;

  @override
  ConsumerState<GroupNamePage> createState() => _GroupNamePageState();
}

class _GroupNamePageState extends ConsumerState<GroupNamePage> {
  late final ChatSettingsController _controller;
  late final TextEditingController _textController;
  final FocusNode _focusNode = FocusNode();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialTitle ?? '');
    _controller = ChatSettingsController(
      ref.read(chatSettingsRepositoryProvider),
      ref.read(sessionRepositoryProvider),
      ownerId: widget.ownerId,
      sessionUnitId: widget.sessionUnitId,
    )..addListener(_onControllerUpdated);
    _controller.initialize();
  }

  void _onControllerUpdated() {
    if (_textController.text.isEmpty && _controller.title.isNotEmpty) {
      setState(() {
        _textController.text = _controller.title;
      });
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdated);
    _controller.dispose();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _textController.text.trim();
    if (name.isEmpty) {
      showToast('群名称不能为空', type: ToastType.warning);
      return;
    }
    if (name == _controller.title) {
      Navigator.pop(context, false);
      return;
    }
    setState(() => _saving = true);
    try {
      await _controller.setGroupName(name);
      if (mounted) {
        showToast('群名称已更新', type: ToastType.success);
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        showToast('更新群名称失败：$e', type: ToastType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String? _avatarFor(SessionSummary? friend) {
    if (friend == null) return null;
    final destination = friend.raw['destination'];
    if (destination is Map) {
      final value = destination['thumbnail'] ?? destination['portrait'];
      if (value != null && '$value'.isNotEmpty) return '$value';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentTitle = _controller.title.isNotEmpty
        ? _controller.title
        : (widget.initialTitle ?? '');

    return Scaffold(
      appBar: AppBar(
        title: const Text('修改群名称'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      '完成',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        child: Column(
          children: [
            AppAvatar(
              imageUrl: _avatarFor(_controller.friend),
              name: currentTitle,
              radius: 32,
            ),
            const SizedBox(height: 16),
            Text(
              '修改群名称',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '修改群名称后,将在群内通知其他成员',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 28),
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.3),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Text(
                    '名称:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      focusNode: _focusNode,
                      maxLength: 100,
                      decoration: InputDecoration(
                        hintText: currentTitle.isNotEmpty ? currentTitle : '请输入群名称',
                        border: InputBorder.none,
                        counterText: '',
                        suffixIcon: _textController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.cancel, size: 18),
                                onPressed: () {
                                  _textController.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _save(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 36),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        '完成',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
