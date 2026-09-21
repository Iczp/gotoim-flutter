import 'package:flutter/material.dart';

import '../../session/presentation/session_list_page.dart';
import '../../explore/presentation/explore_page.dart';
import '../../contact/presentation/contacts_page.dart';
import '../../workbench/presentation/workbench_page.dart';
import '../../mine/presentation/mine_page.dart';

/// Top-level section page router for the IM home shell.
class HomeSectionPage extends StatelessWidget {
  const HomeSectionPage({
    required this.section,
    required this.isCompact,
    required this.onOpenOwnerDrawer,
    super.key,
  });

  final HomeSection section;
  final bool isCompact;
  final VoidCallback onOpenOwnerDrawer;

  @override
  Widget build(BuildContext context) {
    if (section == HomeSection.messages) {
      return SessionListPage(onOpenOwnerDrawer: onOpenOwnerDrawer);
    }
    if (section == HomeSection.contacts) {
      return const ContactsPage();
    }
    if (section == HomeSection.workbench) {
      // 工作台内容直接作为 Tab 页面渲染，不再经过“打开工作台”的中转页。
      return const WorkbenchPage();
    }
    if (section == HomeSection.explore) {
      return _HomeSectionWithTitle(
        title: section.label,
        child: ExplorePage(isCompact: isCompact),
      );
    }
    // 「我的」Tab 直接使用独立 MinePage，自带标题栏处理。
    return _HomeSectionWithTitle(
      title: section.label,
      child: MinePage(
        isCompact: isCompact,
        onOpenOwnerDrawer: onOpenOwnerDrawer,
      ),
    );
  }
}

enum HomeSection { messages, contacts, workbench, explore, profile }

extension HomeSectionInfo on HomeSection {
  String get label {
    if (this == HomeSection.messages) return '消息';
    if (this == HomeSection.contacts) return '通讯录';
    if (this == HomeSection.workbench) return '工作台';
    if (this == HomeSection.explore) return '探索';
    return '我的';
  }

  IconData get icon {
    if (this == HomeSection.messages) return Icons.forum_outlined;
    if (this == HomeSection.contacts) return Icons.contacts_outlined;
    if (this == HomeSection.workbench) return Icons.grid_view_rounded;
    if (this == HomeSection.explore) return Icons.explore_outlined;
    return Icons.person_outline_rounded;
  }

  IconData get selectedIcon {
    if (this == HomeSection.messages) return Icons.forum_rounded;
    if (this == HomeSection.contacts) return Icons.contacts_rounded;
    if (this == HomeSection.workbench) return Icons.grid_view;
    if (this == HomeSection.explore) return Icons.explore_rounded;
    return Icons.person_rounded;
  }
}

Color _homeSectionHeaderBackground(BuildContext context) =>
    Theme.of(context).colorScheme.surface;

/// A title owned by an individual tab page, rather than by the home shell.
class _HomeSectionWithTitle extends StatelessWidget {
  const _HomeSectionWithTitle({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Material(
            color: _homeSectionHeaderBackground(context),
            child: SizedBox(
              height: kAppHeaderHeight,
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// 统一标题栏 / AppBar 高度（含首页标题栏、聊天标题栏、各 Tab 页标题栏）
const double kAppHeaderHeight = 48.0;

/// 微信风格底部导航栏标准高度（不含系统底部安全区）
const double kHomeBottomBarHeight = 56.0;

/// 获取包含系统底部安全区的底部导航栏总高度（用于列表底部避让与滚动垫高）
double getHomeBottomPadding(BuildContext context, {bool isCompact = true}) {
  if (!isCompact) return 0.0;
  return kHomeBottomBarHeight + MediaQuery.paddingOf(context).bottom;
}
