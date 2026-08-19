import 'package:flutter/material.dart';

/// Prominent four-cell display for the scan-login verification state.
class VerificationCodeBoxes extends StatelessWidget {
  const VerificationCodeBoxes({
    super.key,
    required this.code,
    this.color,
    this.compact = false,
  });

  final String? code;
  final Color? color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = color ?? theme.colorScheme.primary;
    final normalized = (code ?? '').padRight(4, '—').substring(0, 4);
    final boxSize = compact ? 40.0 : 52.0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(4, (index) {
        return Padding(
          padding: EdgeInsets.only(right: index == 3 ? 0 : 10),
          child: Container(
            width: boxSize,
            height: boxSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.55)),
            ),
            child: Text(
              normalized[index],
              style: theme.textTheme.headlineSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        );
      }),
    );
  }
}
