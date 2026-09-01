import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/models/contact_group.dart';
import 'contact_surname_initial_bar.dart';
import 'contacts_page_chrome.dart';

class PinnedContactGroup {
  const PinnedContactGroup({required this.group});

  final ContactGroup group;
}

class ContactGroupHeaderDelegate extends SliverPersistentHeaderDelegate {
  ContactGroupHeaderDelegate({
    required this.group,
    required this.activeInitial,
    required this.onSurnameSelected,
  });

  final ContactGroup group;
  final ValueListenable<String> activeInitial;
  final ValueChanged<String> onSurnameSelected;

  @override
  double get minExtent => ContactsPageMetrics.groupHeaderExtent;
  @override
  double get maxExtent => ContactsPageMetrics.groupHeaderExtent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => ContactGroupHeader(
    group: group,
    activeInitial: activeInitial.value,
    onSurnameSelected: onSurnameSelected,
    showBlur: false,
  );

  @override
  bool shouldRebuild(covariant ContactGroupHeaderDelegate oldDelegate) =>
      group != oldDelegate.group || activeInitial != oldDelegate.activeInitial;
}

class ContactGroupHeader extends StatelessWidget {
  const ContactGroupHeader({
    required this.group,
    required this.activeInitial,
    required this.onSurnameSelected,
    this.activeInitialListenable,
    this.showBlur = true,
    super.key,
  });

  final ContactGroup group;
  final String activeInitial;
  final ValueListenable<String>? activeInitialListenable;
  final ValueChanged<String> onSurnameSelected;
  final bool showBlur;

  @override
  Widget build(BuildContext context) {
    final header = Material(
      color: contactHeaderBackground(context),
      child: Row(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 4),
            child: Text(
              group.index,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            '(${group.count})',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(width: 8),
          ContactSurnameInitialBar(
            group: group,
            activeInitial: activeInitial,
            activeInitialListenable: activeInitialListenable,
            onSelected: onSurnameSelected,
          ),
        ],
      ),
    );
    return SizedBox(
      height: ContactsPageMetrics.groupHeaderExtent,
      child: showBlur
          ? ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: header,
              ),
            )
          : header,
    );
  }
}
