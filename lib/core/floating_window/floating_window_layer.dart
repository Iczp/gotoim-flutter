import 'package:flutter/material.dart';

import 'floating_window_manager.dart';
import 'floating_window_models.dart';
import 'floating_window_view.dart';

class FloatingWindowLayer extends StatelessWidget {
  const FloatingWindowLayer({super.key, required this.manager});
  final FloatingWindowManager manager;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: manager,
    builder: (context, _) {
      final windows = manager.entries.where((entry) => entry.visible).toList();
      if (windows.isEmpty) return const SizedBox.shrink();
      return LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            clipBehavior: Clip.none,
            children: [
              for (final entry in windows)
                _buildWindow(context, constraints.biggest, entry),
            ],
          );
        },
      );
    },
  );

  Widget _buildWindow(
    BuildContext context,
    Size screen,
    FloatingWindowEntry entry,
  ) {
    final bounds = _boundsFor(context, screen, entry.options);
    final size = bounds.clampSize(entry.size, entry.options);
    final position = bounds.clampPosition(entry.position, size);
    if (position != entry.position || size != entry.size) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (manager.contains(entry.id)) {
          manager.updateSize(entry.id, size);
          manager.updatePosition(entry.id, position);
        }
      });
    }
    return FloatingWindowView(
      key: ValueKey(entry.id),
      entry: entry.copyWith(position: position, size: size),
      manager: manager,
      bounds: bounds,
    );
  }

  FloatingWindowBounds _boundsFor(
    BuildContext context,
    Size screen,
    FloatingWindowOptions options,
  ) {
    final media = MediaQuery.of(context);
    final safe = options.avoidSafeArea ? media.viewPadding : EdgeInsets.zero;
    final keyboard = options.avoidKeyboard ? media.viewInsets.bottom : 0.0;
    final margin = options.margin;
    final left = safe.left + margin.left;
    final top = safe.top + margin.top;
    final right = screen.width - safe.right - margin.right;
    final bottom = screen.height - safe.bottom - keyboard - margin.bottom;
    return FloatingWindowBounds(Rect.fromLTRB(left, top, right, bottom));
  }
}
