import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../session/presentation/session_list_page.dart';

/// Temporary feature entry points for the IM home shell.
///
/// These pages deliberately expose only real, already available navigation.
/// Session, contact, and profile data will replace their empty states after the
/// corresponding repositories and Drift DAOs are migrated.
class HomeSectionPage extends StatelessWidget {
  const HomeSectionPage({
    required this.section,
    required this.isCompact,
    super.key,
  });

  final HomeSection section;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    if (section == HomeSection.messages) {
      return const SessionListPage();
    }
    if (section == HomeSection.contacts) {
      return _EmptyFeatureState(
        icon: Icons.contacts_outlined,
        title: '通讯录',
        description: '好友、群组及其索引将在联系人数据同步完成后接入。',
        actionLabel: '查看 API 连接',
        onAction: () => context.push('/diagnostics/api'),
        isCompact: isCompact,
      );
    }
    if (section == HomeSection.workbench) {
      return _WorkbenchEntry(isCompact: isCompact);
    }
    return _ProfileEntry(isCompact: isCompact);
  }
}

enum HomeSection { messages, contacts, workbench, profile }

extension HomeSectionInfo on HomeSection {
  String get label {
    if (this == HomeSection.messages) return '消息';
    if (this == HomeSection.contacts) return '通讯录';
    if (this == HomeSection.workbench) return '工作台';
    return '我的';
  }

  IconData get icon {
    if (this == HomeSection.messages) return Icons.forum_outlined;
    if (this == HomeSection.contacts) return Icons.contacts_outlined;
    if (this == HomeSection.workbench) return Icons.grid_view_rounded;
    return Icons.person_outline_rounded;
  }

  IconData get selectedIcon {
    if (this == HomeSection.messages) return Icons.forum_rounded;
    if (this == HomeSection.contacts) return Icons.contacts_rounded;
    if (this == HomeSection.workbench) return Icons.grid_view;
    return Icons.person_rounded;
  }
}

class _EmptyFeatureState extends StatelessWidget {
  const _EmptyFeatureState({
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onAction,
    required this.isCompact,
  });

  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback onAction;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isCompact ? 360 : 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: colorScheme.primary),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.monitor_heart_outlined),
                label: Text(actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkbenchEntry extends StatelessWidget {
  const _WorkbenchEntry({required this.isCompact});

  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return _EmptyFeatureState(
      icon: Icons.apps_outlined,
      title: '工作台',
      description: '已接入的应用可在工作台中加载，并支持 Deep Link 唤醒。',
      actionLabel: '打开工作台',
      onAction: () => context.push('/workbench'),
      isCompact: isCompact,
    );
  }
}

class _ProfileEntry extends StatelessWidget {
  const _ProfileEntry({required this.isCompact});

  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return _EmptyFeatureState(
      icon: Icons.account_circle_outlined,
      title: '我的',
      description: '账号资料、收藏和设置会在账户资料接口迁移后显示。',
      actionLabel: '查看认证状态',
      onAction: () => context.push('/diagnostics/auth'),
      isCompact: isCompact,
    );
  }
}
