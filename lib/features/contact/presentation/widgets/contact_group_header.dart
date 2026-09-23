import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme_tokens.dart';
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
    isPinned: false,
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
    this.isPinned = false,
    super.key,
  });

  final ContactGroup group;
  final String activeInitial;
  final ValueListenable<String>? activeInitialListenable;
  final ValueChanged<String> onSurnameSelected;
  final bool showBlur;
  final bool isPinned;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = context.appTokens;
    final effectiveIsPinned = isPinned || showBlur;

    final content = SizedBox(
      height: ContactsPageMetrics.groupHeaderExtent,
      child: Padding(
        padding: EdgeInsets.only(left: tokens.pagePaddingHorizontal),
        child: Row(
          children: <Widget>[
            // 组名大写首字母（如 A、B、C）
            Text(
              group.index,
              style: TextStyle(
                fontSize: 15.0,
                fontWeight: FontWeight.w700,
                color: colors.primary,
                height: 1.0,
              ),
            ),
            const SizedBox(width: 4),
            // 该组联系人总数
            Text(
              '(${group.count})',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: colors.onSurfaceVariant.withValues(alpha: 0.65),
                height: 1.0,
              ),
            ),
            // 垂直分割微线
            Container(
              height: 11,
              width: tokens.dividerThickness,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: colors.outlineVariant.withValues(alpha: 0.6),
            ),
            // 横向拼音/姓氏筛选条
            ContactSurnameInitialBar(
              group: group,
              activeInitial: activeInitial,
              activeInitialListenable: activeInitialListenable,
              onSelected: onSurnameSelected,
            ),
          ],
        ),
      ),
    );

    if (effectiveIsPinned) {
      // 吸顶状态：采用与顶部毛玻璃标题栏同源的材质与分割线，浑然一体
      return ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: tokens.glassBlurSigma,
            sigmaY: tokens.glassBlurSigma,
          ),
          child: Container(
            height: ContactsPageMetrics.groupHeaderExtent,
            decoration: BoxDecoration(
              color: tokens.glassSurfaceColor,
              border: Border(
                bottom: BorderSide(
                  color: tokens.glassBorderColor,
                  width: tokens.dividerThickness,
                ),
              ),
            ),
            child: content,
          ),
        ),
      );
    }

    // 列表内部普通流状态：轻量自然背景
    return Container(
      height: ContactsPageMetrics.groupHeaderExtent,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.25),
            width: tokens.dividerThickness,
          ),
        ),
      ),
      child: content,
    );
  }
}
