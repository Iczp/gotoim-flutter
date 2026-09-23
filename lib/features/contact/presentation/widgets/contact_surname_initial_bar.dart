import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme_tokens.dart';
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
    final tokens = context.appTokens;
    final initials = widget.group.surnameInitials;

    return Expanded(
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(right: 36),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < initials.length; i++) ...[
              KeyedSubtree(
                key: _initialKeys[initials[i]],
                child: _buildChip(
                  initial: initials[i],
                  isActive: initials[i] == _currentInitial,
                  colors: colors,
                  tokens: tokens,
                ),
              ),
              if (i < initials.length - 1) const SizedBox(width: 4),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChip({
    required String initial,
    required bool isActive,
    required ColorScheme colors,
    required AppThemeTokens tokens,
  }) {
    final bgColor = isActive
        ? colors.primaryContainer.withValues(alpha: 0.85)
        : Colors.transparent;
    final textColor = isActive ? colors.primary : colors.onSurfaceVariant;
    final borderColor = isActive
        ? colors.primary.withValues(alpha: 0.28)
        : Colors.transparent;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.onSelected(initial),
        borderRadius: BorderRadius.circular(tokens.cardRadius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(tokens.cardRadius),
            border: Border.all(
              color: borderColor,
              width: tokens.dividerThickness,
            ),
          ),
          child: Text(
            initial,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              color: textColor,
              height: 1.1,
            ),
          ),
        ),
      ),
    );
  }
}
