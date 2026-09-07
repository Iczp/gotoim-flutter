import 'dart:ui';
import 'package:flutter/material.dart';

import '../../domain/workbench_grid_item.dart';
import 'items/app_grid_widget.dart';

/// Interactive frosted-glass floating bubble modal displaying the contents of a folder.
class FolderBubbleDialog extends StatefulWidget {
  const FolderBubbleDialog({
    required this.folder,
    required this.onClose,
    required this.onLaunchApp,
    required this.onUnpackApp,
    super.key,
  });

  final WorkbenchGridItem folder;
  final VoidCallback onClose;
  final ValueChanged<WorkbenchGridItem> onLaunchApp;
  final ValueChanged<String> onUnpackApp;

  @override
  State<FolderBubbleDialog> createState() => _FolderBubbleDialogState();
}

class _FolderBubbleDialogState extends State<FolderBubbleDialog> {
  late TextEditingController _titleController;
  bool _isRenaming = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.folder.title);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final children = widget.folder.children ?? const [];

    return GestureDetector(
      onTap: widget.onClose,
      behavior: HitTestBehavior.opaque,
      child: Material(
        color: Colors.black.withValues(alpha: 0.45),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Center(
            child: GestureDetector(
              onTap: () {}, // Prevent tap through
              child: Container(
                width: 320,
                constraints: const BoxConstraints(maxHeight: 460),
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.35),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header with title and close button
                    Row(
                      children: [
                        Expanded(
                          child: _isRenaming
                              ? TextField(
                                  controller: _titleController,
                                  autofocus: true,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(vertical: 4),
                                    border: UnderlineInputBorder(),
                                  ),
                                  onSubmitted: (val) {
                                    setState(() => _isRenaming = false);
                                  },
                                )
                              : GestureDetector(
                                  onTap: () => setState(() => _isRenaming = true),
                                  child: Row(
                                    children: [
                                      Text(
                                        _titleController.text,
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Icon(
                                        Icons.edit_outlined,
                                        size: 16,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: '关闭',
                          iconSize: 20,
                          onPressed: widget.onClose,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Grid of apps inside the folder
                    Flexible(
                      child: children.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 40),
                              child: Text(
                                '文件夹为空',
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          : GridView.builder(
                              shrinkWrap: true,
                              itemCount: children.length,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 0.85,
                              ),
                              itemBuilder: (context, index) {
                                final child = children[index];
                                return Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    AppGridWidget(
                                      item: child,
                                      onTap: () {
                                        widget.onClose();
                                        widget.onLaunchApp(child);
                                      },
                                    ),
                                    Positioned(
                                      top: -2,
                                      right: 2,
                                      child: Tooltip(
                                        message: '移到桌面',
                                        child: InkWell(
                                          onTap: () =>
                                              widget.onUnpackApp(child.id),
                                          borderRadius: BorderRadius.circular(10),
                                          child: Container(
                                            padding: const EdgeInsets.all(2),
                                            decoration: BoxDecoration(
                                              color: colorScheme.primaryContainer,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              Icons.arrow_outward,
                                              size: 14,
                                              color: colorScheme.onPrimaryContainer,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
