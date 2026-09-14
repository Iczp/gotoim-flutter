import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/session_list_controller.dart';
import '../data/models/logged_in_device.dart';

class LoginDevicesPage extends ConsumerStatefulWidget {
  const LoginDevicesPage({super.key});

  @override
  ConsumerState<LoginDevicesPage> createState() => _LoginDevicesPageState();
}

class _LoginDevicesPageState extends ConsumerState<LoginDevicesPage> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() async {
      final controller = ref.read(sessionListControllerProvider);
      await Future.wait<void>([
        controller.loadDevices(),
        controller.loadOnlineDevices(),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(sessionListControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('设备管理')),
      body: RefreshIndicator(
        onRefresh:
            () => Future.wait<void>([
              controller.loadDevices(),
              controller.loadOnlineDevices(),
            ]),
        child:
            controller.devices.isEmpty && controller.isLoadingDevices
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  children: <Widget>[
                    _SectionTitle('我的设备（${controller.devices.length}）'),
                    ...controller.devices.map(
                      (device) => _DeviceCard(
                        device: device,
                        isCurrent:
                            device.deviceId == controller.currentDeviceId,
                        onForceLogout: null,
                      ),
                    ),
                    _SectionTitle('当前在线（${controller.onlineDevices.length}）'),
                    ...controller.onlineDevices.map(
                      (device) => _DeviceCard(
                        device: device,
                        isCurrent:
                            device.deviceId == controller.currentDeviceId,
                        onForceLogout:
                            () => _confirmForceLogout(
                              context,
                              controller,
                              device,
                            ),
                      ),
                    ),
                  ],
                ),
      ),
    );
  }

  Future<void> _confirmForceLogout(
    BuildContext context,
    SessionListController controller,
    LoggedInDevice device,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('强制下线'),
            content: const Text('确定要断开此设备的在线连接吗？该设备将收到强制退出通知。'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('强制下线'),
              ),
            ],
          ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await controller.forceLogoutDevice(device);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已请求断开该设备连接')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('强制下线失败：$error')));
      }
    }
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.isCurrent,
    required this.onForceLogout,
  });
  final LoggedInDevice device;
  final bool isCurrent;
  final VoidCallback? onForceLogout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final deviceTitle = [
      device.deviceType,
      device.brand,
      device.model,
    ].where((value) => value.isNotEmpty).join(' · ');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color:
                        isCurrent
                            ? colorScheme.primaryContainer
                            : colorScheme.surfaceContainerHighest.withValues(
                              alpha: 0.5,
                            ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.devices_rounded,
                    size: 22,
                    color:
                        isCurrent
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        deviceTitle.isEmpty ? '未知设备' : deviceTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (device.updatedAt != null)
                        Text(
                          '活跃时间：${device.updatedAt}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (isCurrent)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '当前设备',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            if (!isCurrent &&
                device.connectionId.isNotEmpty &&
                onForceLogout != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onForceLogout,
                  icon: Icon(Icons.logout_rounded, color: colorScheme.error),
                  label: Text(
                    '强制下线',
                    style: TextStyle(color: colorScheme.error),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    'Device ID: ${device.deviceId}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                  if (device.groups.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '设备组：${device.groups.join('、')}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}
