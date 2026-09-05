import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/target_picker/target_picker.dart';
import '../../session/application/session_list_controller.dart';
import '../../session/data/models/session_summary.dart';
import '../data/room_api.dart';

class CreateGroupPage extends ConsumerStatefulWidget {
  const CreateGroupPage({super.key});

  @override
  ConsumerState<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends ConsumerState<CreateGroupPage> {
  bool _isCreating = false;

  Future<void> _handleFaceToFaceGroup() async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final codeController = TextEditingController();
    final nameController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('面对面建群'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '与身边的朋友输入同样的四个数字，即可进入同一个群聊',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: codeController,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  autofocus: true,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                  ),
                  decoration: InputDecoration(
                    hintText: '----',
                    counterText: '',
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  maxLength: 20,
                  decoration: const InputDecoration(
                    labelText: '群聊名称（可选）',
                    hintText: '默认：面对面群 + 数字码',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  if (codeController.text.trim().length != 4) {
                    showToast('请输入完整的4位数字建群码', type: ToastType.warning);
                    return;
                  }
                  Navigator.of(dialogContext).pop(true);
                },
                child: const Text('立即进入/创建'),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final code = codeController.text.trim();
    final customName = nameController.text.trim();
    final groupName = customName.isNotEmpty ? customName : '面对面群 $code';

    final sessionController = ref.read(sessionListControllerProvider);
    final ownerId = sessionController.currentOwner?.id;
    if (ownerId == null) {
      showToast('当前无可用聊天身份，请先登录', type: ToastType.warning);
      return;
    }

    setState(() => _isCreating = true);
    try {
      showToast('正在创建群聊...', type: ToastType.info);
      await ref.read(roomApiProvider).createRoom(
        name: groupName,
        ownerId: ownerId,
        code: code,
        type: 0,
        description: '面对面建群(码:$code)',
        chatObjectIdList: const <int>[],
      );
      showToast('面对面建群成功', type: ToastType.success);
      ref.read(sessionListControllerProvider.notifier).refreshChanges();
      if (mounted) context.pop();
    } catch (e) {
      showToast('建群失败: $e', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Future<void> _handleFriendsGroup() async {
    final sessionController = ref.read(sessionListControllerProvider);
    final ownerId = sessionController.currentOwner?.id;
    if (ownerId == null) {
      showToast('当前无可用聊天身份，请先登录', type: ToastType.warning);
      return;
    }

    // 从当前会话与好友列表构建选择候选项（过滤掉群聊 session.type == 2）
    final sessions = sessionController.sessions;
    final candidateFriends = sessions.where((s) {
      final sessionType = s.raw['session']?['type'];
      return sessionType != 2;
    }).toList();

    if (candidateFriends.isEmpty) {
      showToast('当前通讯录暂无好友，可先添加好友', type: ToastType.info);
      return;
    }

    final items = candidateFriends.map((s) {
      return TargetPickerItem.fromSessionSummary(s);
    }).toList();

    final selected = await TargetPicker.pickMultiple<SessionSummary>(
      context: context,
      items: items,
      title: '选择联系人发起群聊',
      minCount: 1,
      maxCount: 50,
    );

    if (selected == null || selected.isEmpty || !mounted) return;

    final selectedNames = selected.map((e) => e.title).toList();
    final groupName = '群(${selectedNames.take(3).join('、')}${selectedNames.length > 3 ? '等' : ''})';

    final chatObjectIdList = selected
        .map((e) {
          final dest = e.data?.raw['destination'];
          if (dest is Map) {
            final destId = dest['id'];
            if (destId is int) return destId;
            return int.tryParse(destId?.toString() ?? '') ?? 0;
          }
          return int.tryParse(e.id) ?? 0;
        })
        .where((id) => id > 0)
        .toList();

    setState(() => _isCreating = true);
    try {
      showToast('正在创建群聊...', type: ToastType.info);
      await ref.read(roomApiProvider).createRoom(
        name: groupName,
        ownerId: ownerId,
        code: '',
        type: 0,
        description: groupName,
        chatObjectIdList: chatObjectIdList,
      );
      showToast('群聊创建成功', type: ToastType.success);
      ref.read(sessionListControllerProvider.notifier).refreshChanges();
      if (mounted) context.pop();
    } catch (e) {
      showToast('创建群聊失败: $e', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('创建群聊'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '创建群聊天',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.dialpad_rounded,
                      color: colorScheme.primary,
                      size: 22,
                    ),
                  ),
                  title: const Text(
                    '面对面建群',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '通过4位数字进群码，与身边朋友快速建群',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  enabled: !_isCreating,
                  onTap: _handleFaceToFaceGroup,
                ),
                Divider(
                  height: 1,
                  indent: 68,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
                ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.group_add_rounded,
                      color: colorScheme.secondary,
                      size: 22,
                    ),
                  ),
                  title: const Text(
                    '好友建群',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '从通讯录好友中选择人员发起多人聊天',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  enabled: !_isCreating,
                  onTap: _handleFriendsGroup,
                ),
              ],
            ),
          ),
          if (_isCreating)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}
