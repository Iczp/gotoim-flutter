import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../platform/desktop_window_adapter.dart';
import 'desktop_window_dock_controller.dart';
import 'desktop_window_loading.dart';

/// Put this in a fixed layout pane; an existing native window covers its bounds.
class DesktopDockSlot extends ConsumerStatefulWidget {
  const DesktopDockSlot({required this.slotId, super.key});
  final String slotId;
  @override
  ConsumerState<DesktopDockSlot> createState() => _DesktopDockSlotState();
}

class _DesktopDockSlotState extends ConsumerState<DesktopDockSlot>
    with WidgetsBindingObserver {
  bool _scheduled = false;
  bool _visibleReported = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() => _schedule();
  @override
  void didUpdateWidget(covariant DesktopDockSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slotId != widget.slotId) {
      _visibleReported = false;
      unawaited(
        DesktopWindowAdapter.setDockSlotVisible(oldWidget.slotId, false),
      );
    }
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      final notifier = ref.read(desktopWindowDockProvider.notifier);
      if (box == null || !box.attached || !box.hasSize || box.size.isEmpty) {
        notifier.rejectLayout(widget.slotId);
        return;
      }
      final offset = box.localToGlobal(Offset.zero);
      final scale = View.of(context).devicePixelRatio;
      notifier.updateBounds(widget.slotId, (
        x: (offset.dx * scale).round(),
        y: (offset.dy * scale).round(),
        width: (box.size.width * scale).round(),
        height: (box.size.height * scale).round(),
      ));
      if (!_visibleReported) {
        _visibleReported = true;
        unawaited(DesktopWindowAdapter.setDockSlotVisible(widget.slotId, true));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final slot = ref.watch(
      desktopWindowDockProvider.select((state) => state[widget.slotId]),
    );
    _schedule();
    if (slot?.routeCovered == true) {
      final bytes = slot?.preview;
      return ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child:
            bytes == null
                ? const Center(child: Text('关闭弹窗后继续浏览'))
                : Image.memory(
                  bytes,
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                  errorBuilder:
                      (_, _, _) => const Center(child: Text('关闭弹窗后继续浏览')),
                ),
      );
    }
    if (slot?.status == WindowDockingStatus.docking) {
      return DesktopWindowLoading(
        message: slot?.targetId == 'tool:browser' ? '正在打开浏览器…' : '正在打开窗口…',
      );
    }
    return const SizedBox.expand();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(DesktopWindowAdapter.setDockSlotVisible(widget.slotId, false));
    super.dispose();
  }
}
