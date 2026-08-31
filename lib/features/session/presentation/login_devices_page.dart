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
    Future<void>.microtask(
      () => ref.read(sessionListControllerProvider).loadDevices(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(sessionListControllerProvider);
    return Scaffold(
      appBar: AppBar(title: Text('登录设备(${controller.devices.length})')),
      body: RefreshIndicator(
        onRefresh: controller.loadDevices,
        child:
            controller.devices.isEmpty && controller.isLoadingDevices
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  itemCount: controller.devices.length,
                  itemBuilder:
                      (context, index) => _DeviceCard(
                        device: controller.devices[index],
                        isCurrent:
                            controller.devices[index].deviceId ==
                            controller.currentDeviceId,
                      ),
                ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device, required this.isCurrent});
  final LoggedInDevice device;
  final bool isCurrent;

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
