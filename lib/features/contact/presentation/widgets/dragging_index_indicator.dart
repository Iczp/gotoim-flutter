import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class DraggingIndexIndicator extends StatelessWidget {
  const DraggingIndexIndicator({
    required this.draggingIndexListenable,
    super.key,
  });

  final ValueListenable<String?> draggingIndexListenable;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<String?>(
        valueListenable: draggingIndexListenable,
        builder: (context, key, _) {
          if (key == null) return const SizedBox.shrink();
          return IgnorePointer(
            child: Center(
              child: Container(
                width: 80,
                height: 80,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .58),
                  shape: BoxShape.circle,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: .52),
                      blurRadius: 24,
                      spreadRadius: 5,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .36),
                      blurRadius: 14,
                    ),
                  ],
                ),
                child: Text(
                  key,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          );
        },
      );
}
