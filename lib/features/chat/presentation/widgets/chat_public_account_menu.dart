import 'package:flutter/material.dart';

/// 公众号 / 服务号自定义菜单项模型
class PublicAccountMenuItem {
  const PublicAccountMenuItem({
    required this.name,
    this.type = 'click',
    this.key,
    this.url,
    this.subButtons = const <PublicAccountMenuItem>[],
  });

  final String name;
  final String type;
  final String? key;
  final String? url;
  final List<PublicAccountMenuItem> subButtons;

  factory PublicAccountMenuItem.fromJson(Map<String, dynamic> json) {
    final subRaw =
        json['subButtons'] ?? json['sub_button'] ?? json['children'];
    return PublicAccountMenuItem(
      name: (json['name'] ?? json['title'] ?? '').toString(),
      type: (json['type'] ?? 'click').toString(),
      key: json['key']?.toString(),
      url: json['url']?.toString(),
      subButtons:
          subRaw is List
              ? subRaw
                  .whereType<Map>()
                  .map(
                    (e) => PublicAccountMenuItem.fromJson(
                      e.cast<String, dynamic>(),
                    ),
                  )
                  .toList()
              : const <PublicAccountMenuItem>[],
    );
  }
}

/// 公众号底部多级自定义菜单栏组件
class ChatPublicAccountMenu extends StatelessWidget {
  const ChatPublicAccountMenu({
    required this.menus,
    required this.onToggleKeyboard,
    required this.onMenuItemSelected,
    super.key,
  });

  final List<PublicAccountMenuItem> menus;
  final VoidCallback onToggleKeyboard;
  final ValueChanged<PublicAccountMenuItem> onMenuItemSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dividerColor = theme.dividerColor.withValues(alpha: 0.3);

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: dividerColor)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: '切换至键盘输入',
            icon: const Icon(Icons.keyboard_alt_outlined),
            onPressed: onToggleKeyboard,
          ),
          VerticalDivider(
            width: 1,
            color: dividerColor,
            indent: 8,
            endIndent: 8,
          ),
          Expanded(
            child: Row(
              children:
                  menus.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    return Expanded(
                      child: Row(
                        children: [
                          if (index > 0)
                            VerticalDivider(
                              width: 1,
                              color: dividerColor,
                              indent: 8,
                              endIndent: 8,
                            ),
                          Expanded(
                            child:
                                item.subButtons.isNotEmpty
                                    ? _SubmenuButton(
                                      item: item,
                                      onSelect: onMenuItemSelected,
                                    )
                                    : InkWell(
                                      onTap: () => onMenuItemSelected(item),
                                      child: Center(
                                        child: Text(
                                          item.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                      ),
                                    ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubmenuButton extends StatelessWidget {
  const _SubmenuButton({required this.item, required this.onSelect});

  final PublicAccountMenuItem item;
  final ValueChanged<PublicAccountMenuItem> onSelect;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<PublicAccountMenuItem>(
      tooltip: item.name,
      offset: const Offset(0, -10),
      position: PopupMenuPosition.over,
      onSelected: onSelect,
      itemBuilder:
          (context) =>
              item.subButtons
                  .map(
                    (sub) => PopupMenuItem<PublicAccountMenuItem>(
                      value: sub,
                      child: Text(sub.name),
                    ),
                  )
                  .toList(),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.menu_rounded, size: 14),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
