import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/workbench_layout_notifier.dart';
import '../../domain/workbench_grid_item.dart';
import '../../domain/workbench_layout_engine.dart';
import '../../../../core/native/native.dart';
import 'items/app_grid_widget.dart';
import 'items/banner_grid_widget.dart';
import 'items/card_grid_widget.dart';
import 'items/folder_grid_widget.dart';

/// Interactive 2D 4-column workbench grid canvas with fluid layout animations,
/// drag-and-drop reflow, and edge-to-edge widget support.
class WorkbenchCanvas extends ConsumerStatefulWidget {
  const WorkbenchCanvas({
    required this.onOpenApp,
    super.key,
  });

  final ValueChanged<WorkbenchGridItem> onOpenApp;

  @override
  ConsumerState<WorkbenchCanvas> createState() => _WorkbenchCanvasState();
}

class _WorkbenchCanvasState extends ConsumerState<WorkbenchCanvas>
    with SingleTickerProviderStateMixin {
  late AnimationController _jiggleController;

  final GlobalKey _canvasKey = GlobalKey();

  // Active drag tracking
  Offset? _dragPosition;
  String? _activeDragId;
  String? _menuItemId;
  Offset? _longPressStartPos;

  @override
  void initState() {
    super.initState();
    _jiggleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
  }

  @override
  void dispose() {
    _jiggleController.dispose();
    super.dispose();
  }

  void _syncJiggle(bool isEditing) {
    if (isEditing) {
      if (!_jiggleController.isAnimating) {
        _jiggleController.repeat(reverse: true);
      }
    } else {
      if (_jiggleController.isAnimating) {
        _jiggleController.stop();
        _jiggleController.reset();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workbenchLayoutProvider);
    final notifier = ref.read(workbenchLayoutProvider.notifier);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    _syncJiggle(state.isEditing);

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        const padding = 16.0;
        const spacing = 12.0;
        const columns = WorkbenchLayoutEngine.columns;

        final availableWidth = totalWidth - (padding * 2) - (spacing * (columns - 1));
        final cellWidth = math.max(0.0, availableWidth / columns);
        // Height proportioned for 1x1 app shortcut with icon + 2-line title/subtitle + badge
        final cellHeight = cellWidth * 1.34;

        final totalRows = notifier.engine.calculateTotalRows(state.items);
        final contentHeight =
            (padding * 2) +
            (totalRows * cellHeight) +
            (totalRows > 0 ? (totalRows - 1) * spacing : 0.0) +
            80.0; // Extra breathing room at bottom

        return SingleChildScrollView(
          physics: state.draggingItemId != null
              ? const NeverScrollableScrollPhysics()
              : const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            key: _canvasKey,
            width: totalWidth,
            height: math.max(constraints.maxHeight, contentHeight),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 1. Ghost / Target Slot Placeholder Indicator
                if (state.targetSlot != null && state.draggingItemId != null)
                  _buildPlaceholderIndicator(
                    state.targetSlot!,
                    cellWidth: cellWidth,
                    cellHeight: cellHeight,
                    padding: padding,
                    spacing: spacing,
                    totalWidth: totalWidth,
                    colorScheme: colorScheme,
                  ),

                // 2. Animated grid items
                for (final item in state.items)
                  _buildAnimatedGridItem(
                    item: item,
                    cellWidth: cellWidth,
                    cellHeight: cellHeight,
                    padding: padding,
                    spacing: spacing,
                    totalWidth: totalWidth,
                    state: state,
                    notifier: notifier,
                  ),

                // 3. Floating dragged item follower
                if (_activeDragId != null && _dragPosition != null)
                  _buildDraggingFollower(
                    itemId: _activeDragId!,
                    state: state,
                    cellWidth: cellWidth,
                    cellHeight: cellHeight,
                    spacing: spacing,
                    totalWidth: totalWidth,
                  ),

                // 4. Tap-outside dismiss barrier for context menu
                if (_menuItemId != null && _activeDragId == null)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        setState(() {
                          _menuItemId = null;
                        });
                      },
                      child: const SizedBox.expand(),
                    ),
                  ),

                // 5. Context Action Menu Popover
                if (_menuItemId != null && _activeDragId == null)
                  _buildContextMenu(
                    itemId: _menuItemId!,
                    state: state,
                    notifier: notifier,
                    cellWidth: cellWidth,
                    cellHeight: cellHeight,
                    padding: padding,
                    spacing: spacing,
                    totalWidth: totalWidth,
                    colorScheme: colorScheme,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlaceholderIndicator(
    GridRect slot, {
    required double cellWidth,
    required double cellHeight,
    required double padding,
    required double spacing,
    required double totalWidth,
    required ColorScheme colorScheme,
  }) {
    final left = padding + slot.x * (cellWidth + spacing);
    final top = padding + slot.y * (cellHeight + spacing);
    final width = slot.spanX * cellWidth + (slot.spanX - 1) * spacing;
    final height = slot.spanY * cellHeight + (slot.spanY - 1) * spacing;

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: colorScheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.6),
            width: 1.5,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedGridItem({
    required WorkbenchGridItem item,
    required double cellWidth,
    required double cellHeight,
    required double padding,
    required double spacing,
    required double totalWidth,
    required dynamic state,
    required WorkbenchLayoutNotifier notifier,
  }) {
    final isBeingDragged = item.id == state.draggingItemId;
    final isMergeTarget = item.id == state.folderMergeTargetId;

    final isEdgeToEdge = item.edgeToEdge && item.spanX == 4;

    final itemLeft = isEdgeToEdge ? 0.0 : (padding + item.x * (cellWidth + spacing));
    final itemTop = padding + item.y * (cellHeight + spacing);
    final itemWidth = isEdgeToEdge
        ? totalWidth
        : (item.spanX * cellWidth + (item.spanX - 1) * spacing);
    final itemHeight = item.spanY * cellHeight + (item.spanY - 1) * spacing;

    Widget childWidget;
    switch (item.type) {
      case WorkbenchGridItemType.app:
        childWidget = AppGridWidget(
          item: item,
          isEditing: state.isEditing,
          onTap: () {
            if (state.isEditing) return;
            widget.onOpenApp(item);
          },
          onLongPress: null,
          onDelete: () => notifier.removeItem(item.id),
        );
        break;

      case WorkbenchGridItemType.banner:
        childWidget = BannerGridWidget(
          item: item,
          isEditing: state.isEditing,
          onTap: () {
            if (state.isEditing) return;
            widget.onOpenApp(item);
          },
          onDelete: () => notifier.removeItem(item.id),
        );
        break;

      case WorkbenchGridItemType.cardWidget:
        childWidget = CardGridWidget(
          item: item,
          isEditing: state.isEditing,
          onTap: () {
            if (state.isEditing) return;
            widget.onOpenApp(item);
          },
          onDelete: () => notifier.removeItem(item.id),
        );
        break;

      case WorkbenchGridItemType.folder:
        childWidget = FolderGridWidget(
          item: item,
          isEditing: state.isEditing,
          isMergeTarget: isMergeTarget,
          onTap: () {
            if (state.isEditing) return;
            notifier.openFolderBubble(item);
          },
          onLongPress: null,
          onDelete: () => notifier.removeItem(item.id),
        );
        break;

      case WorkbenchGridItemType.custom:
        childWidget = CardGridWidget(
          item: item,
          isEditing: state.isEditing,
          onTap: () => widget.onOpenApp(item),
          onDelete: () => notifier.removeItem(item.id),
        );
        break;
    }

    // Wrap with edit jiggle animation if editing
    Widget interactiveChild = AnimatedBuilder(
      animation: _jiggleController,
      builder: (context, child) {
        if (!state.isEditing || isBeingDragged) return child!;
        final angle = ((item.id.hashCode % 3) == 0 ? 1 : -1) *
            0.02 *
            (_jiggleController.value - 0.5);
        return Transform.rotate(
          angle: angle,
          child: child,
        );
      },
      child: childWidget,
    );

    // Hold-to-drag gesture detector: press and hold shows menu; moving finger hides menu and begins dragging!
    interactiveChild = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (details) {
        // Guaranteed physical hardware vibration + system haptic feedback
        Native.vibrate(HapticFeedbackType.vibrate, 60);
        HapticFeedback.vibrate();

        setState(() {
          _menuItemId = item.id;
          _longPressStartPos = details.globalPosition;
        });
      },
      onLongPressMoveUpdate: (details) {
        // Movement threshold check: if finger moves > 8px, dismiss menu and start dragging
        if (_longPressStartPos != null) {
          final distance =
              (details.globalPosition - _longPressStartPos!).distance;
          if (distance > 8.0) {
            if (_menuItemId != null) {
              // 隐藏菜单，启动拖拽
              setState(() {
                _menuItemId = null;
                _activeDragId = item.id;
                _dragPosition = details.globalPosition;
              });

              if (!state.isEditing) {
                notifier.toggleEditMode(true);
              }
              notifier.startDragging(item.id);
            }
          }
        }

        if (_activeDragId != null) {
          setState(() {
            _dragPosition = details.globalPosition;
          });

          // Convert global pointer position into accurate canvas coordinates
          final RenderBox? canvasBox =
              _canvasKey.currentContext?.findRenderObject() as RenderBox?;
          if (canvasBox != null) {
            final local = canvasBox.globalToLocal(details.globalPosition);
            final strideX = cellWidth + spacing;
            final strideY = cellHeight + spacing;

            final width = item.edgeToEdge && item.spanX == 4
                ? totalWidth
                : (item.spanX * cellWidth + (item.spanX - 1) * spacing);
            final height = item.spanY * cellHeight + (item.spanY - 1) * spacing;

            // Find top-left grid cell corresponding to centered follower
            final itemLeft = local.dx - (width / 2);
            final itemTop = local.dy - (height / 2);

            final targetX = ((itemLeft - padding + (cellWidth * 0.5)) / strideX)
                .floor()
                .clamp(0, WorkbenchLayoutEngine.columns - item.spanX);
            final targetY = math.max(
              0,
              ((itemTop - padding + (cellHeight * 0.5)) / strideY).floor(),
            );

            notifier.updateDragHover(
              targetX: targetX,
              targetY: targetY,
            );
          }
        }
      },
      onLongPressEnd: (_) {
        _longPressStartPos = null;
        if (_activeDragId != null) {
          Native.vibrate(HapticFeedbackType.medium, 40);
          HapticFeedback.mediumImpact();
          setState(() {
            _activeDragId = null;
            _dragPosition = null;
            _menuItemId = null;
          });
          notifier.dropItem();
        }
      },
      onLongPressCancel: () {
        _longPressStartPos = null;
        if (_activeDragId != null) {
          setState(() {
            _activeDragId = null;
            _dragPosition = null;
            _menuItemId = null;
          });
          notifier.cancelDrag();
        }
      },
      child: interactiveChild,
    );

    return AnimatedPositioned(
      key: ValueKey(item.id),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      left: itemLeft,
      top: itemTop,
      width: itemWidth,
      height: itemHeight,
      child: Opacity(
        opacity: isBeingDragged ? 0.35 : 1.0,
        child: interactiveChild,
      ),
    );
  }

  Widget _buildDraggingFollower({
    required String itemId,
    required dynamic state,
    required double cellWidth,
    required double cellHeight,
    required double spacing,
    required double totalWidth,
  }) {
    final dragItem = state.draggingItem;
    if (dragItem == null) return const SizedBox.shrink();

    final RenderBox? box =
        _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || _dragPosition == null) return const SizedBox.shrink();

    final local = box.globalToLocal(_dragPosition!);

    final width = dragItem.edgeToEdge && dragItem.spanX == 4
        ? totalWidth
        : (dragItem.spanX * cellWidth + (dragItem.spanX - 1) * spacing);
    final height = dragItem.spanY * cellHeight + (dragItem.spanY - 1) * spacing;

    return Positioned(
      left: local.dx - (width / 2),
      top: local.dy - (height / 2),
      width: width,
      height: height,
      child: IgnorePointer(
        child: Transform.scale(
          scale: 1.08,
          child: Material(
            elevation: 16,
            borderRadius: BorderRadius.circular(18),
            color: Colors.transparent,
            shadowColor: Colors.black.withValues(alpha: 0.35),
            child: _buildItemPreview(dragItem),
          ),
        ),
      ),
    );
  }

  Widget _buildItemPreview(WorkbenchGridItem item) {
    switch (item.type) {
      case WorkbenchGridItemType.app:
        return AppGridWidget(item: item, onTap: () {});
      case WorkbenchGridItemType.banner:
        return BannerGridWidget(item: item, onTap: () {});
      case WorkbenchGridItemType.cardWidget:
        return CardGridWidget(item: item, onTap: () {});
      case WorkbenchGridItemType.folder:
        return FolderGridWidget(item: item, onTap: () {});
      case WorkbenchGridItemType.custom:
        return CardGridWidget(item: item, onTap: () {});
    }
  }

  Widget _buildContextMenu({
    required String itemId,
    required dynamic state,
    required WorkbenchLayoutNotifier notifier,
    required double cellWidth,
    required double cellHeight,
    required double padding,
    required double spacing,
    required double totalWidth,
    required ColorScheme colorScheme,
  }) {
    final itemIndex = state.items.indexWhere((e) => e.id == itemId);
    if (itemIndex == -1) return const SizedBox.shrink();
    final item = state.items[itemIndex] as WorkbenchGridItem;

    final isEdgeToEdge = item.edgeToEdge && item.spanX == 4;
    final itemLeft = isEdgeToEdge ? 0.0 : (padding + item.x * (cellWidth + spacing));
    final itemTop = padding + item.y * (cellHeight + spacing);
    final itemWidth = isEdgeToEdge
        ? totalWidth
        : (item.spanX * cellWidth + (item.spanX - 1) * spacing);
    final itemHeight = item.spanY * cellHeight + (item.spanY - 1) * spacing;

    const menuWidth = 190.0;
    const menuEstimatedHeight = 145.0;

    final left = (itemLeft + (itemWidth / 2) - (menuWidth / 2))
        .clamp(12.0, totalWidth - menuWidth - 12.0);
    // Show above if enough room, otherwise below
    final showAbove = itemTop > menuEstimatedHeight + 20.0;
    final top = showAbove
        ? itemTop - menuEstimatedHeight - 8.0
        : itemTop + itemHeight + 8.0;

    return Positioned(
      left: left,
      top: top,
      width: menuWidth,
      child: Material(
        elevation: 12,
        borderRadius: BorderRadius.circular(16),
        color: colorScheme.surfaceContainerHighest,
        shadowColor: Colors.black.withValues(alpha: 0.3),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.6),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header with mini title & subtitle preview
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (item.subtitle != null && item.subtitle!.isNotEmpty)
                            Text(
                              item.subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
              // Action 1: Toggle edit mode
              InkWell(
                onTap: () {
                  setState(() => _menuItemId = null);
                  HapticFeedback.lightImpact();
                  notifier.toggleEditMode();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        state.isEditing
                            ? Icons.check_circle_outline
                            : Icons.tune_rounded,
                        size: 18,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        state.isEditing ? '完成编辑' : '编辑主屏幕',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Action 2: If folder, open folder
              if (item.type == WorkbenchGridItemType.folder) ...[
                Divider(
                  height: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
                InkWell(
                  onTap: () {
                    setState(() => _menuItemId = null);
                    notifier.openFolderBubble(item);
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Icon(Icons.folder_open_outlined, size: 18),
                        SizedBox(width: 10),
                        Text(
                          '展开文件夹',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              Divider(
                height: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
              // Action 3: Remove from workbench
              InkWell(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                onTap: () {
                  setState(() => _menuItemId = null);
                  Native.vibrate(HapticFeedbackType.medium, 40);
                  HapticFeedback.mediumImpact();
                  notifier.removeItem(item.id);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline_rounded,
                        size: 18,
                        color: colorScheme.error,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '移出工作台',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.error,
                        ),
                      ),
                    ],
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
