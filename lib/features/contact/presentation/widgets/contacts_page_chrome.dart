import 'package:flutter/material.dart';

/// Shared visual constants for the contacts page.
abstract final class ContactsPageMetrics {
  static const rowExtent = 56.0;
  static const groupHeaderExtent = 36.0;
  static const titleBarExtent = 56.0;
  static const quickActionsExtent = rowExtent * 4;
}

Color contactHeaderBackground(BuildContext context) =>
    Theme.of(context).colorScheme.surface;

class ContactsTitleBar extends StatelessWidget {
  const ContactsTitleBar({super.key});

  @override
  Widget build(BuildContext context) => Material(
    color: contactHeaderBackground(context),
    child: SizedBox(
      height: ContactsPageMetrics.titleBarExtent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: <Widget>[
            Text('通讯录', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            IconButton(
              tooltip: '搜索联系人',
              onPressed:
                  () => ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('联系人搜索将在下一步接入'))),
              icon: const Icon(Icons.search),
            ),
            IconButton(
              tooltip: '添加好友',
              onPressed:
                  () => ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('添加好友功能即将接入'))),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
    ),
  );
}

class ContactsQuickActions extends StatelessWidget {
  const ContactsQuickActions({super.key});

  static const _items = <(String, IconData, Color)>[
    ('添加好友', Icons.person_add_alt_1_rounded, Color(0xfff59e0b)),
    ('附近', Icons.person_pin_circle_outlined, Color(0xff049565)),
    ('群聊', Icons.groups_rounded, Color(0xff4f90e0)),
    ('广场', Icons.star_rounded, Color(0xfff34f4f)),
  ];

  @override
  Widget build(BuildContext context) => Column(
    children: _items
        .map(
          (item) => SizedBox(
            height: ContactsPageMetrics.rowExtent,
            child: ListTile(
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: item.$3,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  item.$2,
                  color: const Color.fromRGBO(255, 255, 255, .5),
                ),
              ),
              title: Text(item.$1),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap:
                  () => ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('${item.$1}功能即将接入'))),
            ),
          ),
        )
        .toList(growable: false),
  );
}

class ContactsErrorBanner extends StatelessWidget {
  const ContactsErrorBanner({
    required this.error,
    required this.hasContacts,
    required this.onRetry,
    super.key,
  });

  final Object error;
  final bool hasContacts;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => MaterialBanner(
    content: Text(hasContacts ? '在线通讯录更新失败，正在显示本地联系人。' : '通讯录加载失败：$error'),
    actions: <Widget>[TextButton(onPressed: onRetry, child: const Text('重试'))],
  );
}

class NoContacts extends StatelessWidget {
  const NoContacts({super.key});

  @override
  Widget build(BuildContext context) => const Center(child: Text('暂无联系人'));
}

class ContactsLoadingSkeleton extends StatelessWidget {
  const ContactsLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: <Widget>[
          Container(
            height: ContactsPageMetrics.groupHeaderExtent,
            color: color,
          ),
          ...List<Widget>.generate(
            7,
            (index) => SizedBox(
              height: ContactsPageMetrics.rowExtent,
              child: Row(
                children: <Widget>[
                  const SizedBox(width: 16),
                  CircleAvatar(radius: 21, backgroundColor: color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: index.isEven ? .42 : .58,
                        child: Container(height: 14, color: color),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
