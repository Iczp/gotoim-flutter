import 'package:flutter/material.dart';
import '../../../domain/workbench_grid_item.dart';

/// Renders a Folder item on the grid with miniature icons preview.
class FolderGridWidget extends StatelessWidget {
  const FolderGridWidget({
    required this.item,
    required this.onTap,
    this.onLongPress,
    this.onDelete,
    this.isEditing = false,
    this.isMergeTarget = false,
    super.key,
  });

  final WorkbenchGridItem item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDelete;
  final bool isEditing;
  final bool isMergeTarget;

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
      default:
        return Icons.apps_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final children = item.children ?? const [];

    // Miniature preview of up to 4 items in a 2x2 grid
    final previewChildren = children.take(4).toList();

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
                  // Folder background container
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 48,
                    height: 48,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isMergeTarget
                          ? colorScheme.primaryContainer.withValues(alpha: 0.9)
                          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: isMergeTarget
                            ? colorScheme.primary
                            : colorScheme.outlineVariant.withValues(alpha: 0.5),
                        width: isMergeTarget ? 2 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isMergeTarget
                              ? colorScheme.primary.withValues(alpha: 0.3)
                              : colorScheme.shadow.withValues(alpha: 0.08),
                          blurRadius: isMergeTarget ? 10 : 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: GridView.count(
                      crossAxisCount: 2,
                      crossAxisSpacing: 3,
                      mainAxisSpacing: 3,
                      physics: const NeverScrollableScrollPhysics(),
                      children: List.generate(4, (index) {
                        if (index < previewChildren.length) {
                          final childItem = previewChildren[index];
                          final iconName = childItem.extra?['icon'] as String?;
                          final colorInt = childItem.extra?['color'] as int?;
                          final iconColor = colorInt != null
                              ? Color(colorInt)
                              : colorScheme.primary;

                          return Container(
                            decoration: BoxDecoration(
                              color: iconColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Center(
                              child: iconName != null
                                  ? Icon(
                                      _getIconData(iconName),
                                      size: 11,
                                      color: iconColor,
                                    )
                                  : Text(
                                      childItem.title.isNotEmpty
                                          ? childItem.title[0]
                                          : '?',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: iconColor,
                                      ),
                                    ),
                            ),
                          );
                        }
                        // Empty slot
                        return Container(
                          decoration: BoxDecoration(
                            color: colorScheme.surface.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
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
              const SizedBox(height: 4),
              Flexible(
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
