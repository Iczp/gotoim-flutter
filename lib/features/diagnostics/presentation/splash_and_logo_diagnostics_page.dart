import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_mode_controller.dart';
import '../../../core/widgets/gotoim_logo.dart';
import '../../auth/presentation/auth_loading_page.dart';

/// 启动页与 Logo 沉浸式体验诊断中心
///
/// 提供 Logo 实验室、全屏 Splash 模拟启动、深浅色底色融合测试以及系统栏穿透诊断。
class SplashAndLogoDiagnosticsPage extends ConsumerStatefulWidget {
  const SplashAndLogoDiagnosticsPage({super.key});

  @override
  ConsumerState<SplashAndLogoDiagnosticsPage> createState() =>
      _SplashAndLogoDiagnosticsPageState();
}

class _SplashAndLogoDiagnosticsPageState
    extends ConsumerState<SplashAndLogoDiagnosticsPage> {
  double _logoSize = 130.0;
  bool _enableBreathing = true;
  int _selectedColorIndex = 0;
  int _selectedBgIndex = 0;

  static const List<Color> _glowColors = [
    Color(0xFF00E5FF), // 电光青
    Color(0xFF38BDF8), // 极光天蓝
    Color(0xFF818CF8), // 科技星云紫
    Color(0xFF34D399), // 矩阵翠绿
  ];

  static const List<String> _glowColorNames = ['电光青 (默认)', '极光蓝', '星云紫', '矩阵绿'];

  static const List<String> _bgNames = [
    '深空黑 (#070B14)',
    '赛博极光渐变',
    '浅色科技白 (#F8FAFC)',
    '半透明毛玻璃',
  ];

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已复制 $label 到剪贴板')));
  }

  void _resetToDefault() {
    setState(() {
      _logoSize = 130.0;
      _enableBreathing = true;
      _selectedColorIndex = 0;
      _selectedBgIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mediaQuery = MediaQuery.of(context);
    final themeMode = ref.watch(themeModeProvider);

    final currentGlowColor = _glowColors[_selectedColorIndex];

    return Scaffold(
      appBar: AppBar(
        title: const Text('启动页与 Logo 体验中心'),
        actions: [
          IconButton(
            tooltip: '切换浅色/深色主题',
            icon: Icon(
              themeMode == ThemeMode.dark
                  ? Icons.dark_mode_rounded
                  : Icons.light_mode_rounded,
            ),
            onPressed:
                () =>
                    ref
                        .read(themeModeControllerProvider.notifier)
                        .toggleTheme(),
          ),
          IconButton(
            tooltip: '恢复默认设置',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _resetToDefault,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 1. 平台支持与概览 ──────────────────────────────────────────
          _buildCard(
            title: '功能概览与支持平台',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'GotoIM 采用沉浸式全屏启动架构与透明自发光量子对话徽标，消除原生底栏与顶栏切边黑条，实现 100% 满屏穿透。',
                  style: TextStyle(fontSize: 13.5, height: 1.45),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: const [
                    _PlatformChip(platform: 'Android', supported: true),
                    _PlatformChip(platform: 'iOS', supported: true),
                    _PlatformChip(platform: 'Windows', supported: true),
                    _PlatformChip(platform: 'macOS', supported: true),
                    _PlatformChip(platform: 'Web', supported: true),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── 2. Logo 实验室 ───────────────────────────────────────────
          _buildCard(
            title: 'Logo 实验室 (交互调节)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 实时预览视窗
                Center(
                  child: Container(
                    width: double.infinity,
                    height: 220,
                    decoration: _getPreviewBoxDecoration(isDark),
                    child: Center(
                      child: GotoImLogo(
                        size: _logoSize,
                        enableBreathing: _enableBreathing,
                        glowColor: currentGlowColor,
                        heroTag: null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 尺寸调节 Slider
                Row(
                  children: [
                    Text('尺寸: ${_logoSize.toInt()} px'),
                    Expanded(
                      child: Slider(
                        value: _logoSize,
                        min: 48,
                        max: 220,
                        divisions: 43,
                        label: '${_logoSize.toInt()} px',
                        onChanged: (val) => setState(() => _logoSize = val),
                      ),
                    ),
                  ],
                ),

                // 呼吸微动开关
                SwitchListTile(
                  title: const Text('自发光呼吸微动'),
                  subtitle: const Text('开启科技生命力脉冲，缓动光晕弥散'),
                  value: _enableBreathing,
                  onChanged: (val) => setState(() => _enableBreathing = val),
                  contentPadding: EdgeInsets.zero,
                ),

                // 高光色切换
                const Text(
                  '高光自发光色彩：',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(_glowColors.length, (idx) {
                    final isSelected = _selectedColorIndex == idx;
                    return ChoiceChip(
                      selected: isSelected,
                      label: Text(_glowColorNames[idx]),
                      avatar: CircleAvatar(
                        backgroundColor: _glowColors[idx],
                        radius: 7,
                      ),
                      onSelected:
                          (_) => setState(() => _selectedColorIndex = idx),
                    );
                  }),
                ),
                const SizedBox(height: 12),

                // 背景色测试（验证无黑底切边残影）
                const Text(
                  '背景融合测试（验证全场景无方框黑底残影）：',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(_bgNames.length, (idx) {
                    final isSelected = _selectedBgIndex == idx;
                    return ChoiceChip(
                      selected: isSelected,
                      label: Text(_bgNames[idx]),
                      onSelected: (_) => setState(() => _selectedBgIndex = idx),
                    );
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── 3. 全屏 Splash 沉浸体验 ──────────────────────────────────
          _buildCard(
            title: '全屏 Splash 沉浸体验',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '点击下方按钮将以全屏模式打开真实的 Splash 启动页，可现场体验穿透状态栏、底部安全区与超时逃生按钮。',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          fullscreenDialog: true,
                          builder:
                              (_) => const AuthLoadingPage(
                                isDiagnosticsPreview: true,
                              ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.fullscreen_rounded),
                    label: const Text('启动全屏沉浸 Splash 体验'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── 4. 屏幕物理边缘与 Inset 诊断 ──────────────────────────────
          _buildCard(
            title: '屏幕边缘与 Insets 诊断',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow(
                  '屏幕分辨率',
                  '${mediaQuery.size.width.toInt()} × ${mediaQuery.size.height.toInt()} pt',
                ),
                _buildInfoRow(
                  '像素密度 (dpr)',
                  '${mediaQuery.devicePixelRatio.toStringAsFixed(2)}x',
                ),
                _buildInfoRow(
                  '状态栏高度 (Top Inset)',
                  '${mediaQuery.padding.top.toStringAsFixed(1)} pt',
                ),
                _buildInfoRow(
                  '底部导航栏 (Bottom Inset)',
                  '${mediaQuery.padding.bottom.toStringAsFixed(1)} pt',
                ),
                _buildInfoRow('EdgeToEdge 满屏状态', '已激活 (穿透系统状态栏与导航条)'),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    final report = '''
屏幕分辨率: ${mediaQuery.size.width} x ${mediaQuery.size.height}
设备像素比: ${mediaQuery.devicePixelRatio}
顶部状态栏: ${mediaQuery.padding.top}
底部手势栏: ${mediaQuery.padding.bottom}
EdgeToEdge: Enabled
Current Theme: ${theme.brightness.name}
Logo Size: ${_logoSize}px
Logo Breathing: $_enableBreathing
''';
                    _copyToClipboard(report, '屏幕与 Logo 诊断参数');
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('复制屏幕与 Logo 诊断参数'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _getPreviewBoxDecoration(bool isDark) {
    switch (_selectedBgIndex) {
      case 0:
        return BoxDecoration(
          color: const Color(0xFF070B14),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        );
      case 1:
        return BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF050B17), Color(0xFF0B1936), Color(0xFF070B14)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
          ),
        );
      case 2:
        return BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        );
      case 3:
      default:
        return BoxDecoration(
          color:
              isDark
                  ? const Color(0xFF1E293B).withValues(alpha: 0.6)
                  : const Color(0xFFE2E8F0).withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.2)),
        );
    }
  }

  Widget _buildCard({required String title, required Widget child}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color:
            supported
                ? const Color(0xFF10B981).withValues(alpha: 0.12)
                : Colors.grey.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
              supported
                  ? const Color(0xFF10B981).withValues(alpha: 0.4)
                  : Colors.grey.withValues(alpha: 0.4),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            supported ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 14,
            color: supported ? const Color(0xFF10B981) : Colors.grey,
          ),
          const SizedBox(width: 4),
          Text(
            platform,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: supported ? const Color(0xFF047857) : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
