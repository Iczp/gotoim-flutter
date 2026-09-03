import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/device/client_device_context.dart';
import '../../../../core/widgets/app_modal.dart';
import '../../../../core/widgets/app_toast.dart';
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
    await ref.read(authControllerProvider).fetchUserInfo(force: true);
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
    final deviceContext = ref.watch(clientDeviceContextProvider);

    final userInfo = authState.userInfo;
    final account = userInfo?['preferred_username']?.toString() ??
        userInfo?['unique_name']?.toString() ??
        authState.accountName ??
        '未设置';

    final name = userInfo?['name']?.toString() ??
        '${userInfo?['family_name'] ?? ''} ${userInfo?['given_name'] ?? ''}'.trim();
    final displayName = name.isNotEmpty ? name : account;

    final email = userInfo?['email']?.toString() ?? '未设置';
    final phoneNumber = userInfo?['phone_number']?.toString() ?? '未设置';
    final roles = _extractRoles(userInfo);

    final lastRefreshed = authState.lastTokenRefreshedAt;
    final lastRefreshedText = lastRefreshed != null
        ? '${lastRefreshed.month.toString().padLeft(2, '0')}-${lastRefreshed.day.toString().padLeft(2, '0')} '
            '${lastRefreshed.hour.toString().padLeft(2, '0')}:${lastRefreshed.minute.toString().padLeft(2, '0')}:${lastRefreshed.second.toString().padLeft(2, '0')}'
        : '有效中';

    return Scaffold(
      appBar: AppBar(
        title: const Text('账号'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // ── 1. 基本信息 ──────────────────────────────────────────────
            _ProfileGroup(
              children: [
                _ProfileCell(
                  label: '账号',
                  value: account,
                  canCopy: true,
                ),
                _ProfileCell(
                  label: '名称',
                  value: displayName,
                  canCopy: true,
                ),
                _ProfileCell(
                  label: '邮箱',
                  value: email,
                  showArrow: true,
                  canCopy: true,
                ),
                _ProfileCell(
                  label: '手机',
                  value: phoneNumber,
                  showArrow: true,
                  canCopy: true,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── 2. 角色组 ────────────────────────────────────────────────
            _ProfileGroup(
              label: '角色',
              children: roles
                  .map(
                    (role) => _ProfileCell(
                      label: role,
                      showArrow: true,
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),

            // ── 3. 缓存管理 ──────────────────────────────────────────────
            _ProfileGroup(
              label: '缓存',
              children: [
                _ProfileCell(
                  label: '本地缓存',
                  value: '约 12.8 MB',
                  showArrow: true,
                  onTap: _clearCache,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── 4. 安全 ──────────────────────────────────────────────────
            _ProfileGroup(
              label: '安全',
              children: [
                const _ProfileCell(
                  label: '登录日志',
                  showArrow: true,
                ),
                _ProfileCell(
                  label: '授权',
                  showArrow: true,
                  valueWidget: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
            const SizedBox(height: 12),

            // ── 5. 设备信息 ──────────────────────────────────────────────
            _ProfileGroup(
              label: '设备',
              children: [
                _ProfileCell(
                  label: 'ID(${deviceContext.deviceType})',
                  value: deviceContext.deviceId.isNotEmpty
                      ? (deviceContext.deviceId.length > 16
                          ? '${deviceContext.deviceId.substring(0, 16)}...'
                          : deviceContext.deviceId)
                      : '本地设备',
                  canCopy: true,
                  copyValue: deviceContext.deviceId,
                ),
                _ProfileCell(
                  label: 'Brand',
                  value: deviceContext.brand.isNotEmpty
                      ? deviceContext.brand
                      : 'Unknown',
                ),
                _ProfileCell(
                  label: 'Model',
                  value: deviceContext.model.isNotEmpty
                      ? deviceContext.model
                      : 'Unknown',
                ),
                _ProfileCell(
                  label: 'OS',
                  value: deviceContext.platform.isNotEmpty
                      ? deviceContext.platform
                      : 'Unknown',
                ),
                _ProfileCell(
                  label: '登录设备',
                  showArrow: true,
                  onTap: () => context.push('/devices'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── 6. 令牌与系统 ────────────────────────────────────────────
            _ProfileGroup(
              children: [
                _ProfileCell(
                  icon: const Icon(Icons.token_outlined, size: 20),
                  label: '刷新Token',
                  value: _refreshingToken ? '刷新中...' : lastRefreshedText,
                  showArrow: true,
                  onTap: _handleRefreshToken,
                ),
                _ProfileCell(
                  icon: const Icon(Icons.touch_app_outlined, size: 20),
                  label: '版本',
                  valueWidget: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
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
            const SizedBox(height: 16),

            // ── 7. 退出登录 ──────────────────────────────────────────────
            _ProfileGroup(
              children: [
                ListTile(
                  title: const Center(
                    child: Text(
                      '退出登录',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  onTap: _confirmLogout,
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _ProfileGroup extends StatelessWidget {
  const _ProfileGroup({
    required this.children,
    this.label,
  });

  final String? label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 6),
            child: Text(
              label!,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        Material(
          clipBehavior: Clip.antiAlias,
          color: theme.colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: theme.dividerColor.withValues(alpha: 0.2),
            ),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: children.length,
            separatorBuilder: (_, index) => Divider(
              height: 1,
              indent: 16,
              color: theme.dividerColor.withValues(alpha: 0.15),
            ),
            itemBuilder: (_, index) => children[index],
          ),
        ),
      ],
    );
  }
}

class _ProfileCell extends StatelessWidget {
  const _ProfileCell({
    required this.label,
    this.value,
    this.valueWidget,
    this.icon,
    this.showArrow = false,
    this.canCopy = false,
    this.copyValue,
    this.onTap,
  });

  final String label;
  final String? value;
  final Widget? valueWidget;
  final Widget? icon;
  final bool showArrow;
  final bool canCopy;
  final String? copyValue;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap ??
          (canCopy && (value != null || copyValue != null)
              ? () {
                  final text = copyValue ?? value!;
                  Clipboard.setData(ClipboardData(text: text));
                  showToast('已复制 $label', type: ToastType.info);
                }
              : null),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            if (icon != null) ...[
              icon!,
              const SizedBox(width: 10),
            ],
            Text(
              label,
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: valueWidget ??
                    Text(
                      value ?? '',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
              ),
            ),
            if (showArrow) ...[
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
