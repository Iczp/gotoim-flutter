import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Renders tweet-like text highlighting #hashtags, @mentions and URL links.
class SocialRichText extends StatelessWidget {
  const SocialRichText({
    super.key,
    required this.text,
    this.style,
    this.onHashtagTap,
    this.onMentionTap,
    this.onUrlTap,
  });

  final String text;
  final TextStyle? style;
  final void Function(String tag)? onHashtagTap;
  final void Function(String handle)? onMentionTap;
  final void Function(String url)? onUrlTap;

  static final _pattern = RegExp(
    r'(https?:\/\/[^\s]+)|(#[^\s#]+)|(@[a-zA-Z0-9_]+)',
  );

  @override
  Widget build(BuildContext context) {
    final defaultStyle =
        style ?? Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    final linkColor =
        Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1D9BF0)
            : const Color(0xFF1D9BF0);

    final linkStyle = defaultStyle.copyWith(
      color: linkColor,
      fontWeight: FontWeight.w500,
    );

    final spans = <InlineSpan>[];
    int lastMatchEnd = 0;

    for (final match in _pattern.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        spans.add(
          TextSpan(
            text: text.substring(lastMatchEnd, match.start),
            style: defaultStyle,
          ),
        );
      }

      final matchText = match.group(0)!;
      if (match.group(1) != null) {
        // URL
        spans.add(
          TextSpan(
            text: matchText,
            style: linkStyle,
            recognizer:
                onUrlTap == null
                    ? null
                    : (TapGestureRecognizer()
                      ..onTap = () => onUrlTap!(matchText)),
          ),
        );
      } else if (match.group(2) != null) {
        // #Hashtag
        spans.add(
          TextSpan(
            text: matchText,
            style: linkStyle,
            recognizer:
                onHashtagTap == null
                    ? null
                    : (TapGestureRecognizer()
                      ..onTap = () => onHashtagTap!(matchText)),
          ),
        );
      } else if (match.group(3) != null) {
        // @Mention
        spans.add(
          TextSpan(
            text: matchText,
            style: linkStyle,
            recognizer:
                onMentionTap == null
                    ? null
                    : (TapGestureRecognizer()
                      ..onTap = () => onMentionTap!(matchText)),
          ),
        );
      }
      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(
        TextSpan(text: text.substring(lastMatchEnd), style: defaultStyle),
      );
    }

    return Text.rich(TextSpan(children: spans), style: defaultStyle);
  }
}
