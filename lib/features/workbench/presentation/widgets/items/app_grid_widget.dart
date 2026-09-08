import 'package:flutter/material.dart';
import '../../../domain/workbench_grid_item.dart';

/// Renders a $1 \times 1$ App shortcut item on the workbench grid.
class AppGridWidget extends StatelessWidget {
  const AppGridWidget({
    required this.item,
    required this.onTap,
    this.onLongPress,
    this.onDelete,
    this.isEditing = false,
    super.key,
  });

  final WorkbenchGridItem item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDelete;
  final bool isEditing;

  IconData _getIconData(String? iconName) {
    switch (iconName) {
      case 'business':
        return Icons.business_center_outlined;
      case 'verified_user':
        return Icons.verified_user_outlined;
      case 'calendar_today':
        return Icons.calendar_month_outlined;
      case 'cloud_queue':
        return Icons.cloud_queue_outlined;
      case 'edit_note':
        return Icons.edit_note_outlined;
      case 'qr_code_scanner':
        return Icons.qr_code_scanner;
      case 'check_circle_outline':
        return Icons.check_circle_outline;
      case 'email':
        return Icons.email_outlined;
      case 'people':
        return Icons.groups_outlined;
      case 'fingerprint':
        return Icons.fingerprint;
      default:
        return Icons.apps_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final extra = item.extra ?? const {};
    final iconName = extra['icon'] as String?;
    final colorInt = extra['color'] as int?;
    final badge = item.badge ?? (extra['badge'] as String?);
    final subtitle = item.subtitle ?? (extra['subtitle'] as String?);

    final primaryColor = colorInt != null ? Color(colorInt) : colorScheme.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  // App Icon Container
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          primaryColor.withValues(alpha: 0.18),
                          primaryColor.withValues(alpha: 0.08),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: primaryColor.withValues(alpha: 0.25),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withValues(alpha: 0.12),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: iconName != null
                          ? Icon(
                              _getIconData(iconName),
                              size: 26,
                              color: primaryColor,
                            )
                          : Text(
                              item.title.isNotEmpty
                                  ? item.title[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: primaryColor,
                              ),
                            ),
                    ),
                  ),

                  // Notification Badge
                  if (badge != null && !isEditing)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.error,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.error.withValues(alpha: 0.4),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                            color: colorScheme.onError,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                  // Edit mode: delete badge
                  if (isEditing && onDelete != null)
                    Positioned(
                      top: -6,
                      left: -6,
                      child: GestureDetector(
                        onTap: onDelete,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: colorScheme.error,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: colorScheme.shadow.withValues(alpha: 0.2),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.remove,
                            size: 14,
                            color: colorScheme.onError,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 5),
              // Line 1: Main Title
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 11.5,
                  letterSpacing: -0.2,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 2),
              // Line 2: Subtitle (shown if available)
              if (subtitle != null && subtitle.isNotEmpty)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 9.5,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
                    letterSpacing: -0.2,
                    height: 1.1,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
