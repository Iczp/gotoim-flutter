import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/application_providers.dart';
import '../../auth/application/auth_controller.dart';

/// 开发诊断中心 - ABP 应用配置与当前账号诊断页面
///
/// 遵循 AGENTS.md 规范：
/// 包含功能说明、平台支持、输入参数、执行状态、返回值结构化渲染、耗时、异常信息、复制与清除缓存等。
class AbpConfigurationDiagnosticsPage extends ConsumerStatefulWidget {
  const AbpConfigurationDiagnosticsPage({super.key});

  @override
  ConsumerState<AbpConfigurationDiagnosticsPage> createState() =>
      _AbpConfigurationDiagnosticsPageState();
}

enum _ExecutionStatus { idle, loading, success, failure }

class _AbpConfigurationDiagnosticsPageState
    extends ConsumerState<AbpConfigurationDiagnosticsPage> {
  bool _includeLocalizationResources = false;
  _ExecutionStatus _status = _ExecutionStatus.idle;
  int? _elapsedMs;
  Object? _lastError;
  StackTrace? _lastStackTrace;
  DateTime? _lastExecutedAt;
  DateTime? _lastCachedAt;
  bool _isClearingCache = false;

  @override
  void initState() {
    super.initState();
    _loadCacheMeta();
  }

  Future<void> _loadCacheMeta() async {
    final repo = ref.read(abpConfigurationRepositoryProvider);
    final cachedAt = await repo.readLastCachedAt();
    if (mounted) {
      setState(() => _lastCachedAt = cachedAt);
    }
  }

  Future<void> _fetchConfiguration() async {
    if (_status == _ExecutionStatus.loading) return;
    setState(() {
      _status = _ExecutionStatus.loading;
      _lastError = null;
      _lastStackTrace = null;
      _elapsedMs = null;
    });

    final stopwatch = Stopwatch()..start();
    try {
      final repo = ref.read(abpConfigurationRepositoryProvider);
      await repo.fetchAndCacheConfiguration(
        includeLocalizationResources: _includeLocalizationResources,
      );
      stopwatch.stop();

      // 同步触发 AuthController 刷新
      await ref.read(authControllerProvider).fetchApplicationConfiguration();
      await _loadCacheMeta();

      if (mounted) {
        setState(() {
          _status = _ExecutionStatus.success;
          _elapsedMs = stopwatch.elapsedMilliseconds;
          _lastExecutedAt = DateTime.now();
        });
      }
    } catch (e, st) {
      stopwatch.stop();
      if (mounted) {
        setState(() {
          _status = _ExecutionStatus.failure;
          _lastError = e;
          _lastStackTrace = st;
          _elapsedMs = stopwatch.elapsedMilliseconds;
          _lastExecutedAt = DateTime.now();
        });
      }
    }
  }

  Future<void> _clearCache() async {
    if (_isClearingCache) return;
    setState(() => _isClearingCache = true);
    try {
      final repo = ref.read(abpConfigurationRepositoryProvider);
      await repo.clearCache();
      await _loadCacheMeta();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已清除 ABP 配置本地 SQLite 缓存。')));
      }
    } finally {
      if (mounted) {
        setState(() => _isClearingCache = false);
      }
    }
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已复制 $label 到剪贴板。')));
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(body: Center(child: Text('开发诊断仅在 Debug 模式可用。')));
    }

    final authState = ref.watch(authControllerProvider);
    final currentUser = authState.currentUser;
    final config = authState.applicationConfiguration;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ABP 配置与当前账号'),
        actions: [
          IconButton(
            tooltip: '重置参数',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _includeLocalizationResources = false;
                _status = _ExecutionStatus.idle;
                _lastError = null;
                _lastStackTrace = null;
                _elapsedMs = null;
              });
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 1. 功能说明与平台支持 ────────────────────────────────────────
          _buildCard(
            title: '接口契约与功能说明',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '应用启动及账号登录成功后，必调用 /api/abp/application-configuration 并进行本地 SQLite 缓存。'
                  'API 响应报文中的 currentUser 对应当前登录人，直接映射为当前活跃账号。',
                  style: TextStyle(fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 8),
                const Text(
                  '接口路径：GET /api/abp/application-configuration\n通道类型：API Dio (携带 Bearer Token + 401 自动刷新)',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: Colors.blueGrey,
                  ),
                ),
                const Divider(height: 16),
                _buildPlatformSupportTable(),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── 2. 输入参数与操作 ──────────────────────────────────────────
          _buildCard(
            title: '执行与输入参数',
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('IncludeLocalizationResources'),
                  subtitle: const Text('包含多语言资源 (默认 false 以提升启动性能)'),
                  value: _includeLocalizationResources,
                  onChanged:
                      _status == _ExecutionStatus.loading
                          ? null
                          : (v) => setState(
                            () => _includeLocalizationResources = v,
                          ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon:
                            _status == _ExecutionStatus.loading
                                ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                : const Icon(Icons.cloud_download_outlined),
                        label: Text(
                          _status == _ExecutionStatus.loading
                              ? '请求中...'
                              : '拉取配置并写缓存',
                        ),
                        onPressed:
                            _status == _ExecutionStatus.loading
                                ? null
                                : _fetchConfiguration,
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('清除缓存'),
                      onPressed: _isClearingCache ? null : _clearCache,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── 3. 执行状态与耗时 ──────────────────────────────────────────
          _buildCard(
            title: '执行状态',
            child: Column(
              children: [
                _buildRow(
                  '状态',
                  _buildStatusBadge(_status),
                ),
                if (_elapsedMs != null)
                  _buildRow(
                    '耗时',
                    Text(
                      '$_elapsedMs ms',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                if (_lastExecutedAt != null)
                  _buildRow(
                    '最近执行时间',
                    Text(_lastExecutedAt!.toIso8601String().substring(11, 19)),
                  ),
                _buildRow(
                  'SQLite 缓存状态',
                  Text(
                    _lastCachedAt != null
                        ? '已持久化 (${_lastCachedAt!.toIso8601String().substring(0, 19)})'
                        : '暂无缓存',
                    style: TextStyle(
                      color:
                          _lastCachedAt != null
                              ? Colors.green[700]
                              : Colors.orange[800],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── 4. 当前登录人 (currentUser) 渲染 ─────────────────────────────
          _buildCard(
            title: '当前登录人 (currentUser)',
            trailing:
                currentUser != null
                    ? IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      tooltip: '复制 currentUser JSON',
                      onPressed:
                          () => _copy(
                            const JsonEncoder.withIndent(
                              '  ',
                            ).convert(currentUser.toJson()),
                            'currentUser',
                          ),
                    )
                    : null,
            child:
                currentUser == null
                    ? const Text('当前尚未载入 currentUser，请执行拉取或登录。')
                    : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildRow(
                          '认证状态 (isAuthenticated)',
                          Text(
                            currentUser.isAuthenticated ? 'true (已认证)' : 'false (未认证)',
                            style: TextStyle(
                              color:
                                  currentUser.isAuthenticated
                                      ? Colors.green[700]
                                      : Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        _buildRow('用户 ID (id)', Text(currentUser.id ?? 'null'), copyable: true),
                        _buildRow('用户名 (userName)', Text(currentUser.userName ?? 'null'), copyable: true),
                        _buildRow('显示名 (displayName)', Text(currentUser.displayName), copyable: true),
                        _buildRow('全名 (fullName)', Text(currentUser.fullName)),
                        _buildRow('名 (name)', Text(currentUser.name ?? 'null')),
                        _buildRow('姓 (surName)', Text(currentUser.surName ?? 'null')),
                        _buildRow(
                          '邮箱 (email)',
                          Text(
                            '${currentUser.email ?? "null"} (${currentUser.emailVerified ? "已验证" : "未验证"})',
                          ),
                          copyable: currentUser.email != null,
                        ),
                        _buildRow(
                          '手机号 (phoneNumber)',
                          Text(
                            '${currentUser.phoneNumber ?? "null"} (${currentUser.phoneNumberVerified ? "已验证" : "未验证"})',
                          ),
                          copyable: currentUser.phoneNumber != null,
                        ),
                        _buildRow(
                          '角色组 (roles)',
                          Text(
                            currentUser.roles.isEmpty
                                ? '[]'
                                : currentUser.roles.join(', '),
                          ),
                        ),
                        if (currentUser.tenantId != null)
                          _buildRow('租户 ID (tenantId)', Text(currentUser.tenantId!)),
                        if (currentUser.sessionId != null)
                          _buildRow('Session ID', Text(currentUser.sessionId!)),
                      ],
                    ),
          ),
          const SizedBox(height: 16),

          // ── 5. 异常信息 ────────────────────────────────────────────────
          if (_lastError != null) ...[
            _buildCard(
              title: '异常信息',
              color: Colors.red.shade50,
              trailing: IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: '复制异常',
                onPressed:
                    () => _copy(
                      '$_lastError\n\n$_lastStackTrace',
                      '异常信息',
                    ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _lastError.toString(),
                    style: TextStyle(
                      color: Colors.red.shade900,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  if (_lastStackTrace != null) ...[
                    const SizedBox(height: 8),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('展开 StackTrace', style: TextStyle(fontSize: 12)),
                      children: [
                        SelectableText(
                          _lastStackTrace.toString(),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── 6. 完整配置原始报文 (JSON) ──────────────────────────────────
          if (config != null)
            _buildCard(
              title: '应用配置完整报文',
              trailing: IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: '复制完整配置 JSON',
                onPressed:
                    () => _copy(
                      const JsonEncoder.withIndent('  ').convert(config.raw),
                      '完整配置 JSON',
                    ),
              ),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  '查看完整 JSON (${config.raw.keys.length} 个根属性: ${config.raw.keys.take(5).join(", ")}...)',
                  style: const TextStyle(fontSize: 13),
                ),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SelectableText(
                      const JsonEncoder.withIndent('  ').convert(config.raw),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required Widget child,
    Widget? trailing,
    Color? color,
  }) {
    return Card(
      color: color,
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const Divider(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, Widget valueWidget, {bool copyable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(child: valueWidget),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(_ExecutionStatus status) {
    switch (status) {
      case _ExecutionStatus.idle:
        return const Text('未执行', style: TextStyle(color: Colors.grey));
      case _ExecutionStatus.loading:
        return const Text(
          '执行中...',
          style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
        );
      case _ExecutionStatus.success:
        return const Text(
          '成功',
          style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
        );
      case _ExecutionStatus.failure:
        return const Text(
          '失败',
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
        );
    }
  }

  Widget _buildPlatformSupportTable() {
    const platforms = [
      ('Android', '✓'),
      ('iOS', '✓'),
      ('iPad', '✓'),
      ('Windows', '✓'),
      ('macOS', '✓'),
      ('Linux', '✓'),
      ('Web', '✓'),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children:
          platforms
              .map(
                (p) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Text(
                    '${p.$1} ${p.$2}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.green.shade900,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
              .toList(),
    );
  }
}
