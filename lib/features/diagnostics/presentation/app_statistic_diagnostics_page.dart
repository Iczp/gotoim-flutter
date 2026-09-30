import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/statistic/statistic_event.dart';
import '../../../core/statistic/statistic_event_names.dart';
import '../../../core/statistic/statistic_page_names.dart';
import '../../../core/statistic/statistic_service.dart';

/// AppStatistic 埋点与数据统计开发诊断页
class AppStatisticDiagnosticsPage extends StatefulWidget {
  const AppStatisticDiagnosticsPage({super.key});

  @override
  State<AppStatisticDiagnosticsPage> createState() =>
      _AppStatisticDiagnosticsPageState();
}

class _AppStatisticDiagnosticsPageState
    extends State<AppStatisticDiagnosticsPage> {
  // ── 输入控制 ──
  late final TextEditingController _baseUrlController;
  late final TextEditingController _eventNameController;
  late final TextEditingController _pageNameController;
  late final TextEditingController _propertiesController;

  String _selectedPresetEvent = StatisticEventNames.pageView;
  bool _isFlushing = false;
  bool _isTestingApi = false;
  String _executionStatus = '未执行';
  int _executionDurationMs = 0;
  String _executionResult = '';
  String _executionError = '';

  List<StatisticEvent> _recentEvents = <StatisticEvent>[];
  int _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    final config = StatisticService.instance.config;
    _baseUrlController = TextEditingController(text: config.baseUrl);
    _eventNameController = TextEditingController(text: StatisticEventNames.pageView);
    _pageNameController = TextEditingController(text: StatisticPageNames.home);
    _propertiesController = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
        'source': 'diagnostics',
        'debug': true,
      }),
    );
    _refreshState();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _eventNameController.dispose();
    _pageNameController.dispose();
    _propertiesController.dispose();
    super.dispose();
  }

  Future<void> _refreshState() async {
    final repo = StatisticService.instance.repository;
    if (repo != null) {
      final count = await repo.getPendingCount();
      final recents = await repo.getRecentEvents(limit: 20);
      if (mounted) {
        setState(() {
          _pendingCount = count;
          _recentEvents = recents;
        });
      }
    }
  }

  void _onPresetChanged(String? val) {
    if (val == null) return;
    setState(() {
      _selectedPresetEvent = val;
      _eventNameController.text = val;
      if (val == StatisticEventNames.pageView ||
          val == StatisticEventNames.pageLeave) {
        _pageNameController.text = StatisticPageNames.chatSession;
        _propertiesController.text = val == StatisticEventNames.pageLeave
            ? '{\n  "durationSeconds": 45\n}'
            : '{\n  "source": "manual_test"\n}';
      } else if (val == StatisticEventNames.crash) {
        _propertiesController.text =
            '{\n  "errorType": "DiagnosticsTestException",\n  "message": "Manual crash simulation"\n}';
      } else if (val == StatisticEventNames.login) {
        _propertiesController.text = '{\n  "method": "account_password"\n}';
      } else {
        _propertiesController.text = '{\n  "test": true\n}';
      }
    });
  }

  Future<void> _triggerTrack() async {
    final name = _eventNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('事件名不能为空')),
      );
      return;
    }

    Map<String, dynamic>? props;
    final rawProps = _propertiesController.text.trim();
    if (rawProps.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawProps);
        if (decoded is Map) {
          props = Map<String, dynamic>.from(decoded);
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Properties JSON 解析失败: $e')),
        );
        return;
      }
    }

    final page = _pageNameController.text.trim().isEmpty
        ? null
        : _pageNameController.text.trim();

    await StatisticService.instance.track(
      name,
      page: page,
      properties: props,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已写入本地队列: $name')),
    );

    await _refreshState();
  }

  Future<void> _triggerFlush() async {
    setState(() {
      _isFlushing = true;
      _executionStatus = '执行中...';
      _executionResult = '';
      _executionError = '';
    });

    final stopwatch = Stopwatch()..start();
    try {
      final repo = StatisticService.instance.repository;
      final config = StatisticService.instance.config;
      if (repo == null) {
        throw StateError('StatisticRepository 未初始化');
      }

      final result = await repo.uploadPendingBatch(
        appId: config.appId,
        channel: config.channel,
        limit: config.maxBatchSize,
      );
      stopwatch.stop();

      setState(() {
        _executionDurationMs = stopwatch.elapsedMilliseconds;
        if (result.isSuccess) {
          _executionStatus = '执行成功';
          _executionResult =
              '状态码: ${result.statusCode ?? 200}\n接收总数: ${result.receivedCount}\n入库新事件: ${result.successCount}\n重复被忽略: ${result.duplicateCount}';
        } else {
          _executionStatus = '执行失败';
          _executionError = result.errorMessage ?? '未知错误';
        }
      });
    } catch (e, st) {
      stopwatch.stop();
      setState(() {
        _executionDurationMs = stopwatch.elapsedMilliseconds;
        _executionStatus = '发生异常';
        _executionError = '$e\n$st';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isFlushing = false;
        });
      }
      await _refreshState();
    }
  }

  Future<void> _testApiDirectly() async {
    setState(() {
      _isTestingApi = true;
      _executionStatus = '正在连通测试...';
      _executionResult = '';
      _executionError = '';
    });

    final stopwatch = Stopwatch()..start();
    try {
      final repo = StatisticService.instance.repository;
      final config = StatisticService.instance.config;
      if (repo == null) throw StateError('StatisticRepository 未就绪');

      // 仅发送一条即时心跳事件测试通信
      await StatisticService.instance.track(
        'diagnostics_ping',
        properties: <String, dynamic>{
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      final result = await repo.uploadPendingBatch(
        appId: config.appId,
        channel: config.channel,
        limit: 10,
      );
      stopwatch.stop();

      setState(() {
        _executionDurationMs = stopwatch.elapsedMilliseconds;
        if (result.isSuccess) {
          _executionStatus = 'API 连通测试成功';
          _executionResult =
              'HTTP Endpoint: ${config.baseUrl}/api/app-statistic/events\n成功上报事件并验证幂等响应。\nReceived: ${result.receivedCount}, Success: ${result.successCount}, Dup: ${result.duplicateCount}';
        } else {
          _executionStatus = 'API 连通失败';
          _executionError =
              'Endpoint: ${config.baseUrl}/api/app-statistic/events\n${result.errorMessage}';
        }
      });
    } catch (e, st) {
      stopwatch.stop();
      setState(() {
        _executionDurationMs = stopwatch.elapsedMilliseconds;
        _executionStatus = 'API 测试异常';
        _executionError = '$e\n$st';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isTestingApi = false;
        });
      }
      await _refreshState();
    }
  }

  Future<void> _clearLocalQueue() async {
    final repo = StatisticService.instance.repository;
    if (repo != null) {
      await repo.clearQueue();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已清空本地统计队列')),
      );
      await _refreshState();
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制 $label 到剪贴板')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = StatisticService.instance;
    final config = service.config;
    final device = service.currentDeviceInfo;

    return Scaffold(
      appBar: AppBar(
        title: const Text('数据统计与埋点 (AppStatistic)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新状态',
            onPressed: _refreshState,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 1. 平台支持与概览 ──────────────────────────────────────────
          _buildCard(
            title: '平台支持情况与环境',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: const [
                    _PlatformChip(platform: 'Android', supported: true),
                    _PlatformChip(platform: 'iOS', supported: true),
                    _PlatformChip(platform: 'iPad', supported: true),
                    _PlatformChip(platform: 'Windows', supported: true),
                    _PlatformChip(platform: 'macOS', supported: true),
                    _PlatformChip(platform: 'Linux', supported: true),
                    _PlatformChip(platform: 'Web', supported: true),
                  ],
                ),
                const SizedBox(height: 12),
                _buildInfoRow('服务初始化状态', service.isInitialized ? '已就绪 (Ready)' : '未就绪'),
                _buildInfoRow('统计功能开关', config.enabled ? '已开启' : '已关闭'),
                _buildInfoRow('当前用户 ID', service.currentUserId ?? '未登录 (匿名)'),
                _buildInfoRow('AppId', config.appId),
                _buildInfoRow('发布渠道 (Channel)', config.channel),
                _buildInfoRow('服务端 BaseUrl', config.baseUrl),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ── 2. 设备与会话信息 (Device & Session) ────────────────────────
          _buildCard(
            title: '设备与会话凭据 (Device & Session)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoRow(
                        'DeviceKey',
                        service.currentDeviceKey ?? '生成中...',
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      tooltip: '复制 DeviceKey',
                      onPressed: () => _copyToClipboard(
                        service.currentDeviceKey ?? '',
                        'DeviceKey',
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoRow('SessionId', service.currentSessionId),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      tooltip: '复制 SessionId',
                      onPressed: () => _copyToClipboard(
                        service.currentSessionId,
                        'SessionId',
                      ),
                    ),
                  ],
                ),
                _buildInfoRow(
                  '设备环境',
                  '${device?.platform ?? '未知'} | ${device?.osName ?? ''} ${device?.osVersion ?? ''}',
                ),
                _buildInfoRow(
                  '型号与品牌',
                  '${device?.manufacturer ?? ''} ${device?.model ?? ''}',
                ),
                _buildInfoRow('应用版本', device?.appVersion ?? '未知'),
                _buildInfoRow('语言与时区', '${device?.language ?? ''} | ${device?.timeZone ?? ''}'),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ── 3. 本地队列与上传控制 ────────────────────────────────────
          _buildCard(
            title: '队列调度与上传控制',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '本地待上传事件: $_pendingCount 条',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Text(
                      service.queue?.isUploading == true ? '上传中...' : '空闲',
                      style: TextStyle(
                        color: service.queue?.isUploading == true
                            ? Colors.orange
                            : Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '自动上传规则：达到 ${config.batchSize} 条立即上报，或每隔 ${config.uploadInterval.inSeconds} 秒轮询，切后台或网络恢复时自动触发。',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      icon: _isFlushing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_upload_outlined),
                      label: const Text('立即上传队列 (Flush)'),
                      onPressed: _isFlushing ? null : _triggerFlush,
                    ),
                    OutlinedButton.icon(
                      icon: _isTestingApi
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.network_ping_outlined),
                      label: const Text('测试 API 连通性'),
                      onPressed: _isTestingApi ? null : _testApiDirectly,
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      label: const Text('清空本地队列', style: TextStyle(color: Colors.red)),
                      onPressed: _clearLocalQueue,
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ── 4. 执行状态与返回结果展示 ──────────────────────────────────
          _buildCard(
            title: '执行状态与返回结果',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('状态: $_executionStatus', style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (_executionDurationMs > 0)
                      Text('耗时: $_executionDurationMs ms', style: const TextStyle(color: Colors.blueGrey)),
                  ],
                ),
                if (_executionResult.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                    ),
                    child: SelectableText(
                      _executionResult,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    ),
                  ),
                ],
                if (_executionError.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: SelectableText(
                      _executionError,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.red),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ── 5. 手动模拟打点测试 ────────────────────────────────────────
          _buildCard(
            title: '手动模拟打点 (Track Event)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('预设典型事件：', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                DropdownButton<String>(
                  value: _selectedPresetEvent,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: StatisticEventNames.pageView, child: Text('page_view (页面访问)')),
                    DropdownMenuItem(value: StatisticEventNames.pageLeave, child: Text('page_leave (页面离开停留)')),
                    DropdownMenuItem(value: StatisticEventNames.appStart, child: Text('app_start (应用冷启动)')),
                    DropdownMenuItem(value: StatisticEventNames.appForeground, child: Text('app_foreground (进入前台)')),
                    DropdownMenuItem(value: StatisticEventNames.appBackground, child: Text('app_background (进入后台)')),
                    DropdownMenuItem(value: StatisticEventNames.login, child: Text('login (账号登录)')),
                    DropdownMenuItem(value: StatisticEventNames.logout, child: Text('logout (账号退出)')),
                    DropdownMenuItem(value: StatisticEventNames.crash, child: Text('crash (异常崩溃捕获)')),
                  ],
                  onChanged: _onPresetChanged,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _eventNameController,
                  decoration: const InputDecoration(
                    labelText: '事件名称 (eventName)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _pageNameController,
                  decoration: const InputDecoration(
                    labelText: '页面标识 (page, 可空)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _propertiesController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: '事件属性 (Properties JSON)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add_chart_outlined),
                  label: const Text('写入埋点 (Track)'),
                  onPressed: _triggerTrack,
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ── 6. 最近入队事件明细 ────────────────────────────────────────
          _buildCard(
            title: '本地最近记录明细 (${_recentEvents.length})',
            child: _recentEvents.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: Text('暂无本地待上传事件', style: TextStyle(color: Colors.grey))),
                  )
                : Column(
                    children: _recentEvents.map((e) {
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${e.eventName}  [${e.page ?? '无页面'}]',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          'ID: ${e.eventId.substring(0, 8)}... | 时间: ${e.eventTime.toIso8601String().substring(11, 19)}\n属性: ${e.properties ?? "{}"}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.copy, size: 16),
                          tooltip: '复制事件 JSON',
                          onPressed: () => _copyToClipboard(
                            jsonEncode(e.toApiDto()),
                            '事件 JSON',
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({required String title, required Widget child}) {
    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Divider(height: 18),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlatformChip extends StatelessWidget {
  const _PlatformChip({required this.platform, required this.supported});

  final String platform;
  final bool supported;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: supported
            ? Colors.green.withValues(alpha: 0.12)
            : Colors.grey.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$platform ${supported ? '✓' : '×'}',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: supported ? Colors.green.shade800 : Colors.grey,
        ),
      ),
    );
  }
}
