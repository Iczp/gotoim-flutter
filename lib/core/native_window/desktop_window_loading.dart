import 'package:flutter/material.dart';
import '../platform/windows/windows_window_adapter.dart';

/// Hidden engines have no regular vsync: explicitly render the latest widget
/// tree and wait for its native surface before exposing a window.
Future<void> prepareDesktopWindowFrame() async {
  final binding = WidgetsBinding.instance;
  final frame = binding.endOfFrame;
  binding.scheduleWarmUpFrame();
  await frame.timeout(const Duration(seconds: 5));
  await WindowsWindowAdapter.prepareFrame();
}

class DesktopWindowLoading extends StatelessWidget {
  const DesktopWindowLoading({
    required this.message,
    this.detail,
    this.backgroundColor,
    super.key,
  });
  final String message;
  final String? detail;
  final Color? backgroundColor;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: backgroundColor ?? Theme.of(context).colorScheme.surface,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(
              detail!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    ),
  );
}
