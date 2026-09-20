import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/network_probe_service.dart';
import '../../auth/application/auth_controller.dart';
import '../application/connection_test_controller.dart';

class ConnectionTestPage extends ConsumerStatefulWidget {
  const ConnectionTestPage({super.key});

  @override
  ConsumerState<ConnectionTestPage> createState() => _ConnectionTestPageState();
}

class _ConnectionTestPageState extends ConsumerState<ConnectionTestPage> {
  final _ownerIdController = TextEditingController();
  final _sessionUnitIdController = TextEditingController();
  final _customUrlController = TextEditingController();
  final _customNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Auto-probe on initial open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(networkProbeServiceProvider).probeAll();
    });
  }

  @override
  void dispose() {
    _ownerIdController.dispose();
    _sessionUnitIdController.dispose();
    _customUrlController.dispose();
    _customNameController.dispose();
    super.dispose();
  }

  Future<void> _addCustomTarget(NetworkProbeService service) async {
    final url = _customUrlController.text.trim();
    if (url.isEmpty) return;
    final name = _customNameController.text.trim();
    await service.addCustomTarget(url, name: name.isEmpty ? null : name);
    _customUrlController.clear();
    _customNameController.clear();
    if (mounted) {
      FocusScope.of(context).unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(connectionTestControllerProvider);
    final probeService = ref.watch(networkProbeServiceProvider);
    final summary = probeService.summary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('网络与连接诊断'),
        actions: [
          IconButton(
            tooltip: '重新探测全部网络',
            icon: probeService.isProbing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            onPressed: probeService.isProbing ? null : probeService.probeAll,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Diagnostic Summary Card
          _DiagnosticSummaryCard(
            summary: summary,
            isProbing: probeService.isProbing,
            onProbeAll: probeService.probeAll,
            onRestartSignalR: () async {
              final gateway = ref.read(signalRGatewayProvider);
              await gateway.restart(fast: true);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已触发 SignalR 极速重连')),
                );
              }
            },
          ),
          const SizedBox(height: 20),

          // 2. Server Endpoints
          _SectionHeader(
            title: 'IM 服务端连通性与延时',
            subtitle: '探测 API、认证授权服务及 SignalR 实时 Hub',
            icon: Icons.dns_rounded,
          ),
          const SizedBox(height: 8),
          ...probeService.allTargets
              .where((t) => t.category == NetworkProbeCategory.server)
              .map((target) => _ProbeTargetTile(
                    target: target,
                    result: probeService.results[target.url],
                    onProbe: () => probeService.probeTarget(target),
                  )),

          const SizedBox(height: 20),

          // 3. Public Reference Probes
          _SectionHeader(
            title: '公网连通性参考 (用于对照排查)',
            subtitle: '公网正常而服务端异常即说明为服务器端问题；全失败说明本地无网络',
            icon: Icons.public_rounded,
          ),
          const SizedBox(height: 8),
          ...probeService.allTargets
              .where((t) => t.category == NetworkProbeCategory.public)
              .map((target) => _ProbeTargetTile(
                    target: target,
                    result: probeService.results[target.url],
                    onProbe: () => probeService.probeTarget(target),
                  )),

          const SizedBox(height: 20),

          // 4. Custom User URLs
          _SectionHeader(
            title: '自定义网址探测',
            subtitle: '支持添加内网、私有云或自定义服务器地址进行对照测试',
            icon: Icons.add_link_rounded,
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _customNameController,
                          decoration: const InputDecoration(
                            labelText: '名称 (选填)',
                            hintText: '如：备用网关',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _customUrlController,
                          decoration: const InputDecoration(
                            labelText: '网址/IP',
                            hintText: 'https://example.com',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => _addCustomTarget(probeService),
                        child: const Text('添加'),
                      ),
                    ],
                  ),
                  if (probeService.customTargets.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        '暂无自定义网址，可输入任意地址进行延时与连通测试。',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    )
                  else ...[
                    const SizedBox(height: 12),
                    ...probeService.customTargets.map((target) => _ProbeTargetTile(
                          target: target,
                          result: probeService.results[target.url],
                          onProbe: () => probeService.probeTarget(target),
                          onDelete: () => probeService.removeCustomTarget(target.url),
                        )),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // 5. Business API & Token Tests
          _SectionHeader(
            title: '业务 API 与 Token 验证',
            subtitle: '测试 ABP 业务接口及 OAuth 令牌刷新流程',
            icon: Icons.security_rounded,
          ),
          const SizedBox(height: 8),
          _TestCard(
            title: '刷新 Token (OAuth 2.0 /connect/token)',
            description: '调用刷新凭证，验证服务端 Token 续期流程与拦截器',
            status: controller.refreshStatus,
            onPressed: controller.refreshStatus == ConnectionTestStatus.testing
                ? null
                : controller.refreshToken,
            buttonText: '刷新 Token',
            detail: controller.refreshError ?? controller.refreshResult,
          ),
          const SizedBox(height: 12),
          _TestCard(
            title: '认证 API (/connect/userinfo)',
            description: '使用当前 AccessToken 调用，验证当前用户授权有效性',
            status: controller.apiStatus,
            onPressed: controller.apiStatus == ConnectionTestStatus.testing
                ? null
                : controller.testAuthenticatedApi,
            buttonText: '测试认证 API',
            detail: controller.apiError ?? controller.apiResult,
          ),
          const SizedBox(height: 12),
          _TestCard(
            title: '好友业务 API (/api/chat/session-unit-cache/friends)',
            description: '获取指定 ownerId 的好友缓存列表',
            status: controller.friendsStatus,
            onPressed: controller.friendsStatus == ConnectionTestStatus.testing
                ? null
                : () => controller.testFriendsApi(_ownerIdController.text.trim()),
            buttonText: '测试好友 API',
            detail: controller.friendsError ?? controller.friendsResult,
            input: TextField(
              controller: _ownerIdController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'ownerId',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _TestCard(
            title: '消息快速加载 API (/api/chat/message/fast)',
            description: '获取指定 sessionUnitId 的消息列表',
            status: controller.messagesStatus,
            onPressed: controller.messagesStatus == ConnectionTestStatus.testing
                ? null
                : () => controller.testMessagesApi(_sessionUnitIdController.text.trim()),
            buttonText: '测试消息 API',
            detail: controller.messagesError ?? controller.messagesResult,
            input: TextField(
              controller: _sessionUnitIdController,
              decoration: const InputDecoration(
                labelText: 'sessionUnitId',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DiagnosticSummaryCard extends StatelessWidget {
  const _DiagnosticSummaryCard({
    required this.summary,
    required this.isProbing,
    required this.onProbeAll,
    required this.onRestartSignalR,
  });

  final NetworkDiagnosticSummary summary;
  final bool isProbing;
  final VoidCallback onProbeAll;
  final VoidCallback onRestartSignalR;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final Color bgColor;
    final Color textColor;
    final IconData icon;

    if (summary.isLocalNetworkIssue || summary.isServerIssue) {
      bgColor = colorScheme.errorContainer;
      textColor = colorScheme.onErrorContainer;
      icon = Icons.error_outline_rounded;
    } else if (!summary.isHealthy) {
      bgColor = Colors.orange.withValues(alpha: 0.15);
      textColor = Colors.deepOrange;
      icon = Icons.warning_amber_rounded;
    } else {
      bgColor = Colors.green.withValues(alpha: 0.12);
      textColor = Colors.green.shade800;
      icon = Icons.check_circle_outline_rounded;
    }

    return Card(
      color: bgColor,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: textColor.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: textColor, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    summary.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              summary.detail,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: textColor.withValues(alpha: 0.9),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: isProbing ? null : onProbeAll,
                  icon: isProbing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.network_check_rounded, size: 18),
                  label: Text(isProbing ? '探测中…' : '重新探测全部'),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: onRestartSignalR,
                  icon: const Icon(Icons.sync_rounded, size: 18),
                  label: const Text('极速重置长连接'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProbeTargetTile extends StatelessWidget {
  const _ProbeTargetTile({
    required this.target,
    required this.result,
    required this.onProbe,
    this.onDelete,
  });

  final NetworkProbeTarget target;
  final NetworkProbeResult? result;
  final VoidCallback onProbe;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final res = result;

    Color badgeColor = Colors.grey.shade400;
    String badgeText = '未测试';
    if (res != null) {
      switch (res.state) {
        case NetworkProbeState.idle:
          badgeColor = Colors.grey.shade400;
          badgeText = '待测';
          break;
        case NetworkProbeState.probing:
          badgeColor = Colors.blue;
          badgeText = '测试中…';
          break;
        case NetworkProbeState.success:
          badgeColor = Colors.green;
          badgeText = '${res.totalLatencyMs} ms';
          break;
        case NetworkProbeState.slow:
          badgeColor = Colors.orange;
          badgeText = '${res.totalLatencyMs} ms (偏高)';
          break;
        case NetworkProbeState.failed:
          badgeColor = Colors.red;
          badgeText = res.statusCode != null ? 'HTTP ${res.statusCode}' : '失败';
          break;
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              target.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: badgeColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: badgeColor.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              badgeText,
                              style: TextStyle(
                                color: badgeColor,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      SelectableText(
                        target.url,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '单项测试',
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  onPressed: onProbe,
                ),
                if (onDelete != null)
                  IconButton(
                    tooltip: '删除',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: onDelete,
                  ),
              ],
            ),
            if (res != null && res.state != NetworkProbeState.idle && res.state != NetworkProbeState.probing) ...[
              const Divider(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  if (res.ipAddress != null)
                    _MetricChip(label: 'IP', value: res.ipAddress!),
                  if (res.dnsTimeMs != null)
                    _MetricChip(label: 'DNS', value: '${res.dnsTimeMs} ms'),
                  if (res.httpLatencyMs != null)
                    _MetricChip(label: 'HTTP', value: '${res.httpLatencyMs} ms'),
                  if (res.statusCode != null)
                    _MetricChip(
                      label: '状态码',
                      value: '${res.statusCode}',
                      isError: (res.statusCode ?? 0) >= 400,
                    ),
                ],
              ),
              if (res.errorMessage != null && res.errorMessage!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        '错误：${res.errorMessage}',
                        style: TextStyle(
                          color: colorScheme.error,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 14),
                      tooltip: '复制错误',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: res.errorMessage!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已复制错误信息')),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    this.isError = false,
  });

  final String label;
  final String value;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label: $value',
      style: TextStyle(
        fontSize: 11,
        color: isError ? Colors.red : Colors.grey.shade700,
        fontFamily: 'monospace',
      ),
    );
  }
}

class _TestCard extends StatelessWidget {
  const _TestCard({
    required this.title,
    required this.description,
    required this.status,
    required this.onPressed,
    required this.buttonText,
    this.detail,
    this.input,
  });

  final String title;
  final String description;
  final ConnectionTestStatus status;
  final VoidCallback? onPressed;
  final String buttonText;
  final String? detail;
  final Widget? input;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFailure = status == ConnectionTestStatus.failure;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            if (input != null) ...[const SizedBox(height: 10), input!],
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.tonal(
                  onPressed: onPressed,
                  child: status == ConnectionTestStatus.testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(buttonText),
                ),
                if (detail != null) ...[
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    tooltip: '复制结果',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: detail!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制结果')),
                      );
                    },
                  ),
                ],
              ],
            ),
            if (detail != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isFailure
                      ? theme.colorScheme.errorContainer.withValues(alpha: 0.4)
                      : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  detail!,
                  style: TextStyle(
                    color: isFailure ? theme.colorScheme.error : null,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
