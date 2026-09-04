import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/application_providers.dart';
import '../../../core/network/abp/abp_current_user.dart';
import '../../../core/services/scan/unified_scan_dispatcher.dart';
import '../../../core/theme/theme_mode_controller.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../auth/application/auth_controller.dart';
import '../application/session_list_controller.dart';

/// The home shell owns this drawer so every top-level tab can open it.
class ChatOwnerDrawer extends ConsumerWidget {
  const ChatOwnerDrawer({required this.controller, super.key});

  final SessionListController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final themeMode = ref.watch(themeModeProvider);

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Text(
                    '切换聊天身份',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '快速切换深浅主题',
                    icon: Icon(
                      themeMode == ThemeMode.dark
                          ? Icons.dark_mode_rounded
                          : themeMode == ThemeMode.light
                          ? Icons.light_mode_rounded
                          : Icons.brightness_auto_rounded,
                      size: 20,
                    ),
                    onPressed:
                        () =>
                            ref
                                .read(themeModeControllerProvider.notifier)
                                .toggleTheme(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final owner in controller.owners)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: ListTile(
                        contentPadding: EdgeInsets.symmetric(horizontal: 8),
                        minVerticalPadding: 0,
                        leading: AppAvatar(
                          name: owner.name,
                          imageUrl: owner.imageUrl,
                          radius: 20,
                        ),
                        title: Text(
                          owner.name,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        subtitle:
                            owner.typeDescription.isEmpty
                                ? null
                                : Text(
                                  owner.typeDescription,
                                  style: const TextStyle(
                                    color: Color.fromARGB(77, 53, 53, 53),
                                  ),
                                ),
                        trailing:
                            controller.currentOwner?.id == owner.id
                                ? Icon(
                                  Icons.check_circle_rounded,
                                  color: colorScheme.primary,
                                )
                                : owner.unreadCount > 0
                                ? Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.error,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    owner.unreadCount > 99
                                        ? '99+'
                                        : '${owner.unreadCount}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                )
                                : owner.immersedCount > 0
                                ? const Badge()
                                : const Icon(
                                  Icons.chevron_right,
                                  size: 18,
                                  color: Color.fromRGBO(0, 0, 0, 0.3),
                                ),
                        selected: controller.currentOwner?.id == owner.id,
                        selectedTileColor: colorScheme.primaryContainer
                            .withValues(alpha: 0.3),
                        onTap: () async {
                          Navigator.pop(context);
                          await controller.selectOwner(owner);
                        },
                      ),
                    ),
                  const Divider(height: 16),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    minVerticalPadding: 0,
                    leading: const Icon(Icons.qr_code_scanner_rounded),
                    title: const Text('扫一扫'),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () {
                      Navigator.pop(context);
                      ref
                          .read(unifiedScanDispatcherProvider)
                          .openAndDispatch(context, ref);
                    },
                  ),
                  const ListTile(
                    contentPadding: EdgeInsets.symmetric(horizontal: 8),
                    minVerticalPadding: 0,
                    leading: Icon(Icons.person_add_alt_1_outlined),
                    title: Text('添加朋友'),
                    trailing: Icon(Icons.chevron_right, size: 18),
                    enabled: false,
                  ),
                  const ListTile(
                    contentPadding: EdgeInsets.symmetric(horizontal: 8),
                    minVerticalPadding: 0,
                    leading: Icon(Icons.group_add_outlined),
                    title: Text('新建群聊'),
                    trailing: Icon(Icons.chevron_right, size: 18),
                    enabled: false,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            CurrentUserAccountTile(controller: controller),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Goto IM Cross-Platform',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Formats current user account text, combining [name] and [userName].
/// Example: `IM  admin` or `admin`.
String formatCurrentUserAccountText(
  AbpCurrentUser? currentUser, {
  String? fallback,
}) {
  final name = currentUser?.name?.trim() ?? '';
  final userName = currentUser?.userName?.trim() ?? '';
  final parts = <String>[
    if (name.isNotEmpty) name,
    if (userName.isNotEmpty && userName != name) userName,
  ];
  if (parts.isNotEmpty) {
    return parts.join('  ');
  }
  if (fallback != null && fallback.trim().isNotEmpty) {
    return fallback.trim();
  }
  return '';
}

/// Dedicated tile at the bottom of [ChatOwnerDrawer] that encapsulates
/// watching [currentUserProvider] and displays the current account info.
class CurrentUserAccountTile extends ConsumerWidget {
  const CurrentUserAccountTile({required this.controller, super.key});

  final SessionListController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final authState = ref.watch(authControllerProvider);
    final accountText = formatCurrentUserAccountText(
      currentUser,
      fallback: authState.accountName,
    );

    final displayTitle = accountText.isNotEmpty ? '当前账号：$accountText' : '当前账号';

    final currentOwner = controller.currentOwner;
    final displaySubtitle =
        currentOwner != null
            ? '当前身份：${currentOwner.name}'
            : (currentOwner?.typeDescription.isNotEmpty == true
                ? currentOwner!.typeDescription
                : '当前登录身份');

    final avatarName =
        currentUser?.name?.trim().isNotEmpty == true
            ? currentUser!.name!.trim()
            : (currentUser?.userName?.trim().isNotEmpty == true
                ? currentUser!.userName!.trim()
                : (currentOwner?.name ?? '我'));

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      minVerticalPadding: 0,
      leading:
          currentOwner != null
              ? AppAvatar(
                name: currentOwner.name,
                imageUrl: currentOwner.imageUrl,
                radius: 16,
              )
              : AppAvatar(name: avatarName, imageUrl: null, radius: 16),
      title: Text(
        displayTitle,
        style: const TextStyle(fontWeight: FontWeight.w500),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        displaySubtitle,
        style: const TextStyle(
          color: Color.fromARGB(153, 53, 53, 53),
          fontSize: 12,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () {
        Navigator.pop(context);
        context.push('/account/profile');
      },
    );
  }
}
