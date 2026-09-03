import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/font_scale_controller.dart';
import '../../../core/theme/overscroll_style_controller.dart';
import '../../../core/theme/tab_glass_controller.dart';
import '../../../core/theme/theme_mode_controller.dart';
import '../../../core/widgets/cell_group.dart';
import '../../../core/widgets/glass_container.dart';

/// 外观与主题（含字体大小、动效与毛玻璃）独立配置页面
class ThemeSettingsPage extends ConsumerWidget {
  const ThemeSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final themeMode = ref.watch(themeModeProvider);
    final fontScale = ref.watch(fontScaleProvider);
    final overscrollStyle = ref.watch(overscrollStyleProvider);
    final currentLevel = FontScaleLevel.fromScale(fontScale);
    final levelIndex = FontScaleLevel.values.indexOf(currentLevel);

    return Scaffold(
      appBar: AppBar(
        title: const Text('外观与主题'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // ── 1. 实时预览卡片 ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '实时效果预览',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          GlassCard(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: colorScheme.primary,
                      child: const Text(
                        'IM',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Goto IM 架构助理',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '刚刚 · 在线',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '字号: ${currentLevel.label}',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '你好！欢迎使用 Goto IM。当前主题与字号设置将实时作用于整个应用的所有会话、消息列表与设置界面。',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── 2. 主题模式 ──────────────────────────────────────────────
          CellGroup(
            title: '主题模式',
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      themeMode == ThemeMode.dark
                          ? Icons.dark_mode_rounded
                          : themeMode == ThemeMode.light
                          ? Icons.light_mode_rounded
                          : Icons.brightness_auto_rounded,
                      size: 20,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '色彩模式',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
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
                      label: Text('浅色'),
                    ),
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode_outlined),
                      label: Text('深色'),
                    ),
                  ],
                  selected: {themeMode},
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

          // ── 3. 字体大小调节 ──────────────────────────────────────────
          CellGroup(
            title: '字体大小',
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.format_size_rounded,
                          size: 20,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '字号大小 (${currentLevel.label})',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    if (currentLevel != FontScaleLevel.standard)
                      TextButton(
                        onPressed: () {
                          ref.read(fontScaleControllerProvider.notifier).reset();
                        },
                        child: const Text('恢复默认'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '拖动下方滑块调节全局文字大小。设置为“标准”为系统基准比例。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Text('A', style: TextStyle(fontSize: 13)),
                    Expanded(
                      child: Slider(
                        value: levelIndex.toDouble().clamp(0.0, 4.0),
                        min: 0,
                        max: 4,
                        divisions: 4,
                        label: currentLevel.label,
                        onChanged: (val) {
                          final idx = val.round().clamp(0, 4);
                          final targetLevel = FontScaleLevel.values[idx];
                          ref
                              .read(fontScaleControllerProvider.notifier)
                              .setLevel(targetLevel);
                        },
                      ),
                    ),
                    const Text(
                      'A',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: FontScaleLevel.values.map((level) {
                      final isSelected = level == currentLevel;
                      return GestureDetector(
                        onTap: () {
                          ref
                              .read(fontScaleControllerProvider.notifier)
                              .setLevel(level);
                        },
                        child: Text(
                          level.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant.withValues(
                                    alpha: 0.6,
                                  ),
                          ),
                        ),
                      );
                    }).toList(growable: false),
                  ),
                ),
              ],
            ),
          ),

          // ── 4. 动效与交互 ──────────────────────────────────────────
          CellGroup(
            title: '动效与视觉细节',
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '列表过界效果',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '可选择 iOS 式边缘回弹或 Android 式拉伸过界效果。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<OverscrollStyle>(
                  segments: OverscrollStyle.values
                      .map(
                        (style) => ButtonSegment<OverscrollStyle>(
                          value: style,
                          label: Text(style.label),
                        ),
                      )
                      .toList(growable: false),
                  selected: {overscrollStyle},
                  onSelectionChanged: (selected) {
                    if (selected.isNotEmpty) {
                      ref
                          .read(overscrollStyleControllerProvider.notifier)
                          .setStyle(selected.first);
                    }
                  },
                ),
                const SizedBox(height: 14),
                const Divider(height: 1),
                Cell(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  icon: const Icon(Icons.blur_on_rounded),
                  title: '底部导航毛玻璃效果',
                  subtitle: '开启后底部导航栏具备高斯模糊与半透明层次感',
                  switchValue: ref.watch(tabGlassProvider),
                  onSwitchChanged: (val) {
                    ref.read(tabGlassProvider.notifier).setEnabled(val);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
