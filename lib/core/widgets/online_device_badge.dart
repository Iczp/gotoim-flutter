import 'package:flutter/material.dart';

/// Online-state marker displayed at the lower-right edge of a friend's avatar.
class OnlineDeviceBadge extends StatelessWidget {
  const OnlineDeviceBadge({required this.deviceTypes, super.key});

  final List<String> deviceTypes;

  @override
  Widget build(BuildContext context) {
    final type = deviceTypes.first.toLowerCase();
    final icon =
        type.contains('phone') || type.contains('mobile')
            ? Icons.smartphone_rounded
            : type.contains('web')
            ? Icons.language_rounded
            : Icons.desktop_windows_rounded;
    return Transform.rotate(
      angle: .785398,
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).colorScheme.surface,
            width: 2,
          ),
        ),
        child: Transform.rotate(
          angle: -.785398,
          child: Icon(icon, size: 10, color: Colors.white),
        ),
      ),
    );
  }
}
