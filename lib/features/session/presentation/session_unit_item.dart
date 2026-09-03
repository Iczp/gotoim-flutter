import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme_tokens.dart';
import '../data/models/session_summary.dart';
import 'chat_object_avatar.dart';

/// Flutter counterpart of UniApp SessionUnitItem.vue.
class SessionUnitItem extends StatelessWidget {
  const SessionUnitItem({
    required this.item,
    required this.showDivider,
    this.dividerIndent = 74.0,
    this.dividerEndIndent = 0.0,
    this.onLongPress,
    this.onTap,
    super.key,
  });

  final SessionSummary item;
  final bool showDivider;
  final double dividerIndent;
  final double dividerEndIndent;
  final VoidCallback? onLongPress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tokens = context.appTokens;
    final raw = item.raw;
    final setting = _map(raw['setting']);
    final destination = _map(raw['destination']);
    final lastMessage = _map(raw['lastMessage']);
    final senderSessionUnit = _map(lastMessage['senderSessionUnit']);
    final badge = _number(raw['publicBadge']);
    final remind =
        _number(raw['remindMeCount']) + _number(raw['remindAllCount']);
    final following = _number(raw['followingCount']);
    final immersed = setting['isImmersed'] == true;
    final rawSenderName = _senderName(lastMessage, senderSessionUnit);
    final senderName =
        senderSessionUnit['id']?.toString() == item.id ? '我' : rawSenderName;
    final senderOwnerId = _number(senderSessionUnit['ownerId']);
    final destinationId = _number(destination['id']);
    final messageType = item.messageTypeLabel;
    final showSender =
        senderName.isNotEmpty &&
        lastMessage['messageType'] != 1 &&
        senderOwnerId != destinationId;
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color:
          item.isPinned ? tokens.sessionPinnedBackground : Colors.transparent,
      child: InkWell(
        onLongPress: onLongPress,
        onTap:
            onTap ??
            () => context.push(
              '/chat/${Uri.encodeComponent(item.id)}'
              '?ownerId=${item.ownerId ?? 0}'
              '&title=${Uri.encodeQueryComponent(item.title)}',
            ),
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 68),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  ChatObjectAvatar(
                    name: item.title,
                    imageUrl:
                        (destination['thumbnail'] ?? destination['portrait'])
                            ?.toString(),
                    radius: 24,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: (theme.textTheme.titleSmall ??
                                          const TextStyle())
                                      .copyWith(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                        color: colorScheme.onSurface,
                                      ),
                                ),
                              ),
                              if (item.updatedAt != null) ...[
                                const SizedBox(width: 8),
                                Text(
                                  _time(item.updatedAt!),
                                  maxLines: 1,
                                  style: (theme.textTheme.labelSmall ??
                                          const TextStyle())
                                      .copyWith(
                                        color: colorScheme.onSurfaceVariant
                                            .withValues(
                                              alpha: isDark ? 0.6 : 0.5,
                                            ),
                                      ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      if (immersed && badge > 0)
                                        TextSpan(
                                          text: '[$badge条] ',
                                          style: TextStyle(
                                            color: colorScheme.onSurfaceVariant,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      if (remind > 0)
                                        TextSpan(
                                          text:
                                              '[ ${remind > 99 ? '99+' : remind} 人@我 ] ',
                                          style: TextStyle(
                                            color: tokens.mentionBadgeColor,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      if (following > 0)
                                        TextSpan(
                                          text: '关注 $following ',
                                          style: TextStyle(
                                            color: tokens.followBadgeColor,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      if (showSender)
                                        TextSpan(
                                          text: '$senderName: ',
                                          style: TextStyle(
                                            color: colorScheme.onSurfaceVariant,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      if (messageType.isNotEmpty)
                                        TextSpan(
                                          text: '$messageType ',
                                          style: TextStyle(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      TextSpan(
                                        text:
                                            item.preview.isEmpty
                                                ? '-'
                                                : item.preview,
                                      ),
                                    ],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: (theme.textTheme.bodySmall ??
                                          const TextStyle())
                                      .copyWith(
                                        color: colorScheme.onSurfaceVariant
                                            .withValues(
                                              alpha: isDark ? 0.75 : 0.65,
                                            ),
                                      ),
                                ),
                              ),
                              if (immersed)
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Icon(
                                    Icons.notifications_off_outlined,
                                    size: 16,
                                    color: colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                              if (item.isPinned)
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Icon(
                                    Icons.push_pin_rounded,
                                    size: 15,
                                    color: colorScheme.primary.withValues(
                                      alpha: 0.8,
                                    ),
                                  ),
                                ),
                              if (badge > 0)
                                Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 18,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          immersed
                                              ? colorScheme.outlineVariant
                                              : tokens.unreadBadgeColor,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      badge > 99 ? '99+' : '$badge',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color:
                                            immersed
                                                ? colorScheme.onSurfaceVariant
                                                : Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
              ),
            ),
            if (showDivider)
              PositionedDirectional(
                start: dividerIndent,
                end: dividerEndIndent,
                bottom: 0,
                height: 0.6,
                child: Container(
                  color: tokens.dividerBorder.withValues(
                    alpha: isDark ? 0.45 : 0.55,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : const <String, dynamic>{};
int _number(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
String _time(DateTime value) {
  final now = DateTime.now();
  final hhmm =
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  final difference = now.difference(value);
  if (difference.inMinutes < 1) return '刚刚 $hhmm';
  if (now.year == value.year &&
      now.month == value.month &&
      now.day == value.day) {
    final hour = value.hour;
    final period =
        hour < 6
            ? '凌晨'
            : hour < 12
            ? '上午'
            : hour < 18
            ? '下午'
            : '晚上';
    return '$period $hhmm';
  }
  if (difference.inHours < 24) return '昨天 $hhmm';
  if (difference.inDays < 7) {
    const weekdays = ['日', '一', '二', '三', '四', '五', '六'];
    return '星期${weekdays[value.weekday % 7]} $hhmm';
  }
  if (now.year == value.year) return '${value.month}月${value.day}日 $hhmm';
  return '${value.year}年${value.month}月${value.day}日';
}

String _senderName(
  Map<String, dynamic> message,
  Map<String, dynamic> senderSessionUnit,
) =>
    (senderSessionUnit['displayName'] ??
            senderSessionUnit['memberName'] ??
            _map(message['sender'])['displayName'] ??
            _map(message['sender'])['name'] ??
            '')
        .toString();
