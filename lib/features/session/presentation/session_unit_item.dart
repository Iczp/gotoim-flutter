import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme_tokens.dart';
import '../../../core/widgets/app_badge.dart';
import '../data/models/session_summary.dart';
import 'chat_object_avatar.dart';
import 'relative_time_text.dart';
import 'session_last_message_preview.dart';

/// Flutter counterpart of UniApp SessionUnitItem.vue.
class SessionUnitItem extends StatelessWidget {
  const SessionUnitItem({
    required this.item,
    required this.showDivider,
    this.dividerIndent = 74.0,
    this.dividerEndIndent = 0.0,
    this.aiRunning = false,
    this.onLongPress,
    this.onTap,
    super.key,
  });

  final SessionSummary item;
  final bool showDivider;
  final double dividerIndent;
  final double dividerEndIndent;
  final bool aiRunning;
  final VoidCallback? onLongPress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tokens = context.appTokens;
    final raw = item.raw;
    final setting = _map(raw['setting']);
    // `owner` identifies the sending/current side. The remote participant
    // (including Aurora AI) is always `destination`. Before its detail is
    // refreshed, this value comes from the persisted local Friend record.
    final destination = _map(raw['destination']);
    final badge = _number(raw['publicBadge']);
    final immersed = setting['isImmersed'] == true;
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
                    name:
                        (destination['displayName'] ??
                                destination['name'] ??
                                item.title)
                            .toString(),
                    imageUrl:
                        (destination['thumbnail'] ?? destination['portrait'])
                            ?.toString(),
                    radius: 24,
                    chatObjectId: item.destinationId,
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
                                RelativeTimeText(
                                  time: item.updatedAt!,
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
                                child: SessionLastMessagePreview(item: item),
                              ),
                              if (aiRunning)
                                const Padding(
                                  padding: EdgeInsets.only(left: 8),
                                  child: _AiThinkingIndicator(),
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
                                  child: AppBadge(
                                    count: badge,
                                    color:
                                        immersed
                                            ? colorScheme.outlineVariant
                                            : tokens.unreadBadgeColor,
                                    textColor:
                                        immersed
                                            ? colorScheme.onSurfaceVariant
                                            : Colors.white,
                                    size: AppBadgeSize.small,
                                    borderWidth: 0,
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

class _AiThinkingIndicator extends StatelessWidget {
  const _AiThinkingIndicator();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Semantics(
      label: 'AI 正在思考',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 1.8, color: color),
          ),
          const SizedBox(width: 4),
          Text(
            'AI思考',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : const <String, dynamic>{};
int _number(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
