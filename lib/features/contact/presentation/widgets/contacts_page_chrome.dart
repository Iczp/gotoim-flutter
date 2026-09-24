import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme_tokens.dart';

/// Shared visual constants for the contacts page.
abstract final class ContactsPageMetrics {
  static const rowExtent = 56.0;
  static const groupHeaderExtent = 36.0;
  static const titleBarExtent = 48.0;
  static const quickActionsExtent = rowExtent * 4;
}

Color contactHeaderBackground(BuildContext context) =>
    Theme.of(context).colorScheme.surface;

class ContactsTitleBar extends StatelessWidget {
  const ContactsTitleBar({
    this.bottom,
    this.hasError = false,
    this.isLoading = false,
    this.onRetry,
    this.onDismiss,
    super.key,
  });

  final Widget? bottom;
  final bool hasError;
  final bool isLoading;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tokens = context.appTokens;
    final topPadding = MediaQuery.paddingOf(context).top;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: tokens.glassBlurSigma,
          sigmaY: tokens.glassBlurSigma,
        ),
        child: Container(
          padding: EdgeInsets.only(top: topPadding),
          decoration: BoxDecoration(
            color: tokens.glassSurfaceColor,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                height: ContactsPageMetrics.titleBarExtent,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: tokens.pagePaddingHorizontal,
                  ),
                  child: Row(
                    children: <Widget>[
                      Text(
                        '通讯录',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (hasError || isLoading) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.only(
                            left: 6,
                            top: 2,
                            bottom: 2,
                            right: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? (isLoading
                                    ? const Color(0x333B82F6)
                                    : const Color(0x33F59E0B))
                                : (isLoading
                                    ? const Color(0x222563EB)
                                    : const Color(0x22D97706)),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isDark
                                  ? (isLoading
                                      ? const Color(0x663B82F6)
                                      : const Color(0x66F59E0B))
                                  : (isLoading
                                      ? const Color(0x552563EB)
                                      : const Color(0x55D97706)),
                              width: 0.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              if (isLoading) ...[
                                SizedBox(
                                  width: 10,
                                  height: 10,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      isDark
                                          ? const Color(0xFF60A5FA)
                                          : const Color(0xFF2563EB),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '正在重试...',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w500,
                                    color: isDark
                                        ? const Color(0xFF60A5FA)
                                        : const Color(0xFF2563EB),
                                  ),
                                ),
                              ] else ...[
                                InkWell(
                                  onTap: onRetry,
                                  borderRadius: BorderRadius.circular(6),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      Icon(
                                        Icons.sync_problem_rounded,
                                        size: 11,
                                        color: isDark
                                            ? const Color(0xFFFBBF24)
                                            : const Color(0xFFB45309),
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        '未同步·重试',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w500,
                                          color: isDark
                                              ? const Color(0xFFFBBF24)
                                              : const Color(0xFFB45309),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (onDismiss != null) ...[
                                const SizedBox(width: 2),
                                InkWell(
                                  onTap: onDismiss,
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.all(2),
                                    child: Icon(
                                      Icons.close,
                                      size: 11,
                                      color: isDark
                                          ? const Color(0x99FFFFFF)
                                          : const Color(0x88000000),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      const Spacer(),
                      IconButton(
                        tooltip: '搜索联系人',
                        onPressed: () => context.push('/search'),
                        icon: const Icon(Icons.search),
                      ),
                      IconButton(
                        tooltip: '添加好友',
                        onPressed: () => context.push('/add-friend'),
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ),
              ),
              if (bottom != null) bottom!,
            ],
          ),
        ),
      ),
    );
  }
}

class ContactsQuickActions extends StatelessWidget {
  const ContactsQuickActions({super.key});

  static const _items = <(String, IconData, Color)>[
    ('添加好友', Icons.person_add_alt_1_rounded, Color(0xfff59e0b)),
    ('附近', Icons.person_pin_circle_outlined, Color(0xff049565)),
    ('群聊', Icons.groups_rounded, Color(0xff4f90e0)),
    ('广场', Icons.star_rounded, Color(0xfff34f4f)),
  ];

  @override
  Widget build(BuildContext context) => Column(
    children: _items
        .map(
          (item) => SizedBox(
            height: ContactsPageMetrics.rowExtent,
            child: ListTile(
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: item.$3,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  item.$2,
                  color: const Color.fromRGBO(255, 255, 255, .5),
                ),
              ),
              title: Text(item.$1),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap:
                  () => ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('${item.$1}功能即将接入'))),
            ),
          ),
        )
        .toList(growable: false),
  );
}

class ContactsFloatingErrorBanner extends StatelessWidget {
  const ContactsFloatingErrorBanner({
    required this.error,
    required this.onRetry,
    this.onDismiss,
    super.key,
  });

  final Object error;
  final VoidCallback onRetry;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tokens = context.appTokens;

    final bgColor = isDark
        ? const Color(0xE678350F)
        : const Color(0xF2FEF3C7);
    final textColor = isDark
        ? const Color(0xFFFDE68A)
        : const Color(0xFF92400E);
    final borderColor = isDark
        ? const Color(0x66F59E0B)
        : const Color(0x66D97706);

    return Material(
      color: Colors.transparent,
      child: Container(
        margin: EdgeInsets.symmetric(
          horizontal: tokens.pagePaddingHorizontal,
          vertical: 4,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(tokens.cardRadius),
          border: Border.all(
            color: borderColor,
            width: tokens.dividerThickness,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.wifi_off_rounded, size: 16, color: textColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '在线更新失败，正在显示本地联系人',
                style: TextStyle(
                  fontSize: 12.0,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              onTap: onRetry,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  '重试',
                  style: TextStyle(
                    fontSize: 12.0,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
            if (onDismiss != null) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: onDismiss,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.close_rounded, size: 14, color: textColor),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class NoContacts extends StatelessWidget {
  const NoContacts({
    this.error,
    this.onRetry,
    super.key,
  });

  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isError = error != null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isError
                  ? Icons.cloud_off_rounded
                  : Icons.people_outline_rounded,
              size: 56,
              color: isError
                  ? colorScheme.error.withValues(alpha: 0.8)
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              isError ? '通讯录加载失败' : '暂无联系人',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: isError ? colorScheme.error : colorScheme.onSurface,
              ),
            ),
            if (isError) ...[
              const SizedBox(height: 6),
              Text(
                '$error',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              if (onRetry != null)
                FilledButton.tonal(
                  onPressed: onRetry,
                  child: const Text('重新加载'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class ContactsLoadingSkeleton extends StatelessWidget {
  const ContactsLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: <Widget>[
          Container(
            height: ContactsPageMetrics.groupHeaderExtent,
            color: color,
          ),
          ...List<Widget>.generate(
            7,
            (index) => SizedBox(
              height: ContactsPageMetrics.rowExtent,
              child: Row(
                children: <Widget>[
                  const SizedBox(width: 16),
                  CircleAvatar(radius: 21, backgroundColor: color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: index.isEven ? .42 : .58,
                        child: Container(height: 14, color: color),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
