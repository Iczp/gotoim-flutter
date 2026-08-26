import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme_tokens.dart';
import '../../../core/theme/theme_mode_controller.dart';
import '../../../core/widgets/glass_container.dart';
import '../../session/presentation/chat_object_avatar.dart';

/// Diagnostics page for inspecting and testing Theme configurations,
/// Dark Mode behavior, ColorTokens, Typography, and Component showcases.
class ThemeDiagnosticsPage extends ConsumerStatefulWidget {
  const ThemeDiagnosticsPage({super.key});

  @override
  ConsumerState<ThemeDiagnosticsPage> createState() =>
      _ThemeDiagnosticsPageState();
}

class _ThemeDiagnosticsPageState extends ConsumerState<ThemeDiagnosticsPage> {
  final _sampleTextController = TextEditingController(text: 'Goto IM 统一设计系统');
  double _sliderValue = 0.65;
  bool _switchValue = true;
  bool _checkboxValue = true;
  double _glassBlurSigma = 18.0;
  double _glassOpacity = 0.75;
  int _glassBackgroundPattern = 0;

  @override
  void dispose() {
    _sampleTextController.dispose();
    super.dispose();
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已复制 $label 到剪贴板')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tokens = context.appTokens;
    final currentThemeMode = ref.watch(themeModeProvider);
    final activeBrightness = theme.brightness;

    final tokensSummary = '''
ThemeMode: ${currentThemeMode.name}
Active Brightness: ${activeBrightness.name}
Primary: #${colorScheme.primary.toARGB32().toRadixString(16).padLeft(8, '0')}
Surface: #${colorScheme.surface.toARGB32().toRadixString(16).padLeft(8, '0')}
SurfaceContainer: #${colorScheme.surfaceContainer.toARGB32().toRadixString(16).padLeft(8, '0')}
SessionPinnedBg: #${tokens.sessionPinnedBackground.toARGB32().toRadixString(16).padLeft(8, '0')}
DividerBorder: #${tokens.dividerBorder.toARGB32().toRadixString(16).padLeft(8, '0')}
MentionBadge: #${tokens.mentionBadgeColor.toARGB32().toRadixString(16).padLeft(8, '0')}
UnreadBadge: #${tokens.unreadBadgeColor.toARGB32().toRadixString(16).padLeft(8, '0')}
''';

    return Scaffold(
      appBar: AppBar(
        title: const Text('主题与暗黑模式诊断'),
        actions: [
          IconButton(
            tooltip: '复制当前主题配置',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () => _copy(tokensSummary, '主题配置'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Platform Support Banner
          _DiagnosticCard(
            title: '平台支持情况',
            icon: Icons.devices_rounded,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
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
          ),

          const SizedBox(height: 12),

          // Theme Mode Switcher
          _DiagnosticCard(
            title: '主题模式控制 (实时生效)',
            icon: Icons.palette_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前应用模式：${currentThemeMode.name}  (实际亮度: ${activeBrightness.name})',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto_outlined),
                      label: Text('跟随系统'),
                    ),
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode_outlined),
                      label: Text('浅色模式'),
                    ),
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode_outlined),
                      label: Text('深色模式'),
                    ),
                  ],
                  selected: {currentThemeMode},
                  onSelectionChanged: (selected) {
                    if (selected.isNotEmpty) {
                      ref
                          .read(themeModeControllerProvider.notifier)
                          .setThemeMode(selected.first);
                    }
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Color Scheme Palette
          _DiagnosticCard(
            title: 'Material 3 调色板与语义色',
            icon: Icons.color_lens_outlined,
            child: Column(
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ColorChip(
                      label: 'Primary',
                      color: colorScheme.primary,
                      textColor: colorScheme.onPrimary,
                    ),
                    _ColorChip(
                      label: 'PrimaryContainer',
                      color: colorScheme.primaryContainer,
                      textColor: colorScheme.onPrimaryContainer,
                    ),
                    _ColorChip(
                      label: 'Secondary',
                      color: colorScheme.secondary,
                      textColor: colorScheme.onSecondary,
                    ),
                    _ColorChip(
                      label: 'SecondaryContainer',
                      color: colorScheme.secondaryContainer,
                      textColor: colorScheme.onSecondaryContainer,
                    ),
                    _ColorChip(
                      label: 'Tertiary',
                      color: colorScheme.tertiary,
                      textColor: colorScheme.onTertiary,
                    ),
                    _ColorChip(
                      label: 'Surface',
                      color: colorScheme.surface,
                      textColor: colorScheme.onSurface,
                    ),
                    _ColorChip(
                      label: 'ContainerLow',
                      color: colorScheme.surfaceContainerLow,
                      textColor: colorScheme.onSurface,
                    ),
                    _ColorChip(
                      label: 'Container',
                      color: colorScheme.surfaceContainer,
                      textColor: colorScheme.onSurface,
                    ),
                    _ColorChip(
                      label: 'ContainerHigh',
                      color: colorScheme.surfaceContainerHigh,
                      textColor: colorScheme.onSurface,
                    ),
                    _ColorChip(
                      label: 'Error',
                      color: colorScheme.error,
                      textColor: colorScheme.onError,
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Custom IM Theme Tokens
          _DiagnosticCard(
            title: 'IM 专用设计 Token (ThemeExtension)',
            icon: Icons.extension_outlined,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ColorChip(
                  label: '置顶会话背景',
                  color: tokens.sessionPinnedBackground,
                  textColor: colorScheme.onSurface,
                ),
                _ColorChip(
                  label: '分割线描边',
                  color: tokens.dividerBorder,
                  textColor: colorScheme.onSurface,
                ),
                _ColorChip(
                  label: '@我 标签',
                  color: tokens.mentionBadgeColor,
                  textColor: Colors.white,
                ),
                _ColorChip(
                  label: '关注 标签',
                  color: tokens.followBadgeColor,
                  textColor: Colors.white,
                ),
                _ColorChip(
                  label: '未读 Badge',
                  color: tokens.unreadBadgeColor,
                  textColor: Colors.white,
                ),
                _ColorChip(
                  label: '我的消息气泡',
                  color: tokens.bubbleMeBackground,
                  textColor: tokens.bubbleMeText,
                ),
                _ColorChip(
                  label: '对方消息气泡',
                  color: tokens.bubbleOtherBackground,
                  textColor: tokens.bubbleOtherText,
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Dynamic Avatar Gradient Preview
          _DiagnosticCard(
            title: '无头像动态渐变 (Hash Initial Palette)',
            icon: Icons.account_circle_outlined,
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final name in [
                  'Alice',
                  'Bob',
                  'Charlie',
                  'David',
                  'Emma',
                  'Frank',
                  'Grace',
                  'Henry',
                  'Iris',
                  'Jack',
                ])
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: tokens.getAvatarGradient(name),
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          name[0],
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(name, style: theme.textTheme.labelSmall),
                    ],
                  ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // UI Components Showcase in Current Theme
          _DiagnosticCard(
            title: '常用组件当前主题效果',
            icon: Icons.widgets_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () {},
                        child: const Text('FilledButton'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {},
                        child: const Text('OutlinedButton'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Inputs
                TextField(
                  controller: _sampleTextController,
                  decoration: const InputDecoration(
                    labelText: '输入框测试',
                    prefixIcon: Icon(Icons.edit_outlined),
                  ),
                ),
                const SizedBox(height: 12),

                // Toggles
                Row(
                  children: [
                    const Text('Switch:'),
                    Switch(
                      value: _switchValue,
                      onChanged: (val) => setState(() => _switchValue = val),
                    ),
                    const Spacer(),
                    const Text('Checkbox:'),
                    Checkbox(
                      value: _checkboxValue,
                      onChanged:
                          (val) =>
                              setState(() => _checkboxValue = val ?? false),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Slider & Progress
                Row(
                  children: [
                    const Text('Slider:'),
                    Expanded(
                      child: Slider(
                        value: _sliderValue,
                        onChanged: (val) => setState(() => _sliderValue = val),
                      ),
                    ),
                    Text('${(_sliderValue * 100).toInt()}%'),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: _sliderValue),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Glassmorphism & Frosted Glass Showcase
          _DiagnosticCard(
            title: '现代 IM 毛玻璃与高斯模糊效果 (Glassmorphism)',
            icon: Icons.blur_on_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '实时调节高斯模糊半径 (Sigma) 与表面透明度，测试不同背景下的光影折射与镜面边框质感。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      '模糊强度 (Sigma: ${_glassBlurSigma.toStringAsFixed(1)}):',
                      style: theme.textTheme.labelMedium,
                    ),
                    Expanded(
                      child: Slider(
                        value: _glassBlurSigma,
                        min: 0,
                        max: 40,
                        divisions: 40,
                        onChanged:
                            (val) => setState(() => _glassBlurSigma = val),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      '表面不透明度 (${(_glassOpacity * 100).toInt()}%):',
                      style: theme.textTheme.labelMedium,
                    ),
                    Expanded(
                      child: Slider(
                        value: _glassOpacity,
                        min: 0.1,
                        max: 1.0,
                        divisions: 18,
                        onChanged: (val) => setState(() => _glassOpacity = val),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text('背景图样：'),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('炫彩光斑'),
                      selected: _glassBackgroundPattern == 0,
                      onSelected:
                          (_) => setState(() => _glassBackgroundPattern = 0),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('几何波浪'),
                      selected: _glassBackgroundPattern == 1,
                      onSelected:
                          (_) => setState(() => _glassBackgroundPattern = 1),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('聊天背景'),
                      selected: _glassBackgroundPattern == 2,
                      onSelected:
                          (_) => setState(() => _glassBackgroundPattern = 2),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Live Frosted Glass Container with Interactive Content
                Container(
                  width: double.infinity,
                  height: 280,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient:
                        _glassBackgroundPattern == 0
                            ? const LinearGradient(
                              colors: [
                                Color(0xFF3B82F6),
                                Color(0xFF8B5CF6),
                                Color(0xFFEC4899),
                                Color(0xFFF59E0B),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                            : _glassBackgroundPattern == 1
                            ? const RadialGradient(
                              colors: [
                                Color(0xFF10B981),
                                Color(0xFF06B6D4),
                                Color(0xFF3B82F6),
                                Color(0xFF1E1B4B),
                              ],
                              radius: 1.2,
                            )
                            : const LinearGradient(
                              colors: [
                                Color(0xFF0F172A),
                                Color(0xFF1E293B),
                                Color(0xFF334155),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                  ),
                  child: Stack(
                    children: [
                      // Decorative background shapes
                      Positioned(
                        top: 20,
                        left: 30,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.amberAccent,
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 30,
                        right: 40,
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.cyanAccent,
                          ),
                        ),
                      ),

                      // Floating Glass Cards over Colorful Pattern
                      Center(
                        child: GlassContainer(
                          width: 320,
                          blurSigma: _glassBlurSigma,
                          backgroundColor: (theme.brightness == Brightness.dark
                                  ? const Color(0xFF0F172A)
                                  : Colors.white)
                              .withValues(alpha: _glassOpacity),
                          borderColor: Colors.white.withValues(
                            alpha:
                                theme.brightness == Brightness.dark
                                    ? 0.25
                                    : 0.6,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          padding: const EdgeInsets.all(18),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  const ChatObjectAvatar(
                                    name: 'Alice Glass',
                                    imageUrl: null,
                                    radius: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '现代毛玻璃卡片',
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                        Text(
                                          '高透气泡 · 镜面反光边框',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color:
                                                    colorScheme
                                                        .onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: tokens.mentionBadgeColor,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      '@IM',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton.tonal(
                                      onPressed: () {},
                                      child: const Text('玻璃按键'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () {},
                                      child: const Text('高斯模糊'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticCard extends StatelessWidget {
  const _DiagnosticCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}

class _ColorChip extends StatelessWidget {
  const _ColorChip({
    required this.label,
    required this.color,
    required this.textColor,
  });

  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final hex =
        '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.grey.withValues(alpha: 0.2),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            hex,
            style: TextStyle(
              color: textColor.withValues(alpha: 0.8),
              fontSize: 9,
              fontFamily: 'monospace',
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
    final colorScheme = Theme.of(context).colorScheme;

    return Chip(
      avatar: Icon(
        supported ? Icons.check_circle : Icons.cancel,
        size: 16,
        color: supported ? colorScheme.primary : colorScheme.error,
      ),
      label: Text(platform),
      visualDensity: VisualDensity.compact,
    );
  }
}
