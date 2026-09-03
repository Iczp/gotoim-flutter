import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_toast.dart';
import 'glass_container.dart';

/// 统一单元格分组组件
///
/// 视觉与层次规范参考 `MinePage` 的 `_SectionHeader` 与 `GlassCard`。
class CellGroup extends StatelessWidget {
  const CellGroup({
    super.key,
    this.title,
    this.titleWidget,
    this.children,
    this.child,
    this.margin = const EdgeInsets.only(bottom: 12),
    this.padding = EdgeInsets.zero,
    this.borderRadius,
    this.useGlass = true,
    this.backgroundColor,
    this.borderColor,
    this.dividerIndent = 16.0,
  }) : assert(
         children != null || child != null,
         'Either children or child must be provided to CellGroup.',
       );

  /// 分组标题（渲染样式与 `MinePage._SectionHeader` 保持一致）
  final String? title;

  /// 自定义分组标题组件
  final Widget? titleWidget;

  /// 子项列表（内部自动在相邻项间插入微弱分隔线）
  final List<Widget>? children;

  /// 自定义单一子组件（与 [children] 二选一）
  final Widget? child;

  /// 外边距，默认 `const EdgeInsets.only(bottom: 12)`
  final EdgeInsetsGeometry margin;

  /// 内边距，默认 `EdgeInsets.zero`
  final EdgeInsetsGeometry padding;

  /// 圆角，默认 16
  final BorderRadiusGeometry? borderRadius;

  /// 是否使用毛玻璃卡片材质，默认 true
  final bool useGlass;

  /// 背景色覆盖
  final Color? backgroundColor;

  /// 边框颜色覆盖
  final Color? borderColor;

  /// 分隔线缩进，默认 16.0
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final effectiveRadius = borderRadius ?? BorderRadius.circular(16);

    final Widget? header = titleWidget ??
        (title != null
            ? Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Text(
                  title!,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : null);

    Widget content;
    if (child != null) {
      content = child!;
    } else {
      final items = children!;
      final separated = <Widget>[];
      for (var i = 0; i < items.length; i++) {
        if (i > 0) {
          separated.add(
            Divider(
              height: 1,
              indent: dividerIndent,
              color: theme.dividerColor.withValues(alpha: 0.15),
            ),
          );
        }
        separated.add(items[i]);
      }
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: separated,
      );
    }

    final Widget card = useGlass
        ? GlassCard(
            margin: EdgeInsets.zero,
            padding: padding,
            borderRadius: effectiveRadius,
            backgroundColor: backgroundColor,
            borderColor: borderColor,
            child: content,
          )
        : Material(
            color: backgroundColor ?? theme.colorScheme.surface,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: effectiveRadius,
              side: BorderSide(
                color: borderColor ?? theme.dividerColor.withValues(alpha: 0.2),
              ),
            ),
            child: Padding(
              padding: padding,
              child: content,
            ),
          );

    return Padding(
      padding: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (header != null) header,
          card,
        ],
      ),
    );
  }
}

/// 统一单元格项组件
///
/// 支持左侧图标、标题、副标题、右侧文本、自定义尾部、一键复制与右箭头导航指示。
class Cell extends StatelessWidget {
  const Cell({
    super.key,
    required this.title,
    this.value,
    this.valueWidget,
    this.subtitle,
    this.subtitleWidget,
    this.icon,
    this.trailing,
    this.showArrow = false,
    this.canCopy = false,
    this.copyValue,
    this.onTap,
    this.titleColor,
    this.subtitleColor,
    this.subTitleColor,
    this.arrowColor,
    this.isCentered = false,
    this.disabled = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  });

  /// 单元格标题
  final String title;

  /// 右侧值文本
  final String? value;

  /// 右侧自定义组件（徽标、胶囊标签等）
  final Widget? valueWidget;

  /// 副标题辅助文案
  final String? subtitle;

  /// 自定义副标题组件
  final Widget? subtitleWidget;

  /// 左侧图标或前缀组件
  final Widget? icon;

  /// 自定义尾部组件（存在时替换 value、valueWidget 和 arrow）
  final Widget? trailing;

  /// 是否显示右侧箭头指示器
  final bool showArrow;

  /// 点击是否复制值到剪贴板
  final bool canCopy;

  /// 复制的内容（为空时使用 value 或 title）
  final String? copyValue;

  /// 点击回调
  final VoidCallback? onTap;

  /// 标题颜色（可用于危险/退出操作标红）
  final Color? titleColor;

  /// 副标题文字颜色（默认透明度 0.5）
  final Color? subtitleColor;

  /// 副标题文字颜色别名
  final Color? subTitleColor;

  /// 右侧箭头颜色（默认透明度 0.5）
  final Color? arrowColor;

  /// 标题是否居中显示
  final bool isCentered;

  /// 是否置灰禁用
  final bool disabled;

  /// 单元格内边距
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveSubtitleColor = subTitleColor ??
        subtitleColor ??
        theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
    final effectiveArrowColor = arrowColor ??
        theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5);

    final effectiveOnTap = onTap ??
        (canCopy && (value != null || copyValue != null)
            ? () {
                final text = copyValue ?? value!;
                Clipboard.setData(ClipboardData(text: text));
                showToast('已复制 $title', type: ToastType.info);
              }
            : null);

    Widget content;
    if (isCentered) {
      content = Center(
        child: Text(
          title,
          style: TextStyle(
            color: titleColor ?? theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      );
    } else {
      final hasValue =
          valueWidget != null || (value != null && value!.isNotEmpty);
      final hasRightContent = trailing != null || hasValue || showArrow;

      final Widget leftTitleColumn = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: titleColor ??
                  (disabled
                      ? theme.disabledColor
                      : theme.colorScheme.onSurface),
            ),
          ),
          if (subtitleWidget != null) ...[
            const SizedBox(height: 2),
            subtitleWidget!,
          ] else if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 12,
                color: effectiveSubtitleColor,
              ),
            ),
          ],
        ],
      );

      final Widget leftContent = Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            icon!,
            const SizedBox(width: 12),
          ],
          Flexible(
            fit: hasValue ? FlexFit.loose : FlexFit.tight,
            child: leftTitleColumn,
          ),
        ],
      );

      if (!hasRightContent) {
        content = leftContent;
      } else if (trailing != null) {
        content = Row(
          children: [
            Expanded(child: leftContent),
            const SizedBox(width: 12),
            trailing!,
          ],
        );
      } else if (!hasValue && showArrow) {
        content = Row(
          children: [
            Expanded(child: leftContent),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: effectiveArrowColor,
            ),
          ],
        );
      } else {
        content = LayoutBuilder(
          builder: (context, constraints) {
            return Row(
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * 0.45,
                  ),
                  child: leftContent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: valueWidget ??
                              Text(
                                value!,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                              ),
                        ),
                        if (showArrow) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: effectiveArrowColor,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      }
    }

    return InkWell(
      onTap: disabled ? null : effectiveOnTap,
      child: Padding(
        padding: padding,
        child: content,
      ),
    );
  }
}
