import 'package:flutter/material.dart';

/// Two-line AppBar title showing the current page title and optional
/// session/group context subtitle for deep-routed pages.
class TwoLineAppBarTitle extends StatelessWidget {
  const TwoLineAppBarTitle({
    required this.title,
    this.subtitle,
    this.centerTitle = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final bool centerTitle;

  @override
  Widget build(BuildContext context) {
    final cleanSubtitle = subtitle?.trim();
    if (cleanSubtitle == null || cleanSubtitle.isEmpty) {
      return Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          centerTitle ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          cleanSubtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w400,
            height: 1.15,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
          ),
        ),
      ],
    );
  }
}

/// Unified WeChat-like spacing, surface colors, and button styles for
/// chat settings and deep-routed subpages.
abstract final class WeChatPageStyle {
  static const double pageHorizontalPadding = 12.0;
  static const double sectionGap = 10.0;
  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(12));

  static Color scaffoldBg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF111317)
          : const Color(0xFFF5F5F5);

  static Color cardBg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1C1F26)
          : Colors.white;

  static Color appBarBg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF15181E)
          : const Color(0xFFF5F5F5);

  static ButtonStyle primaryButtonStyle(BuildContext context) =>
      FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      );

  static ButtonStyle tonalButtonStyle(BuildContext context) =>
      FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      );
}
