import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 桌面端统一模态弹窗外壳 (DesktopModalDialog)
///
/// 遵循桌面端 IM（如微信/Telegram）弹窗设计规范：
/// - 宽度适中（默认 480~520dp），高度自适应内容并设置最大高度约束；
/// - 圆角 12dp，极细边框，微质感阴影；
/// - 顶部包含桌面端原生质感标题栏与关闭按钮（X）；
/// - 支持按 ESC 键快速关闭；
/// - 背景使用半透明遮罩 (Dark Translucent Barrier)；
/// - 支持自定义标题栏前缀与操作项。
class DesktopModalDialog extends StatelessWidget {
  const DesktopModalDialog({
    required this.child,
    this.title,
    this.subtitle,
    this.titleLeading,
    this.titleActions,
    this.width = 500,
    this.height,
    this.maxHeightFactor = 0.85,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.padding = EdgeInsets.zero,
    this.showCloseButton = true,
    this.onClose,
    super.key,
  });

  /// 弹窗主内容区
  final Widget child;

  /// 标题文字
  final String? title;

  /// 副标题文字（可选）
  final String? subtitle;

  /// 标题栏左侧前缀图标/组件
  final Widget? titleLeading;

  /// 标题栏右侧自定义操作按钮组
  final List<Widget>? titleActions;

  /// 弹窗宽度（默认 500）
  final double width;

  /// 固定高度（为空则根据内容自适应）
  final double? height;

  /// 最大高度比例（相对于屏幕高度，默认 0.85）
  final double maxHeightFactor;

  /// 弹窗圆角
  final BorderRadius borderRadius;

  /// 内容区内边距
  final EdgeInsets padding;

  /// 是否显示右上角关闭按钮
  final bool showCloseButton;

  /// 关闭回调（为空则默认 Navigator.pop）
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final screenSize = MediaQuery.of(context).size;

    final dialogWidth = width.clamp(320.0, screenSize.width - 48);
    final maxHeight = screenSize.height * maxHeightFactor;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          if (onClose != null) {
            onClose!();
          } else {
            Navigator.of(context).maybePop();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: dialogWidth,
            height: height,
            constraints: BoxConstraints(
              maxHeight: maxHeight,
              maxWidth: dialogWidth,
            ),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: borderRadius,
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.10)
                    : colorScheme.outlineVariant.withValues(alpha: 0.45),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.16),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: height == null ? MainAxisSize.min : MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── 桌面标题栏 ──
                if (title != null || showCloseButton)
                  _buildHeader(context, colorScheme, isDark),

                // ── 内容主体 ──
                if (height != null)
                  Expanded(
                    child: Padding(
                      padding: padding,
                      child: child,
                    ),
                  )
                else
                  Flexible(
                    child: Padding(
                      padding: padding,
                      child: child,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.25)
            : colorScheme.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          if (titleLeading != null) ...[
            titleLeading!,
            const SizedBox(width: 8),
          ],
          if (title != null)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title!,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            )
          else
            const Spacer(),
          if (titleActions != null) ...titleActions!,
          if (showCloseButton) ...[
            const SizedBox(width: 4),
            _DesktopCloseButton(
              onPressed: () {
                if (onClose != null) {
                  onClose!();
                } else {
                  Navigator.of(context).maybePop();
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// 桌面端关闭小图标（带悬浮圆角背景过渡）
class _DesktopCloseButton extends StatefulWidget {
  const _DesktopCloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_DesktopCloseButton> createState() => _DesktopCloseButtonState();
}

class _DesktopCloseButtonState extends State<_DesktopCloseButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: _isHovered
                ? (isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.08))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            Icons.close_rounded,
            size: 17,
            color: _isHovered
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 弹出桌面端居中模态对话框
Future<T?> showDesktopModalDialog<T>({
  required BuildContext context,
  required Widget child,
  String? title,
  String? subtitle,
  Widget? titleLeading,
  List<Widget>? titleActions,
  double width = 500,
  double? height,
  double maxHeightFactor = 0.85,
  BorderRadius borderRadius = const BorderRadius.all(Radius.circular(12)),
  EdgeInsets padding = EdgeInsets.zero,
  bool barrierDismissible = true,
  bool showCloseButton = true,
  VoidCallback? onClose,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (dialogContext) => DesktopModalDialog(
      title: title,
      subtitle: subtitle,
      titleLeading: titleLeading,
      titleActions: titleActions,
      width: width,
      height: height,
      maxHeightFactor: maxHeightFactor,
      borderRadius: borderRadius,
      padding: padding,
      showCloseButton: showCloseButton,
      onClose: onClose,
      child: child,
    ),
  );
}
