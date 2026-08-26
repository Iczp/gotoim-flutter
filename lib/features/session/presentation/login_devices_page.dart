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
                  padding: const EdgeInsets.all(12),
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
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.devices_outlined),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  [
                    device.deviceType,
                    device.brand,
                    device.model,
                  ].where((value) => value.isNotEmpty).join(' · '),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (isCurrent) const Chip(label: Text('当前设备')),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText('deviceId: ${device.deviceId}'),
          if (device.groups.isNotEmpty) Text('组：${device.groups.join('、')}'),
          if (device.updatedAt != null) Text('最后更新：${device.updatedAt}'),
        ],
      ),
    ),
  );
}
