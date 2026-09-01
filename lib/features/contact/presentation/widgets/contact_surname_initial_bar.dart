import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/models/contact_group.dart';

class ContactSurnameInitialBar extends StatefulWidget {
  const ContactSurnameInitialBar({
    required this.group,
    required this.activeInitial,
    required this.activeInitialListenable,
    required this.onSelected,
    super.key,
  });

  final ContactGroup group;
  final String activeInitial;
  final ValueListenable<String>? activeInitialListenable;
  final ValueChanged<String> onSelected;

  @override
  State<ContactSurnameInitialBar> createState() =>
      _ContactSurnameInitialBarState();
}

class _ContactSurnameInitialBarState extends State<ContactSurnameInitialBar> {
  final ScrollController _scrollController = ScrollController();
  late Map<String, GlobalKey> _initialKeys = _createInitialKeys();
  late String _currentInitial = widget.activeInitial;

  Map<String, GlobalKey> _createInitialKeys() => <String, GlobalKey>{
    for (final initial in widget.group.surnameInitials) initial: GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    widget.activeInitialListenable?.addListener(_onActiveInitialChanged);
  }

  @override
  void didUpdateWidget(covariant ContactSurnameInitialBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeInitialListenable != widget.activeInitialListenable) {
      oldWidget.activeInitialListenable?.removeListener(
        _onActiveInitialChanged,
      );
      widget.activeInitialListenable?.addListener(_onActiveInitialChanged);
    }
    if (oldWidget.group != widget.group) {
      _initialKeys = _createInitialKeys();
      _currentInitial = widget.activeInitial;
    }
  }

  @override
  void dispose() {
    widget.activeInitialListenable?.removeListener(_onActiveInitialChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onActiveInitialChanged() {
    final nextInitial = widget.activeInitialListenable!.value;
    if (nextInitial == _currentInitial || !mounted) return;
    setState(() => _currentInitial = nextInitial);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final targetContext = _initialKeys[nextInitial]?.currentContext;
      if (mounted && targetContext != null) {
        Scrollable.ensureVisible(
          targetContext,
          alignment: .5,
          duration: Duration.zero,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(right: 42),
        child: Row(
          children: widget.group.surnameInitials
              .expand<Widget>((initial) sync* {
                yield KeyedSubtree(
                  key: _initialKeys[initial],
                  child: _buildButton(
                    initial,
                    initial == _currentInitial,
                    colors,
                  ),
                );
                if (initial != widget.group.surnameInitials.last) {
                  yield const Text('、');
                }
              })
              .toList(growable: false),
        ),
      ),
    );
  }

  Widget _buildButton(String initial, bool isActive, ColorScheme colors) =>
      TextButton(
        onPressed: () => widget.onSelected(initial),
        style: TextButton.styleFrom(
          foregroundColor: isActive ? colors.primary : colors.onSurfaceVariant,
          minimumSize: const Size(28, 32),
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
        child: Text(initial),
      );
}
