import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/window_service.dart';
import '../widgets/app_toast.dart';

/// Per-engine presentation state, updated by NativeSubWindowApp after native ACK.
final nativeWindowDocked = ValueNotifier<bool>(false);

class DesktopWindowDockButton extends ConsumerStatefulWidget {
  const DesktopWindowDockButton({required this.targetId, super.key});
  final String targetId;
  @override
  ConsumerState<DesktopWindowDockButton> createState() =>
      _DesktopWindowDockButtonState();
}

class _DesktopWindowDockButtonState
    extends ConsumerState<DesktopWindowDockButton> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final service = ref.watch(windowServiceProvider);
    if (!service.supportsWindowDocking) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: nativeWindowDocked,
      builder:
          (context, docked, _) => IconButton(
            icon: Icon(
              docked
                  ? Icons.open_in_new_rounded
                  : Icons.vertical_align_bottom_rounded,
              size: 17,
            ),
            tooltip: docked ? '弹出为独立窗口' : '吸附到聊天右侧',
            onPressed:
                _busy
                    ? null
                    : () async {
                      setState(() => _busy = true);
                      try {
                        if (docked) {
                          await service.undock(targetId: widget.targetId);
                        } else {
                          await service.dock(targetId: widget.targetId);
                        }
                      } catch (error) {
                        showToast('窗口切换失败：$error', type: ToastType.error);
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
          ),
    );
  }
}
