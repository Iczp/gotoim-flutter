import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/compliance/agreement_viewer_page.dart';
import '../../../core/compliance/privacy_consent_dialog.dart';
import '../../../core/compliance/privacy_service.dart';
import '../../app_update/application/app_update_service.dart';
import '../../app_update/data/models/app_version_dto.dart';
import '../../app_update/presentation/app_update_dialog.dart';

/// Comprehensive diagnostics for Privacy Compliance and App Version Upgrade.
class PrivacyAndUpdateDiagnosticsPage extends ConsumerStatefulWidget {
  const PrivacyAndUpdateDiagnosticsPage({super.key});

  @override
  ConsumerState<PrivacyAndUpdateDiagnosticsPage> createState() =>
      _PrivacyAndUpdateDiagnosticsPageState();
}

class _PrivacyAndUpdateDiagnosticsPageState
    extends ConsumerState<PrivacyAndUpdateDiagnosticsPage> {
  // Configurable parameters for update simulation
  late final TextEditingController _versionCodeController;
  late final TextEditingController _versionNameController;
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late final TextEditingController _pkgUrlController;
  bool _isForce = false;

  // Execution state
  String _executionStatus = '未执行';
  int _durationMs = 0;
  String _outputJson = '';
  String? _errorTrace;

  @override
  void initState() {
    super.initState();
    _versionCodeController = TextEditingController(text: '2');
    _versionNameController = TextEditingController(text: '1.1.0');
    _titleController = TextEditingController(text: '发现新版本 1.1.0');
    _contentController = TextEditingController(
      text: '1. 新增首次启动用户隐私保护与合规授权\n2. 新增应用版本静默检查与强制升级\n3. 优化多设备登录状态同步性能',
    );
    _pkgUrlController = TextEditingController(
      text: 'https://storage.flutter-io.cn/sample_apk.apk',
    );
  }

  @override
  void dispose() {
    _versionCodeController.dispose();
    _versionNameController.dispose();
    _titleController.dispose();
    _contentController.dispose();
    _pkgUrlController.dispose();
    super.dispose();
  }

  Future<void> _runServerCheck() async {
    final service = ref.read(appUpdateServiceProvider);
    setState(() {
      _executionStatus = '执行中...';
      _outputJson = '';
      _errorTrace = null;
    });

    final stopwatch = Stopwatch()..start();
    try {
      final latest = await service.checkUpdate(silent: true);
      stopwatch.stop();
      setState(() {
        _executionStatus = '执行成功';
        _durationMs = stopwatch.elapsedMilliseconds;
        _outputJson = const JsonEncoder.withIndent('  ').convert({
          'input': {
            'appId': service.appId,
            'platform': service.platformName,
            'currentVersionCode': service.currentVersionCode,
            'currentVersionName': service.currentVersionName,
          },
          'output': latest?.toJson() ?? '服务端无新版本返回',
          'shouldUpdate': service.shouldUpdate(latest),
        });
      });
    } catch (e, st) {
      stopwatch.stop();
      setState(() {
        _executionStatus = '执行失败';
        _durationMs = stopwatch.elapsedMilliseconds;
        _outputJson = '异常: $e';
        _errorTrace = st.toString();
      });
    }
  }

  void _simulateUpdateDialog({required bool isForce}) {
    final updateService = ref.read(appUpdateServiceProvider);
    final targetVersionCode =
        int.tryParse(_versionCodeController.text.trim()) ?? 2;
    final simulated = AppVersionDto(
      version: _versionNameController.text.trim(),
      versionCode: targetVersionCode,
      title: _titleController.text.trim(),
      content: _contentController.text.trim(),
      isForce: isForce,
      pkgUrl: _pkgUrlController.text.trim(),
      pageUrl: 'https://gotoim.com/download',
    );

    setState(() {
      _executionStatus = '已打开模拟升级弹窗';
      _durationMs = 0;
      _outputJson = const JsonEncoder.withIndent('  ').convert({
        'action': 'simulate_dialog',
        'isForce': isForce,
        'simulatedDto': simulated.toJson(),
      });
    });

    AppUpdateDialog.show(context, version: simulated, updateService: updateService);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final privacy = ref.watch(privacyServiceProvider);
    final updateService = ref.watch(appUpdateServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('合规授权与版本升级诊断'),
        elevation: 0.5,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 平台支持标签 ──────────────────────────────────────────
          _PlatformSupportCard(),
          const SizedBox(height: 16),

          // ── 1. 首次启动隐私合规诊断 ────────────────────────────────
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.privacy_tip_rounded,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '首次启动隐私协议授权',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('当前授权状态：'),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: privacy.hasAgreed
                              ? colorScheme.primaryContainer
                              : colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          privacy.hasAgreed ? '已授权 (已同意)' : '未授权 (首次启动)',
                          style: TextStyle(
                            color: privacy.hasAgreed
                                ? colorScheme.onPrimaryContainer
                                : colorScheme.onErrorContainer,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (privacy.agreedAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '授权时间：${privacy.agreedAt!.toLocal()}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: const Text('模拟首次弹窗'),
                        onPressed: () {
                          PrivacyConsentDialog.show(
                            context,
                            privacyService: privacy,
                          );
                        },
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('重置授权记录'),
                        onPressed: () async {
                          await privacy.resetAgreement();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('隐私授权状态已重置为未同意'),
                              ),
                            );
                          }
                        },
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.description_outlined, size: 16),
                        label: const Text('查看用户协议'),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const AgreementViewerPage(
                                title: PrivacyService.userAgreementTitle,
                                content: PrivacyService.userAgreementContent,
                              ),
                            ),
                          );
                        },
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.shield_outlined, size: 16),
                        label: const Text('查看隐私政策'),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const AgreementViewerPage(
                                title: PrivacyService.privacyPolicyTitle,
                                content: PrivacyService.privacyPolicyContent,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── 2. 应用版本检查与升级诊断 ────────────────────────────────
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.system_update_rounded,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '应用版本检查与升级',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '当前客户端环境：平台=${updateService.platformName} · AppId=${updateService.appId} · VersionCode=${updateService.currentVersionCode} · VersionName=${updateService.currentVersionName}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Editable inputs for simulated payload
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _versionNameController,
                          decoration: const InputDecoration(
                            labelText: '目标版本名',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _versionCodeController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '目标 VersionCode',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: '更新标题',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _contentController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: '版本特性日志',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _pkgUrlController,
                    decoration: const InputDecoration(
                      labelText: 'APK 安装包直链 URL',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    title: const Text('强制更新 (isForce)'),
                    subtitle: const Text('开启后拦截返回键与点击外部，必须升级'),
                    contentPadding: EdgeInsets.zero,
                    value: _isForce,
                    onChanged: (val) => setState(() => _isForce = val),
                  ),
                  const SizedBox(height: 12),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        icon: const Icon(Icons.cloud_sync_rounded, size: 16),
                        label: const Text('调用服务端真实最新版本'),
                        onPressed: _runServerCheck,
                      ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.notification_important_rounded, size: 16),
                        label: const Text('模拟普通升级弹窗'),
                        onPressed: () => _simulateUpdateDialog(isForce: false),
                      ),
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          backgroundColor: colorScheme.errorContainer,
                          foregroundColor: colorScheme.onErrorContainer,
                        ),
                        icon: const Icon(Icons.block_rounded, size: 16),
                        label: const Text('模拟强制升级弹窗'),
                        onPressed: () => _simulateUpdateDialog(isForce: true),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── 3. 诊断输出监控 ──────────────────────────────────────────
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '执行状态与结构化输出',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        tooltip: '复制输出',
                        onPressed: _outputJson.isEmpty
                            ? null
                            : () async {
                                await Clipboard.setData(
                                  ClipboardData(text: _outputJson),
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('已复制诊断结果到剪贴板'),
                                      duration: Duration(seconds: 1),
                                    ),
                                  );
                                }
                              },
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '执行状态: $_executionStatus · 耗时: $_durationMs ms',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _executionStatus == '执行失败'
                          ? colorScheme.error
                          : colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(minHeight: 80, maxHeight: 220),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _outputJson.isEmpty ? '等待执行...' : _outputJson,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  if (_errorTrace != null) ...[
                    const SizedBox(height: 8),
                    ExpansionTile(
                      title: Text(
                        '异常调用栈',
                        style: TextStyle(color: colorScheme.error, fontSize: 13),
                      ),
                      children: [
                        SelectableText(
                          _errorTrace!,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: colorScheme.error,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlatformSupportCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _PlatformItem(name: 'Android', supported: true),
          _PlatformItem(name: 'iOS', supported: true),
          _PlatformItem(name: 'iPad', supported: true),
          _PlatformItem(name: 'Windows', supported: true),
          _PlatformItem(name: 'macOS', supported: true),
          _PlatformItem(name: 'Linux', supported: true),
          _PlatformItem(name: 'Web', supported: true),
        ],
      ),
    );
  }
}

class _PlatformItem extends StatelessWidget {
  const _PlatformItem({required this.name, required this.supported});

  final String name;
  final bool supported;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(name, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 2),
        Text(
          supported ? '✓' : '×',
          style: TextStyle(
            color: supported ? Colors.green : Colors.red,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
