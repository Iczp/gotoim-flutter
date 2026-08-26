import 'package:flutter/material.dart';

import '../data/models/session_summary.dart';
import 'chat_object_avatar.dart';

/// Flutter counterpart of UniApp SessionUnitItem.vue.
class SessionUnitItem extends StatelessWidget {
  const SessionUnitItem({
    required this.item,
    required this.showDivider,
    super.key,
  });

  final SessionSummary item;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
    return Material(
      color: item.isPinned ? const Color(0xFFF0F0F0) : null,
      child: InkWell(
        onTap:
            () => ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('聊天页面正在迁移中'))),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration:
              showDivider
                  ? const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0x33000000)),
                    ),
                  )
                  : null,
          child: Row(
            children: [
              ChatObjectAvatar(
                name: item.title,
                imageUrl:
                    (destination['thumbnail'] ?? destination['portrait'])
                        ?.toString(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        if (item.updatedAt != null)
                          Text(
                            _time(item.updatedAt!),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.grey,
                            ),
                          ),
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
                                    style: const TextStyle(color: Colors.grey),
                                  ),
                                if (remind > 0)
                                  TextSpan(
                                    text:
                                        '[ ${remind > 99 ? '99+' : remind} 人@我 ] ',
                                    style: const TextStyle(
                                      color: Color(0xFFEC0101),
                                    ),
                                  ),
                                if (following > 0)
                                  TextSpan(
                                    text: '关注 $following ',
                                    style: const TextStyle(
                                      color: Color(0xFFF64DFF),
                                    ),
                                  ),
                                if (showSender)
                                  TextSpan(
                                    text: '$senderName: ',
                                    style: const TextStyle(
                                      color: Color(0xFF757575),
                                    ),
                                  ),
                                if (messageType.isNotEmpty)
                                  TextSpan(
                                    text: '$messageType ',
                                    style: const TextStyle(
                                      color: Color(0xFF666666),
                                    ),
                                  ),
                                TextSpan(
                                  text:
                                      item.preview.isEmpty ? '-' : item.preview,
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        if (immersed)
                          const Icon(
                            Icons.notifications_off_outlined,
                            size: 17,
                          ),
                        if (item.isPinned)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(Icons.star_outline, size: 17),
                          ),
                        if (badge > 0)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Badge(
                              label: Text(badge > 99 ? '99+' : '$badge'),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
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
