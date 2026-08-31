import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/avatar_preferences.dart';
import '../../session/application/session_list_controller.dart';
import '../application/avatar_edit_controller.dart';

class AvatarSettingsPage extends ConsumerWidget {
  const AvatarSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(avatarPreferencesProvider);
    final editor = ref.watch(avatarEditControllerProvider);
    final owner = ref.watch(sessionListControllerProvider).currentOwner;
    final busy =
        editor.status == AvatarEditStatus.picking ||
        editor.status == AvatarEditStatus.cropping ||
        editor.status == AvatarEditStatus.uploading;
    return Scaffold(
      appBar: AppBar(title: const Text('头像与外观')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Stack(
              children: [
                AppAvatar(
                  name: owner?.name ?? '我',
                  imageUrl: owner?.imageUrl,
                  size: 112,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: IconButton.filled(
                    tooltip: '选择并裁剪头像',
                    onPressed:
                        busy || owner == null
                            ? null
                            : () => ref
                                .read(avatarEditControllerProvider)
                                .chooseCropAndUpload(preferences.shape),
                    icon: const Icon(Icons.edit),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Center(child: Text(owner?.name ?? '当前聊天身份尚未加载')),
          const SizedBox(height: 24),
          const Text('头像形状'),
          RadioGroup<AvatarShape>(
            groupValue: preferences.shape,
            onChanged: (value) {
              if (value != null) {
                ref.read(avatarPreferencesProvider).setShape(value);
              }
            },
            child: const Column(
              children: [
                RadioListTile(value: AvatarShape.circle, title: Text('圆形')),
                RadioListTile(value: AvatarShape.square, title: Text('方形（圆角）')),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (busy) ...[
            LinearProgressIndicator(value: editor.progress),
            const SizedBox(height: 8),
            Text(
              '正在${editor.status == AvatarEditStatus.uploading ? '上传' : '处理'}头像…',
            ),
          ],
          if (editor.status == AvatarEditStatus.success)
            const ListTile(
              leading: Icon(Icons.check_circle, color: Colors.green),
              title: Text('头像已更新'),
              subtitle: Text('当前聊天身份和所有统一头像会自动刷新。'),
            ),
          if (editor.status == AvatarEditStatus.failed)
            ListTile(
              leading: const Icon(Icons.error_outline, color: Colors.red),
              title: const Text('头像更新失败'),
              subtitle: Text('${editor.error}'),
            ),
          const SizedBox(height: 20),
          const Text('图片会固定裁剪为 1:1、最大 1024×1024。圆形仅影响预览与显示，不会生成透明圆形文件。'),
        ],
      ),
    );
  }
}
