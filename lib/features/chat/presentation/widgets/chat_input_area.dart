import 'package:flutter/material.dart';

/// Switches the bottom region between multi-select actions and message input.
///
/// Its contents are supplied by the page because both are feature-specific,
/// stateful widgets with different lifecycles.
class ChatInputArea extends StatelessWidget {
  const ChatInputArea({
    required this.selectionMode,
    required this.selectionActions,
    required this.composer,
    super.key,
  });

  final bool selectionMode;
  final Widget selectionActions;
  final Widget composer;

  @override
  Widget build(BuildContext context) =>
      selectionMode ? selectionActions : composer;
}
