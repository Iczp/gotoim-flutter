import 'package:flutter/material.dart';

import '../data/models/session_summary.dart';

/// Flutter counterpart of UniApp SessionUnitItem.vue.
class SessionUnitItem extends StatelessWidget {
  const SessionUnitItem({required this.item, super.key});

  final SessionSummary item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final raw = item.raw;
    final setting = _map(raw['setting']);
    final badge = _number(raw['publicBadge']);
    final remind =
        _number(raw['remindMeCount']) + _number(raw['remindAllCount']);
    final following = _number(raw['followingCount']);
    final immersed = setting['isImmersed'] == true;
    return Material(
      color: item.isPinned ? const Color(0xFFF0F0F0) : null,
      child: InkWell(
        onTap:
            () => ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('聊天页面正在迁移中'))),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                child: Text(item.title.characters.first),
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
String _time(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
