import 'package:flutter/material.dart';

import '../../../core/theme/app_theme_tokens.dart';
import '../../../core/widgets/glass_container.dart';

/// Displays the current logged-in device banner in the session list.
class CurrentDeviceBar extends StatelessWidget {
  const CurrentDeviceBar({
    required this.label,
    required this.deviceCount,
    required this.isLoading,
    required this.onPressed,
    this.isConnected = true,
    super.key,
  });

  final String label;
  final int deviceCount;
  final bool isLoading;
  final bool isConnected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tokens = context.appTokens;
    final title = isConnected
        ? '当前在线：$deviceCount 台设备${label.isEmpty ? '' : ' · 本机：$label'}'
        : '服务未连接${label.isEmpty ? '' : ' · 本机：$label'}';

    return GlassContainer(
      borderRadius: BorderRadius.zero,
      backgroundColor: tokens.glassSecondarySurface,
      borderWidth: 0.6,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(
                Icons.devices_rounded,
                size: 20,
                color: isConnected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: isConnected ? null : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (isLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
