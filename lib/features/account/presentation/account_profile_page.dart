import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/device/client_device_context.dart';
import '../../../../core/widgets/app_modal.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/cell_group.dart';
import '../../auth/application/auth_controller.dart';

/// 账号设置与个人信息页面
///
/// 参考 UniApp 路径: `src/pages/account/profile.vue`
class AccountProfilePage extends ConsumerStatefulWidget {
  const AccountProfilePage({super.key});

  @override
  ConsumerState<AccountProfilePage> createState() => _AccountProfilePageState();
}

class _AccountProfilePageState extends ConsumerState<AccountProfilePage> {
  bool _refreshingToken = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authControllerProvider).fetchUserInfo();
    });
  }

  Future<void> _onRefresh() async {
    await Future.wait([
      ref.read(authControllerProvider).fetchUserInfo(force: true),
      ref.read(authControllerProvider).fetchApplicationConfiguration(force: true),
    ]);
  }

  Future<void> _handleRefreshToken() async {
    if (_refreshingToken) return;
    setState(() => _refreshingToken = true);
    try {
      await ref.read(authControllerProvider).tryRefreshToken();
      if (mounted) {
        showToast('Token 刷新成功', type: ToastType.success);
      }
    } catch (e) {
      if (mounted) {
        showToast('Token 刷新失败：$e', type: ToastType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _refreshingToken = false);
      }
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await showConfirmModal(
      context: context,
      title: '清理本地缓存',
      message: '将清除本机的临时文件、图片与音视频缓存，聊天消息与登录状态不会受到影响。确定继续吗？',
      confirmText: '清理',
    );
    if (confirmed && mounted) {
      showToast('缓存已清理完成', type: ToastType.success);
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showConfirmModal(
      context: context,
      title: '退出登录',
      message: '确定要退出当前账号登录吗？\n退出后 Token 将立即在服务器失效。',
      confirmText: '退出',
      isDestructive: true,
    );
    if (confirmed && mounted) {
      await ref.read(authControllerProvider).logout();
      if (mounted) {
        context.go('/login');
      }
    }
  }

  List<String> _extractRoles(Map<String, dynamic>? userInfo) {
    if (userInfo == null) return const <String>[];
    final roleValue = userInfo['role'] ?? userInfo['roles'];
    if (roleValue is List) {
      return roleValue.map((e) => '$e').where((e) => e.isNotEmpty).toList();
    }
    if (roleValue is String && roleValue.isNotEmpty) {
      return <String>[roleValue];
    }
    return const <String>['普通用户'];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(authControllerProvider);
    final currentUser = authState.currentUser;
    final deviceContext = ref.watch(clientDeviceContextProvider);

    final userInfo = authState.userInfo;
    final account =
        currentUser?.userName ??
        userInfo?['preferred_username']?.toString() ??
        userInfo?['unique_name']?.toString() ??
        authState.accountName ??
        '未设置';

    final name =
        currentUser?.displayName ??
        userInfo?['name']?.toString() ??
        '${userInfo?['family_name'] ?? ''} ${userInfo?['given_name'] ?? ''}'
            .trim();
    final displayName = name.isNotEmpty ? name : account;

    final email =
        currentUser?.email ?? userInfo?['email']?.toString() ?? '未设置';
    final phoneNumber =
        currentUser?.phoneNumber ??
        userInfo?['phone_number']?.toString() ??
        '未设置';
    final roles =
        currentUser != null && currentUser.roles.isNotEmpty
            ? currentUser.roles
            : _extractRoles(userInfo);

    final lastRefreshed = authState.lastTokenRefreshedAt;
    final lastRefreshedText =
        lastRefreshed != null
            ? '${lastRefreshed.month.toString().padLeft(2, '0')}-${lastRefreshed.day.toString().padLeft(2, '0')} '
                '${lastRefreshed.hour.toString().padLeft(2, '0')}:${lastRefreshed.minute.toString().padLeft(2, '0')}:${lastRefreshed.second.toString().padLeft(2, '0')}'
            : '有效中';

    return Scaffold(
      appBar: AppBar(title: const Text('账号'), centerTitle: true),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // ── 1. 基本信息 ──────────────────────────────────────────────
            CellGroup(
              children: [
                if (currentUser?.id != null && currentUser!.id!.isNotEmpty)
                  Cell(title: '用户ID', value: currentUser.id!, canCopy: true),
                Cell(title: '账号', value: account, canCopy: true),
                Cell(title: '名称', value: displayName, canCopy: true),
                Cell(
                  title: '邮箱',
                  value: email,
                  showArrow: true,
                  canCopy: true,
                ),
                Cell(
                  title: '手机',
                  value: phoneNumber,
                  showArrow: true,
                  canCopy: true,
                ),
              ],
            ),

            // ── 2. 角色组 ────────────────────────────────────────────────
            CellGroup(
              title: '角色',
              children: roles
                  .map((role) => Cell(title: role, showArrow: true))
                  .toList(),
            ),

            // ── 3. 缓存管理 ──────────────────────────────────────────────
            CellGroup(
              title: '缓存',
              children: [
                Cell(
                  title: '本地缓存',
                  value: '约 12.8 MB',
                  showArrow: true,
                  onTap: _clearCache,
                ),
              ],
            ),

            // ── 4. 安全 ──────────────────────────────────────────────────
            CellGroup(
              title: '安全',
              children: [
                const Cell(title: '登录日志', showArrow: true),
                Cell(
                  title: '授权',
                  showArrow: true,
                  valueWidget: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '0',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // ── 5. 设备信息 ──────────────────────────────────────────────
            CellGroup(
              title: '设备',
              children: [
                Cell(
                  title: 'ID(${deviceContext.deviceType})',
                  value: deviceContext.deviceId.isNotEmpty
                      ? (deviceContext.deviceId.length > 16
                          ? '${deviceContext.deviceId.substring(0, 16)}...'
                          : deviceContext.deviceId)
                      : '本地设备',
                  canCopy: true,
                  copyValue: deviceContext.deviceId,
                ),
                Cell(
                  title: 'Brand',
                  value: deviceContext.brand.isNotEmpty
                      ? deviceContext.brand
                      : 'Unknown',
                ),
                Cell(
                  title: 'Model',
                  value: deviceContext.model.isNotEmpty
                      ? deviceContext.model
                      : 'Unknown',
                ),
                Cell(
                  title: 'OS',
                  value: deviceContext.platform.isNotEmpty
                      ? deviceContext.platform
                      : 'Unknown',
                ),
                Cell(
                  title: '登录设备',
                  showArrow: true,
                  onTap: () => context.push('/devices'),
                ),
              ],
            ),

            // ── 6. 令牌与系统 ────────────────────────────────────────────
            CellGroup(
              children: [
                Cell(
                  icon: const Icon(Icons.token_outlined, size: 20),
                  title: '刷新Token',
                  value: _refreshingToken ? '刷新中...' : lastRefreshedText,
                  showArrow: true,
                  onTap: _handleRefreshToken,
                ),
                Cell(
                  icon: const Icon(Icons.touch_app_outlined, size: 20),
                  title: '版本',
                  valueWidget: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'GotoIM v${deviceContext.appVersion}',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // ── 7. 退出登录 ──────────────────────────────────────────────
            CellGroup(
              margin: const EdgeInsets.only(bottom: 32),
              children: [
                Cell(
                  title: '退出登录',
                  titleColor: Colors.red,
                  isCentered: true,
                  onTap: _confirmLogout,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
