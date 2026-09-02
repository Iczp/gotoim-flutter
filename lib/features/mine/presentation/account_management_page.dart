import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/glass_container.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../session/application/session_list_controller.dart';

/// 账号管理页面。
class AccountManagementPage extends ConsumerWidget {
  const AccountManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final sessionController = ref.watch(sessionListControllerProvider);
    final currentOwner = sessionController.currentOwner;

    return Scaffold(
      appBar: AppBar(title: const Text('账号管理')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          // 当前账号信息卡
          GlassCard(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                AppAvatar(
                  name: currentOwner?.name ?? 'User',
                  imageUrl: currentOwner?.imageUrl,
                  radius: 28,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentOwner?.name ?? '—',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (currentOwner?.typeDescription.isNotEmpty == true) ...[
                        const SizedBox(height: 4),
                        Text(
                          currentOwner!.typeDescription,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          GlassCard(
            margin: const EdgeInsets.only(bottom: 12),
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.lock_outline_rounded),
                  title: const Text('修改密码'),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  enabled: false,
                  onTap: () {},
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.phone_android_rounded),
                  title: const Text('绑定手机'),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  enabled: false,
                  onTap: () {},
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.email_outlined),
                  title: const Text('绑定邮箱'),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  enabled: false,
                  onTap: () {},
                ),
              ],
            ),
          ),

          GlassCard(
            margin: const EdgeInsets.only(bottom: 12),
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: Icon(
                Icons.delete_forever_outlined,
                color: colorScheme.error,
              ),
              title: Text(
                '注销账号',
                style: TextStyle(color: colorScheme.error),
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              enabled: false,
              onTap: () {},
            ),
          ),
        ],
      ),
    );
  }
}
