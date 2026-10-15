import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/pages/url_interstitial_page.dart';
import '../../../core/security/url_security_level.dart';
import '../../../core/security/url_security_repository.dart';
import '../../../core/security/url_security_service.dart';
import '../../../core/security/widgets/report_dialog.dart';
import '../../../core/security/widgets/url_risk_dialog.dart';
import '../../../core/widgets/app_toast.dart';

/// URL 安全与反诈风控诊断中心页面
///
/// 严格遵循 AGENTS.md 规范第 25 条：
/// - 功能说明、支持平台；
/// - 输入参数允许自定义并提供预设；
/// - 执行按钮、真实执行状态、耗时（ms）、结构化返回值；
/// - 复制功能与恢复默认。
class UrlSecurityDiagnosticsPage extends ConsumerStatefulWidget {
  const UrlSecurityDiagnosticsPage({super.key});

  @override
  ConsumerState<UrlSecurityDiagnosticsPage> createState() =>
      _UrlSecurityDiagnosticsPageState();
}

class _UrlSecurityDiagnosticsPageState
    extends ConsumerState<UrlSecurityDiagnosticsPage> {
  late final TextEditingController _urlController;
  late final TextEditingController _titleController;
  late final TextEditingController _customHostController;
  bool _useInterstitialPage = true;

  String _executionStatus = '未执行';
  int _durationMs = 0;
  String _outputJson = '';
  String? _errorTrace;

  static const String _defaultUrl = 'https://flutter.dev/docs';

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: _defaultUrl);
    _titleController = TextEditingController(text: 'Flutter 开发者文档');
    _customHostController = TextEditingController(text: 'custom-untrusted.org');
  }

  @override
  void dispose() {
    _urlController.dispose();
    _titleController.dispose();
    _customHostController.dispose();
    super.dispose();
  }

  void _resetDefaults() {
    setState(() {
      _urlController.text = _defaultUrl;
      _titleController.text = 'Flutter 开发者文档';
      _customHostController.text = 'custom-untrusted.org';
      _useInterstitialPage = true;
      _executionStatus = '已恢复默认设置';
      _durationMs = 0;
      _outputJson = '';
      _errorTrace = null;
    });
    showToast('已重置测试参数');
  }

  void _copyOutput() {
    if (_outputJson.isEmpty && _errorTrace == null) {
      showToast('暂无内容可复制');
      return;
    }
    final content = _errorTrace != null
        ? '$_outputJson\n\nStack Trace:\n$_errorTrace'
        : _outputJson;
    Clipboard.setData(ClipboardData(text: content));
    showToast('诊断结果已复制到剪贴板', type: ToastType.success);
  }

  Future<void> _runCheck() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      showToast('请输入测试网址', type: ToastType.warning);
      return;
    }

    setState(() {
      _executionStatus = '执行中...';
      _outputJson = '';
      _errorTrace = null;
    });

    final service = ref.read(urlSecurityServiceProvider);
    final stopwatch = Stopwatch()..start();

    try {
      final result = await service.checkUrl(url);
      stopwatch.stop();

      setState(() {
        _executionStatus = '执行成功';
        _durationMs = stopwatch.elapsedMilliseconds;
        _outputJson = const JsonEncoder.withIndent('  ').convert({
          'input': {
            'url': url,
            'title': _titleController.text.trim(),
            'useInterstitialPage': _useInterstitialPage,
          },
          'evaluation': result.toJson(),
          'policy': {
            'isTrustedDomain': service.isTrustedDomain(url),
            'isDangerousDownload': service.isDangerousDownload(url),
            'recommendedAction': result.isSafe
                ? '直接在内置安全 WebView 静默打开'
                : (result.isBlocked
                    ? '阻断访问，展示红色禁止拦截页'
                    : (_useInterstitialPage
                        ? '展示黄色微信同款中转警示页'
                        : '展示前置风险防诈弹窗')),
          },
        });
      });
    } catch (e, st) {
      stopwatch.stop();
      setState(() {
        _executionStatus = '执行失败';
        _durationMs = stopwatch.elapsedMilliseconds;
        _outputJson = '异常信息: $e';
        _errorTrace = st.toString();
      });
    }
  }

  Future<void> _openFullExperience() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    final service = ref.read(urlSecurityServiceProvider);
    await service.openUrl(
      context,
      url: url,
      title: _titleController.text.trim().isNotEmpty
          ? _titleController.text.trim()
          : null,
      useInterstitialPage: _useInterstitialPage,
    );
  }

  Future<void> _previewWarningInterstitial() async {
    final url = _urlController.text.trim();
    final service = ref.read(urlSecurityServiceProvider);
    final res = await service.checkUrl(url);
    final warningRes = UrlSecurityCheckResult(
      url: res.url,
      domain: res.domain,
      level: UrlSecurityLevel.warning,
      category: UrlRiskCategory.unknownThirdParty,
      message: '你即将离开 GotoIM 访问第三方网站，请注意防范电信网络诈骗。',
      interceptReason: '第三方未经认证的外链网站',
      checkedAt: DateTime.now(),
    );
    if (!mounted) return;
    await UrlInterstitialPage.open(
      context,
      checkResult: warningRes,
      title: _titleController.text.trim(),
    );
  }

  Future<void> _previewBlockedInterstitial() async {
    final url = _urlController.text.trim();
    final service = ref.read(urlSecurityServiceProvider);
    final res = await service.checkUrl(url);
    final blockedRes = UrlSecurityCheckResult(
      url: res.url,
      domain: res.domain,
      level: UrlSecurityLevel.blocked,
      category: UrlRiskCategory.fraud,
      message: '据用户投诉及相关法律法规核查，该网页包含违法/诈骗/违规内容。',
      interceptReason: '涉嫌虚假投资返利与冒充公检法电信诈骗（黑名单规则命中）',
      checkedAt: DateTime.now(),
    );
    if (!mounted) return;
    await UrlInterstitialPage.open(
      context,
      checkResult: blockedRes,
      title: _titleController.text.trim(),
    );
  }

  Future<void> _previewRiskDialog() async {
    final url = _urlController.text.trim();
    final service = ref.read(urlSecurityServiceProvider);
    final res = await service.checkUrl(url);
    if (!mounted) return;
    await UrlRiskDialog.show(context, checkResult: res);
  }

  Future<void> _triggerReportModal() async {
    final url = _urlController.text.trim();
    await ReportDialog.showForUrl(
      context,
      url: url,
      title: _titleController.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final repo = ref.watch(urlSecurityRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('URL 安全与反诈风控诊断'),
        actions: [
          IconButton(
            tooltip: '重置默认值',
            icon: const Icon(Icons.refresh),
            onPressed: _resetDefaults,
          ),
          IconButton(
            tooltip: '复制诊断结果',
            icon: const Icon(Icons.copy_rounded),
            onPressed: _copyOutput,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 平台支持标识（AGENTS.md 规范） ──────────────────────────────────
          _buildPlatformCard(isDark),
          const SizedBox(height: 12),

          // ── 功能说明卡片 ──────────────────────────────────────────────────
          _buildInfoCard(isDark),
          const SizedBox(height: 16),

          // ── 快速预设场景测试 ──────────────────────────────────────────────
          _buildPresetsCard(isDark),
          const SizedBox(height: 16),

          // ── 输入参数区域 ──────────────────────────────────────────────────
          _buildInputsCard(theme, isDark),
          const SizedBox(height: 16),

          // ── 操作按钮矩阵 ──────────────────────────────────────────────────
          _buildActionsCard(theme),
          const SizedBox(height: 16),

          // ── 动态白名单/黑名单管理 ─────────────────────────────────────────
          _buildRulesManagerCard(repo, isDark),
          const SizedBox(height: 16),

          // ── 结构化执行结果输出 ────────────────────────────────────────────
          _buildExecutionOutputCard(theme, isDark),
        ],
      ),
    );
  }

  Widget _buildPlatformCard(bool isDark) {
    const platforms = [
      {'name': 'Android', 'supported': true},
      {'name': 'iOS', 'supported': true},
      {'name': 'iPad', 'supported': true},
      {'name': 'Windows', 'supported': true},
      {'name': 'macOS', 'supported': true},
      {'name': 'Linux', 'supported': true},
      {'name': 'Web', 'supported': true},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '支持平台验证 (Platform Verification)',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: platforms.map((p) {
              final isSupported = p['supported'] as bool;
              return Chip(
                padding: EdgeInsets.zero,
                labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
                avatar: Icon(
                  isSupported ? Icons.check_circle : Icons.cancel,
                  size: 14,
                  color: isSupported ? const Color(0xFF10B981) : Colors.red,
                ),
                label: Text(
                  '${p['name']}',
                  style: const TextStyle(fontSize: 11),
                ),
                backgroundColor: isDark ? Colors.white10 : Colors.white,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF).withValues(alpha: isDark ? 0.15 : 0.8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.security_rounded, color: Color(0xFF2563EB), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '三阶段风控体系：\n'
              '1. 域名检测与分级 (Safe / Warning / Blocked)；\n'
              '2. 隔离敏感 JSBridge、拦截危险 APK 下载；\n'
              '3. 微信同款风险中转页、阻断拦截页与标准化举报投诉流程。',
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: isDark ? const Color(0xFFBFDBFE) : const Color(0xFF1E3A8A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetsCard(bool isDark) {
    final presets = [
      {
        'title': '官方白名单',
        'url': 'https://gotoim.com/safety',
        'pageTitle': 'GotoIM 安全中心',
        'color': const Color(0xFF10B981),
      },
      {
        'title': '未知普通外链 (灰名单)',
        'url': 'https://flutter.dev/docs',
        'pageTitle': 'Flutter 开发者文档',
        'color': const Color(0xFFF59E0B),
      },
      {
        'title': '涉诈黑名单 (杀猪盘/刷单)',
        'url': 'https://scam-test.xyz/lottery-claim',
        'pageTitle': '中奖领取中心',
        'color': const Color(0xFFEF4444),
      },
      {
        'title': '钓鱼盗号黑名单',
        'url': 'https://phishing-test.com/login-steal',
        'pageTitle': '仿冒安全验证',
        'color': const Color(0xFFDC2626),
      },
      {
        'title': '危险安装包 APK 下载',
        'url': 'https://example.com/malicious_payload.apk',
        'pageTitle': '应用更新包',
        'color': const Color(0xFF8B5CF6),
      },
      {
        'title': '非法 Scheme 注入',
        'url': 'javascript:alert("xss")',
        'pageTitle': '脚本攻击测试',
        'color': Colors.grey,
      },
    ];

    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '快速预设场景测试 (Preset Test Cases)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: presets.map((p) {
                return ActionChip(
                  label: Text(p['title'] as String),
                  labelStyle: TextStyle(
                    fontSize: 11.5,
                    color: p['color'] as Color,
                    fontWeight: FontWeight.w600,
                  ),
                  avatar: Icon(Icons.flash_on_rounded, size: 14, color: p['color'] as Color),
                  onPressed: () {
                    setState(() {
                      _urlController.text = p['url'] as String;
                      _titleController.text = p['pageTitle'] as String;
                    });
                    _runCheck();
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputsCard(ThemeData theme, bool isDark) {
    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '输入参数 (Configurable Parameters)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: '测试网址 (URL)',
                hintText: 'https://...',
                prefixIcon: Icon(Icons.link_rounded),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: '网页标题 (Title)',
                hintText: '可选标题',
                prefixIcon: Icon(Icons.title_rounded),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('优先使用微信同款中转页 (否则使用弹窗)', style: TextStyle(fontSize: 13)),
              subtitle: Text(
                _useInterstitialPage ? '当前模式: 全屏黄盾中转页' : '当前模式: 风险前置弹窗',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              value: _useInterstitialPage,
              onChanged: (val) => setState(() => _useInterstitialPage = val),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsCard(ThemeData theme) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('评估安全风控等级'),
                onPressed: _runCheck,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF07C160),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('真实流程打开'),
                onPressed: _openFullExperience,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.gpp_maybe_outlined, color: Color(0xFFF59E0B)),
                label: const Text('预览黄盾中转页'),
                onPressed: _previewWarningInterstitial,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.gpp_bad_outlined, color: Color(0xFFEF4444)),
                label: const Text('预览红盾阻断页'),
                onPressed: _previewBlockedInterstitial,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: const Text('测试风险弹窗'),
                onPressed: _previewRiskDialog,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.flag_outlined, color: Color(0xFFEF4444)),
                label: const Text('测试违规举报'),
                onPressed: _triggerReportModal,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRulesManagerCard(UrlSecurityRepository repo, bool isDark) {
    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '动态黑白名单规则管理 (Rules Runtime Engine)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '当前已生效白名单: ${repo.trustedHosts.length} 项，黑名单: ${repo.blockedHosts.length} 项',
              style: const TextStyle(fontSize: 11.5, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customHostController,
                    decoration: const InputDecoration(
                      labelText: '目标域名 (Host)',
                      hintText: 'example.org',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {
                    final h = _customHostController.text.trim();
                    if (h.isNotEmpty) {
                      repo.addTrustedHost(h);
                      showToast('已加入白名单: $h');
                      _runCheck();
                    }
                  },
                  child: const Text('+ 加白', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 4),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFEF4444),
                  ),
                  onPressed: () {
                    final h = _customHostController.text.trim();
                    if (h.isNotEmpty) {
                      repo.addBlockedHost(h, reason: '诊断中心测试手动阻断');
                      showToast('已加入黑名单: $h');
                      _runCheck();
                    }
                  },
                  child: const Text('+ 阻断', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExecutionOutputCard(ThemeData theme, bool isDark) {
    final statusColor = _executionStatus == '执行成功'
        ? const Color(0xFF10B981)
        : (_executionStatus == '执行中...'
            ? Colors.blue
            : (_executionStatus.startsWith('执行失败') ? Colors.red : Colors.grey));

    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text(
                      '实际执行结果 (Execution Output)',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _executionStatus,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_durationMs > 0)
                  Text(
                    '耗时: $_durationMs ms',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (_outputJson.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF121212) : const Color(0xFF282C34),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  _outputJson,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Color(0xFFABB2BF),
                    height: 1.4,
                  ),
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    '点击上方按钮执行安全检测或流程验证',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ),
            if (_errorTrace != null) ...[
              const SizedBox(height: 10),
              ExpansionTile(
                title: const Text('错误堆栈 (Stack Trace)', style: TextStyle(fontSize: 12, color: Colors.red)),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SelectableText(
                      _errorTrace!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
