import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../application/session_list_controller.dart';

/// Interactive status banner showing SignalR connection status, error reasons,
/// and providing diagnostic actions (reconnect, network test, server test).
class SignalRStatusBar extends StatelessWidget {
  const SignalRStatusBar({
    required this.state,
    required this.onReconnect,
    this.errorDescription,
    this.hubUrl,
    super.key,
  });

  final SessionRealtimeStatus state;
  final Future<void> Function() onReconnect;
  final String? errorDescription;
  final String? hubUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final busy =
        state == SessionRealtimeStatus.connecting ||
        state == SessionRealtimeStatus.reconnecting;
    final text = switch (state) {
      SessionRealtimeStatus.connecting => 'SignalR 正在连接…',
      SessionRealtimeStatus.reconnecting => 'SignalR 正在重新连接…',
      SessionRealtimeStatus.disconnecting => 'SignalR 正在断开…',
      SessionRealtimeStatus.disconnected => 'SignalR 连接断开，点击排查',
      SessionRealtimeStatus.connected => '',
    };

    return Material(
      color: colorScheme.errorContainer,
      child: InkWell(
        onTap: () => _openTroubleshootSheet(context),
        child: SizedBox(
          height: 38,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    Icons.cloud_off_outlined,
                    size: 18,
                    color: colorScheme.onErrorContainer,
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      color: colorScheme.onErrorContainer,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                if (!busy)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.onErrorContainer.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '排查/重试',
                      style: TextStyle(
                        color: colorScheme.onErrorContainer,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openTroubleshootSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => _SignalRTroubleshootSheet(
        state: state,
        onReconnect: onReconnect,
        errorDescription: errorDescription,
        hubUrl: hubUrl,
      ),
    );
  }
}

class _SignalRTroubleshootSheet extends StatefulWidget {
  const _SignalRTroubleshootSheet({
    required this.state,
    required this.onReconnect,
    this.errorDescription,
    this.hubUrl,
  });

  final SessionRealtimeStatus state;
  final Future<void> Function() onReconnect;
  final String? errorDescription;
  final String? hubUrl;

  @override
  State<_SignalRTroubleshootSheet> createState() =>
      _SignalRTroubleshootSheetState();
}

class _SignalRTroubleshootSheetState extends State<_SignalRTroubleshootSheet> {
  bool _isReconnecting = false;
  bool _isTestingNetwork = false;
  bool _isTestingServer = false;
  String? _networkTestResult;
  String? _serverTestResult;

  Future<void> _handleReconnect() async {
    setState(() => _isReconnecting = true);
    try {
      await widget.onReconnect();
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已触发重连请求')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('重连失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isReconnecting = false);
    }
  }

  Future<void> _testNetwork() async {
    setState(() {
      _isTestingNetwork = true;
      _networkTestResult = null;
    });
    final stopwatch = Stopwatch()..start();
    try {
      final host = widget.hubUrl != null && widget.hubUrl!.isNotEmpty
          ? (Uri.tryParse(widget.hubUrl!)?.host ?? '')
          : '';
      final targetHost = host.isNotEmpty ? host : 'connectivitycheck.gstatic.com';
      final lookup = await InternetAddress.lookup(targetHost);
      stopwatch.stop();
      if (lookup.isNotEmpty) {
        setState(() {
          _networkTestResult =
              '网络正常，DNS 解析目标 ($targetHost) 成功，耗时 ${stopwatch.elapsedMilliseconds} ms。\nIP: ${lookup.map((e) => e.address).join(", ")}';
        });
      } else {
        setState(() {
          _networkTestResult = 'DNS 解析异常：未查询到该主机 IP 地址。';
        });
      }
    } catch (e) {
      stopwatch.stop();
      setState(() {
        _networkTestResult = '网络测试失败：无法连通外网或目标域名无法解析 ($e)';
      });
    } finally {
      setState(() => _isTestingNetwork = false);
    }
  }

  Future<void> _testServer() async {
    setState(() {
      _isTestingServer = true;
      _serverTestResult = null;
    });
    final stopwatch = Stopwatch()..start();
    try {
      final targetUrl = widget.hubUrl != null && widget.hubUrl!.isNotEmpty
          ? widget.hubUrl!
          : '';
      if (targetUrl.isEmpty) {
        setState(() {
          _serverTestResult = '服务器地址未配置。';
        });
        return;
      }
      final uri = Uri.parse(targetUrl);
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      final request = await client.getUrl(uri);
      final response = await request.close();
      stopwatch.stop();
      setState(() {
        _serverTestResult =
            '服务端响应 HTTP ${response.statusCode}，耗时 ${stopwatch.elapsedMilliseconds} ms。';
      });
    } catch (e) {
      stopwatch.stop();
      setState(() {
        _serverTestResult = '服务端探测失败：$e';
      });
    } finally {
      setState(() => _isTestingServer = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final errorMsg = widget.errorDescription != null &&
            widget.errorDescription!.isNotEmpty
        ? widget.errorDescription!
        : '未建立连接或连接意外中断。请检查网络设置或确认后端 SignalR 服务运行状态。';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      color: colorScheme.onErrorContainer,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SignalR 实时长连接异常排查',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '实时通知、消息即时到达依赖此连接',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(height: 24),
              Text(
                '异常原因：',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: SelectableText(
                  errorMsg,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (widget.hubUrl != null && widget.hubUrl!.isNotEmpty) ...[
                Text(
                  '目标 Hub 地址：',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  widget.hubUrl!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_networkTestResult != null) ...[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _networkTestResult!,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
              if (_serverTestResult != null) ...[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _serverTestResult!,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isTestingNetwork ? null : _testNetwork,
                      icon: _isTestingNetwork
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.network_check_rounded, size: 18),
                      label: const Text('测试网络'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isTestingServer ? null : _testServer,
                      icon: _isTestingServer
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.dns_rounded, size: 18),
                      label: const Text('测试服务器'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isReconnecting ? null : _handleReconnect,
                      icon: _isReconnecting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('立即重连'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.push('/diagnostics/connection');
                    },
                    icon: const Icon(Icons.network_check_outlined, size: 18),
                    label: const Text('全面探测'),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.push('/diagnostics/signalr');
                    },
                    icon: const Icon(Icons.analytics_outlined, size: 18),
                    label: const Text('SignalR日志'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
