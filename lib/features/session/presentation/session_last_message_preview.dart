import 'package:flutter/material.dart';

import '../../../core/theme/app_theme_tokens.dart';
import '../../../core/utils/message_text_formatter.dart';
import '../data/models/session_summary.dart';

/// 会话列表项最后一条发送消息的富文本渲染组件。
///
/// 整合展示：
/// 1. 免打扰下的未读数 `[x条]`；
/// 2. `@我` 徽标提醒 `[ x 人@我 ]`；
/// 3. 关注计数 `关注 x`；
/// 4. 发送者昵称 `张三: `；
/// 5. 消息类型前缀（如 `[图片] `、`[系统] `、`[文件] ` 等）；
/// 6. 经特定标签清洗与换行符规整后的消息摘要文本。
class SessionLastMessagePreview extends StatelessWidget {
  const SessionLastMessagePreview({
    required this.item,
    this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    super.key,
  });

  final SessionSummary item;
  final TextStyle? style;
  final int maxLines;
  final TextOverflow overflow;

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

    final showSender = senderName.isNotEmpty &&
        lastMessage['messageType'] != 1 &&
        senderOwnerId != destinationId;

    final isDark = theme.brightness == Brightness.dark;
    final defaultStyle = (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
      color: colorScheme.onSurfaceVariant.withValues(
        alpha: isDark ? 0.75 : 0.65,
      ),
    );

    final messageState = (lastMessage['state'] ?? '').toString();
    final isSending = messageState == 'sending' || messageState == 'pending';
    final isFailed = messageState == 'failed';

    // 清洗特定标签（如 <a>user</a>、<a uid="...">name</a>、换行符）
    final cleanedPreview = stripMessageTags(item.preview);
    final displayText = cleanedPreview.isEmpty ? '-' : cleanedPreview;

    return Text.rich(
      TextSpan(
        children: [
          if (isSending)
            TextSpan(
              text: '[发送中...] ',
              style: TextStyle(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (isFailed)
            TextSpan(
              text: '[发送失败] ',
              style: TextStyle(
                color: colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
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
              text: '[ ${remind > 99 ? '99+' : remind} 人@我 ] ',
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
          TextSpan(text: displayText),
        ],
      ),
      maxLines: maxLines,
      overflow: overflow,
      style: style ?? defaultStyle,
    );
  }

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? value.cast<String, dynamic>() : const <String, dynamic>{};

  static int _number(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  static String _senderName(
    Map<String, dynamic> message,
    Map<String, dynamic> senderSessionUnit,
  ) =>
      (senderSessionUnit['displayName'] ??
              senderSessionUnit['memberName'] ??
              _map(message['sender'])['displayName'] ??
              _map(message['sender'])['name'] ??
              '')
          .toString();
}
