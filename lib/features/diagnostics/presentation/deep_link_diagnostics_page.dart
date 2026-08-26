import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/deep_link/deep_link_handler.dart';
import '../../../core/deep_link/deep_link_parser.dart';
import '../../../core/deep_link/deep_link_service.dart';

class DeepLinkDiagnosticsPage extends ConsumerStatefulWidget {
  const DeepLinkDiagnosticsPage({super.key});

  @override
  ConsumerState<DeepLinkDiagnosticsPage> createState() =>
      _DeepLinkDiagnosticsPageState();
}

class _DeepLinkDiagnosticsPageState
    extends ConsumerState<DeepLinkDiagnosticsPage> {
  final _uriController = TextEditingController(
    text: 'gotoim-dev://chat/123/message/456',
  );

  DeepLinkParseResult? _parseResult;
  DeepLinkExecutionResult? _executionResult;
  bool _working = false;

  final List<_PresetCase> _presets = const [
    _PresetCase(
      label: '聊天',
      uri: 'gotoim-dev://chat/123',
      description: '打开指定会话 (sessionId=123)',
    ),
    _PresetCase(
      label: '消息定位',
      uri: 'gotoim-dev://chat/123/message/456',
      description: '定位指定会话的消息 (sessionId=123, messageId=456)',
    ),
    _PresetCase(
      label: '用户资料',
      uri: 'gotoim-dev://user/10086',
      description: '查看用户 (userId=10086)',
    ),
    _PresetCase(
      label: '群资料',
      uri: 'gotoim-dev://group/888',
      description: '查看群组 (groupId=888)',
    ),
    _PresetCase(
      label: '群邀请',
      uri: 'gotoim-dev://invite/group/abcdef123',
      description: '群邀请确认卡片 (token=abcdef123)',
    ),
    _PresetCase(
      label: '扫码登录',
      uri: 'gotoim-dev://scan-login/abc123',
      description: '扫码登录授权确认 (qrCode=abc123)',
    ),
    _PresetCase(
      label: '工作台应用',
      uri: 'gotoim-dev://workbench/mail',
      description: '工作台 MiniApp (appId=mail)',
    ),
    _PresetCase(
      label: 'OAuth 回调',
      uri: 'gotoim-dev://oauth/callback?code=auth_code_999&state=state_xyz',
      description: '第三方 OAuth 授权回调',
    ),
    _PresetCase(
      label: 'HTTPS 模拟',
      uri: 'https://gotoim.com/chat/123/message/456',
      description: '未来生产 HTTPS Universal Link 纯解析验证',
    ),
    _PresetCase(
      label: '生产 Scheme',
      uri: 'gotoim://chat/123',
      description: '正式环境自定义 Scheme',
    ),
    _PresetCase(
      label: '错误: 缺参数',
      uri: 'gotoim-dev://chat',
      description: '缺少 sessionId (应返回 invalid)',
    ),
    _PresetCase(
      label: '错误: 非法数字',
      uri: 'gotoim-dev://chat/123/message/abc',
      description: '非数字 messageId (应返回 invalid)',
    ),
    _PresetCase(
      label: '拒绝: 未知域名',
      uri: 'https://evil.com/chat/123',
      description: '非 GotoIM 域名 (应返回 unsupported)',
    ),
    _PresetCase(
      label: '未知 Action',
      uri: 'gotoim-dev://unknown_action/123',
      description: '未知业务动作 (应返回 unsupported)',
    ),
  ];

  @override
  void dispose() {
    _uriController.dispose();
    super.dispose();
  }

  void _applyPreset(_PresetCase preset) {
    setState(() {
      _uriController.text = preset.uri;
      _parseResult = null;
      _executionResult = null;
    });
  }

  void _parseOnly() {
    final text = _uriController.text.trim();
    if (text.isEmpty) return;

    final service = ref.read(deepLinkServiceProvider);
    try {
      final uri = Uri.parse(text);
      final result = service.parser.parse(uri);
      setState(() {
        _parseResult = result;
        _executionResult = null;
      });
    } catch (e) {
      setState(() {
        _parseResult = DeepLinkParseResult.invalid(
          rawUri: Uri.parse(text),
          reason: 'Uri.parse error: $e',
        );
        _executionResult = null;
      });
    }
  }

  Future<void> _execute() async {
    final text = _uriController.text.trim();
    if (text.isEmpty) return;

    setState(() => _working = true);
    final service = ref.read(deepLinkServiceProvider);
    try {
      final uri = Uri.parse(text);
      final parseRes = service.parser.parse(uri);
      final execRes = await service.handleUri(uri, source: 'manual_diagnostic');
      if (mounted) {
        setState(() {
          _parseResult = parseRes;
          _executionResult = execRes;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _executionResult = DeepLinkExecutionResult(
            status: DeepLinkExecutionStatus.failed,
            target: null,
            message: '执行异常: $e',
          );
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已复制 $label 到剪贴板')));
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(body: Center(child: Text('开发诊断仅在 Debug 模式可用。')));
    }

    final service = ref.watch(deepLinkServiceProvider);
    final eventLogs = service.eventLogs;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Deep Link / App Links 诊断'),
        actions: [
          IconButton(
            tooltip: '清空事件日志',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: eventLogs.isEmpty ? null : service.clearEventLogs,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Platform Support Info
          _buildPlatformCard(),
          const SizedBox(height: 16),

          // URI Input Card
          _buildInputCard(),
          const SizedBox(height: 16),

          // Presets Card
          _buildPresetsCard(),
          const SizedBox(height: 16),

          // Parse Result Panel
          if (_parseResult != null) ...[
            _buildParseResultCard(_parseResult!),
            const SizedBox(height: 16),
          ],

          // Execution Result Panel
          if (_executionResult != null) ...[
            _buildExecutionResultCard(_executionResult!),
            const SizedBox(height: 16),
          ],

          // Real-time Event Logs Card
          _buildEventLogsCard(eventLogs, service),
          const SizedBox(height: 16),

          // CLI Commands Card
          _buildCliCommandsCard(),
        ],
      ),
    );
  }

  Widget _buildPlatformCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.link, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Deep Link 平台支持情况',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                _StatusChip(
                  platform: 'Android',
                  supported: true,
                  label: 'gotoim-dev:// (VIEW Intent)',
                ),
                _StatusChip(
                  platform: 'iOS',
                  supported: true,
                  label: 'gotoim-dev:// (URL Scheme)',
                ),
                _StatusChip(
                  platform: 'macOS',
                  supported: true,
                  label: 'gotoim-dev:// (URL Scheme)',
                ),
                _StatusChip(
                  platform: 'Windows',
                  supported: true,
                  label: 'gotoim-dev:// (SendAppLink)',
                ),
                _StatusChip(
                  platform: 'Linux',
                  supported: true,
                  label: 'gtk / desktop link',
                ),
                _StatusChip(
                  platform: 'Web',
                  supported: true,
                  label: 'URL Stream / Manual',
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '说明：当前阶段启用开发自定义 Scheme (gotoim-dev://)，未来 HTTPS (https://gotoim.com) 统一复用现有解析代码。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('URI 输入与测试', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _uriController,
              decoration: InputDecoration(
                labelText: 'Deep Link / App Link URI',
                hintText: 'gotoim-dev://chat/123',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() => _uriController.clear()),
                ),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _working ? null : _parseOnly,
                    icon: const Icon(Icons.manage_search),
                    label: const Text('解析 (仅查看)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _working ? null : _execute,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('执行 (真实路由)'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('预设测试案例', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              '点击预设案例快速填充输入框：',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  _presets.map((preset) {
                    final isSelected = _uriController.text == preset.uri;
                    return ActionChip(
                      avatar: Icon(
                        isSelected ? Icons.check_circle : Icons.arrow_forward,
                        size: 16,
                      ),
                      label: Text(preset.label),
                      tooltip: '${preset.description}\n${preset.uri}',
                      onPressed: () => _applyPreset(preset),
                    );
                  }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParseResultCard(DeepLinkParseResult result) {
    final statusColor =
        result.isSuccess
            ? Colors.green
            : result.isUnsupported
            ? Colors.orange
            : Colors.red;

    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  result.isSuccess
                      ? Icons.check_circle
                      : result.isUnsupported
                      ? Icons.help_outline
                      : Icons.error_outline,
                  color: statusColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '解析结果: ${result.status.name.toUpperCase()}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '复制解析 JSON',
                  icon: const Icon(Icons.copy, size: 20),
                  onPressed:
                      () => _copy(
                        const JsonEncoder.withIndent(
                          '  ',
                        ).convert(result.toMap()),
                        '解析结果',
                      ),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 4),
            _infoRow('Raw URI', result.rawUri.toString()),
            _infoRow(
              'Scheme',
              result.rawUri.scheme.isEmpty ? '(none)' : result.rawUri.scheme,
            ),
            _infoRow(
              'Host',
              result.rawUri.host.isEmpty ? '(none)' : result.rawUri.host,
            ),
            _infoRow(
              'Path',
              result.rawUri.path.isEmpty ? '(none)' : result.rawUri.path,
            ),
            _infoRow(
              'Normalized Segments',
              '[${result.normalizedSegments.join(', ')}]',
            ),
            if (result.target != null) ...[
              _infoRow('Target Type', result.target!.targetType),
              _infoRow(
                'Requires Auth',
                result.target!.requiresAuth ? '是 (true)' : '否 (false)',
              ),
              _infoRow(
                'Target Details',
                const JsonEncoder.withIndent(
                  '  ',
                ).convert(result.target!.toMap()),
              ),
            ],
            if (result.reason != null)
              _infoRow('Reason / Error', result.reason!, color: statusColor),
          ],
        ),
      ),
    );
  }

  Widget _buildExecutionResultCard(DeepLinkExecutionResult result) {
    final statusColor =
        result.isSuccess
            ? Colors.green
            : result.isNeedsAuth
            ? Colors.blue
            : result.isNotImplemented
            ? Colors.orange
            : Colors.red;

    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  result.isSuccess
                      ? Icons.check_circle
                      : result.isNeedsAuth
                      ? Icons.lock_clock
                      : result.isNotImplemented
                      ? Icons.construction
                      : Icons.cancel,
                  color: statusColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '执行结果: ${result.status.name.toUpperCase()}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '耗时: ${result.elapsedMs} ms',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 4),
            _infoRow('Target Type', result.target?.targetType ?? '(none)'),
            _infoRow('Message', result.message, color: statusColor),
          ],
        ),
      ),
    );
  }

  Widget _buildEventLogsCard(
    List<DeepLinkEventLog> eventLogs,
    DeepLinkService service,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '真实 App Links 事件日志',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '系统冷启动 / 实时链接流 / 诊断记录 (共 ${eventLogs.length} 条)',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                if (eventLogs.isNotEmpty)
                  TextButton.icon(
                    onPressed: service.clearEventLogs,
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('清空'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (eventLogs.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Text(
                    '暂未收到 Deep Link 事件。\n可使用下方 adb / Start-Process 命令或手动执行测试。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: eventLogs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final log = eventLogs[index];
                  final statusColor =
                      log.parseResult.isSuccess
                          ? Colors.green
                          : log.parseResult.isUnsupported
                          ? Colors.orange
                          : Colors.red;

                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      log.source.contains('stream')
                          ? Icons.stream
                          : log.source.contains('cold')
                          ? Icons.ac_unit
                          : Icons.touch_app,
                      color: statusColor,
                      size: 20,
                    ),
                    title: SelectableText(
                      log.rawUri.toString(),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_formatTime(log.timestamp)}  •  源: ${log.source}  •  状态: ${log.parseResult.status.name}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                        if (log.executionResult != null)
                          Text(
                            '执行: ${log.executionResult!.status.name} (${log.executionResult!.message})',
                            style: TextStyle(fontSize: 11, color: statusColor),
                          ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.copy, size: 16),
                      tooltip: '复制事件数据',
                      onPressed:
                          () => _copy(
                            const JsonEncoder.withIndent(
                              '  ',
                            ).convert(log.toMap()),
                            '事件记录',
                          ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCliCommandsCard() {
    final uri = _uriController.text.trim();
    final androidCmd =
        'adb shell am start -a android.intent.action.VIEW -d "$uri"';
    final iosCmd = 'xcrun simctl openurl booted "$uri"';
    final winCmd = 'Start-Process "$uri"';
    final macCmd = 'open "$uri"';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '外部系统唤醒命令 (直接复制)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              '在终端执行以下命令，测试操作系统级 Deep Link 唤醒：',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            _cliCommandTile('Android (adb)', androidCmd),
            const SizedBox(height: 8),
            _cliCommandTile('Windows (PowerShell)', winCmd),
            const SizedBox(height: 8),
            _cliCommandTile('iOS Simulator', iosCmd),
            const SizedBox(height: 8),
            _cliCommandTile('macOS (Terminal)', macCmd),
          ],
        ),
      ),
    );
  }

  Widget _cliCommandTile(String platform, String command) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  platform,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  command,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: '复制命令',
            onPressed: () => _copy(command, '$platform 命令'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class _PresetCase {
  const _PresetCase({
    required this.label,
    required this.uri,
    required this.description,
  });

  final String label;
  final String uri;
  final String description;
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.platform,
    required this.supported,
    required this.label,
  });

  final String platform;
  final bool supported;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(
        supported ? Icons.check_circle : Icons.cancel,
        color: supported ? Colors.green : Colors.grey,
        size: 16,
      ),
      label: Text('$platform: $label'),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}
