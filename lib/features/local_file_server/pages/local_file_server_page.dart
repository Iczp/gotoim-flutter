import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:app_settings/app_settings.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../app/application_providers.dart';
import '../../../core/capabilities/client_capability_models.dart';
import '../../../core/services/clipboard_service.dart';
import '../local_file_server.dart';
import '../local_file_server_controller.dart';

class LocalFileServerPage extends ConsumerStatefulWidget {
  const LocalFileServerPage({super.key});

  @override
  ConsumerState<LocalFileServerPage> createState() =>
      _LocalFileServerPageState();
}

class _LocalFileServerPageState extends ConsumerState<LocalFileServerPage> {
  late final LocalFileServerService _service;
  String _selectedPath = '/';
  Future<String?>? _wifiName;

  @override
  void initState() {
    super.initState();
    _service = ref.read(localFileServerProvider)
      ..addListener(_onServiceChanged);
    _loadWifiName();
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadWifiName() async {
    await Permission.locationWhenInUse.request();
    final name = await NetworkInfo().getWifiName();
    if (mounted) {
      setState(() => _wifiName = Future.value(name));
    }
  }

  String _networkLabel(ClientNetworkStatus status) {
    if (!status.isConnected) return '未连接网络';
    if (status.types.contains(ClientNetworkType.wifi)) return '已连接 Wi‑Fi';
    return '当前网络：${status.types.map((item) => item.name).join('、')}';
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    final state = service.state;
    final running = state.status == LocalFileServerStatus.running;
    final capabilities = ref.read(clientCapabilityServiceProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('局域网文件管理')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          StreamBuilder<ClientNetworkStatus>(
            stream: capabilities.networkStatusChanges,
            initialData: ClientNetworkStatus(
              types: [ClientNetworkType.none],
              observedAt: DateTime.now(),
            ),
            builder: (context, snapshot) {
              final status = snapshot.data!;
              return Card(
                child: ListTile(
                  leading: Icon(
                    status.types.contains(ClientNetworkType.wifi)
                        ? Icons.wifi
                        : Icons.wifi_off_outlined,
                  ),
                  title: Text(
                    status.types.contains(ClientNetworkType.wifi)
                        ? '当前 Wi‑Fi 网络'
                        : _networkLabel(status),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: FutureBuilder<String?>(
                    future: _wifiName,
                    builder:
                        (context, ssid) => Text(
                          status.types.contains(ClientNetworkType.wifi)
                              ? 'SSID：${ssid.data?.replaceAll('"', '') ?? '未授权读取（请允许位置权限）'}\n访问设备必须连接到同一个 Wi‑Fi'
                              : '请连接 Wi‑Fi 后再开启文件共享',
                        ),
                  ),
                  trailing: TextButton(
                    onPressed:
                        () => AppSettings.openAppSettings(
                          type: AppSettingsType.wifi,
                        ),
                    child: const Text('打开 Wi‑Fi 设置'),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        running
                            ? Icons.check_circle
                            : Icons.pause_circle_outline,
                        color:
                            running
                                ? Colors.green
                                : Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _statusText(state.status),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  if (state.error != null) ...[
                    const SizedBox(height: 12),
                    SelectableText(
                      state.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  if (running) ...[
                    const SizedBox(height: 16),
                    _CopyField(label: '访问地址', value: state.address!),
                    const SizedBox(height: 12),
                    _CopyField(label: '验证码', value: state.verificationCode!),
                    const SizedBox(height: 16),
                    Center(
                      child: QrImageView(data: state.qrLoginUrl!, size: 180),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '二维码仅可使用一次，5 分钟内有效；输入验证码也可进入。',
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed:
                        state.status == LocalFileServerStatus.starting
                            ? null
                            : (running ? service.stop : service.start),
                    icon: Icon(
                      running
                          ? Icons.stop_circle_outlined
                          : Icons.play_arrow_outlined,
                    ),
                    label: Text(running ? '关闭文件共享' : '开启文件共享'),
                  ),
                  if (Theme.of(context).platform == TargetPlatform.iOS) ...[
                    const SizedBox(height: 12),
                    const Text('iOS 在后台或锁屏时可能暂停服务；传输期间请保持 App 在前台。'),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: () => context.push('/local-file-server/files'),
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('打开 App 资源管理器'),
          ),
          const SizedBox(height: 16),
          Text(
            '已连接终端 ${state.terminals.length}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (state.terminals.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('暂无已连接终端。'),
              ),
            ),
          ...state.terminals.map(
            (terminal) => Card(
              child: ListTile(
                leading: const Icon(Icons.devices_outlined),
                title: Text(terminal.name),
                subtitle: Text(
                  '${terminal.platform} · ${terminal.ip}\n${_terminalState(terminal)}',
                ),
                isThreeLine: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => service.disconnectTerminal(terminal.id),
                      child: const Text('断开'),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap:
                    () => context.push(
                      '/local-file-server/terminal/${Uri.encodeComponent(terminal.id)}',
                    ),
              ),
            ),
          ),
          if (service.recentTerminals.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              '最近终端 ${service.recentTerminals.length}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ...service.recentTerminals.map(
              (terminal) => Card(
                child: ListTile(
                  leading: const Icon(Icons.devices_outlined),
                  title: Text(terminal.name),
                  subtitle: Text(
                    '${terminal.platform} · ${terminal.ip}\n已断开 · 最后活动 ${terminal.lastActiveAt.toLocal()}',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap:
                      () => context.push(
                        '/local-file-server/terminal/${Uri.encodeComponent(terminal.id)}',
                      ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _statusText(LocalFileServerStatus status) {
    switch (status) {
      case LocalFileServerStatus.running:
        return '服务已开启';
      case LocalFileServerStatus.starting:
        return '服务启动中';
      case LocalFileServerStatus.failed:
        return '服务启动失败';
      case LocalFileServerStatus.unsupported:
        return '当前平台暂不支持';
      case LocalFileServerStatus.stopped:
        return '服务未开启';
    }
  }

  String _terminalState(ConnectedTerminal terminal) {
    final current = terminal.transferLabel;
    if (current != null &&
        terminal.totalBytes != null &&
        terminal.receivedBytes != null) {
      return '$current ${(terminal.receivedBytes! * 100 / terminal.totalBytes!).toStringAsFixed(0)}%';
    }
    return terminal.status == TerminalStatus.idle
        ? '在线 · 空闲'
        : terminal.status.name;
  }

  Widget _buildFileManager(BuildContext context) {
    const folders = ['/', '/图片', '/视频', '/文档', '/下载', '/聊天文件'];
    return Card(
      child: SizedBox(
        height: 300,
        child: Row(
          children: [
            SizedBox(
              width: 112,
              child: ListView(
                children:
                    folders
                        .map(
                          (path) => ListTile(
                            dense: true,
                            selected: path == _selectedPath,
                            title: Text(
                              path == '/' ? '全部文件' : path.substring(1),
                            ),
                            onTap: () => setState(() => _selectedPath = path),
                          ),
                        )
                        .toList(),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: FutureBuilder<List<SharedFile>>(
                future: _service.listSharedFiles(_selectedPath),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final files = snapshot.data!;
                  if (files.isEmpty) {
                    return const Center(child: Text('当前文件夹为空'));
                  }
                  return ListView(
                    children:
                        files
                            .map(
                              (item) => ListTile(
                                dense: true,
                                leading: Icon(
                                  item.isDirectory
                                      ? Icons.folder
                                      : Icons.insert_drive_file_outlined,
                                ),
                                title: Text(item.name),
                                subtitle: Text(
                                  item.isDirectory ? '文件夹' : '${item.size} B',
                                ),
                                onTap:
                                    item.isDirectory
                                        ? () => setState(
                                          () => _selectedPath = item.path,
                                        )
                                        : null,
                              ),
                            )
                            .toList(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CopyField extends ConsumerWidget {
  const _CopyField({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context, WidgetRef ref) => TextField(
    controller: TextEditingController(text: value),
    readOnly: true,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      suffixIcon: IconButton(
        tooltip: '复制',
        icon: const Icon(Icons.copy_outlined),
        onPressed: () async {
          await ref.read(clipboardServiceProvider).copy(value);
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('已复制。')));
          }
        },
      ),
    ),
  );
}
