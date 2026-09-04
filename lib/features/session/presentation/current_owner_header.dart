import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/scan/unified_scan_dispatcher.dart';
import '../data/models/chat_owner.dart';
import 'chat_object_avatar.dart';

/// Header displaying the current chat identity / owner with actions on the trailing side.
class CurrentOwnerHeader extends ConsumerWidget {
  const CurrentOwnerHeader({
    required this.owner,
    required this.hasMultiple,
    required this.isConnecting,
    required this.onPressed,
    super.key,
  });

  final ChatOwner? owner;
  final bool hasMultiple;
  final bool isConnecting;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SizedBox(
      height: 56,
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
            // 左侧身份切换区域
            Expanded(
              child: InkWell(
                onTap: onPressed,
                borderRadius: BorderRadius.circular(24),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    children: [
                      ChatObjectAvatar(
                        name: owner?.name ?? '-',
                        imageUrl: owner?.imageUrl,
                        radius: 18,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          owner?.name ?? 'Goto IM',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (hasMultiple)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(width: 8),

            // 右侧操作按钮：搜索与 + 号菜单
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.search_rounded),
                  tooltip: '搜索',
                  onPressed: () => context.push('/search'),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  tooltip: '更多功能',
                  offset: const Offset(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onSelected: (value) {
                    switch (value) {
                      case 'scan':
                        ref
                            .read(unifiedScanDispatcherProvider)
                            .openAndDispatch(context, ref);
                      case 'add_friend':
                        context.push('/add-friend');
                      case 'create_group':
                        context.push('/create-group');
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem<String>(
                      value: 'scan',
                      child: Row(
                        children: [
                          Icon(Icons.qr_code_scanner_rounded, size: 20),
                          SizedBox(width: 12),
                          Text('扫一扫'),
                        ],
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'add_friend',
                      child: Row(
                        children: [
                          Icon(Icons.person_add_outlined, size: 20),
                          SizedBox(width: 12),
                          Text('添加好友'),
                        ],
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'create_group',
                      child: Row(
                        children: [
                          Icon(Icons.group_add_outlined, size: 20),
                          SizedBox(width: 12),
                          Text('创建群聊'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    ),);
  }
}
