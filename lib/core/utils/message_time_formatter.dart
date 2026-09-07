/// 统一的消息与会话时间格式化工具。
///
/// 兼容会话列表（相对时间优先，如“刚刚”、“5分钟前”）以及聊天消息列表时间展示。
String formatMessageTime(
  DateTime? datetime, {
  DateTime? now,
  bool isRelative = true,
}) {
  if (datetime == null) return '';

  final current = (now ?? DateTime.now()).toLocal();
  final target = datetime.toLocal();
  final hhmm =
      '${target.hour.toString().padLeft(2, '0')}:${target.minute.toString().padLeft(2, '0')}';

  final diff = current.difference(target);

  // 1. 当天内的相对时间处理
  final isSameDay = current.year == target.year &&
      current.month == target.month &&
      current.day == target.day;

  if (isSameDay) {
    if (isRelative) {
      if (diff.inSeconds >= 0 && diff.inSeconds < 60) {
        return '刚刚';
      }
      if (diff.inMinutes >= 1 && diff.inMinutes < 60) {
        return '${diff.inMinutes}分钟前';
      }
    }

    final hour = target.hour;
    final period = hour < 6
        ? '凌晨'
        : hour < 12
            ? '上午'
            : hour < 18
                ? '下午'
                : '晚上';
    return '$period $hhmm';
  }

  // 2. 昨天
  final yesterday = DateTime(current.year, current.month, current.day - 1);
  final isYesterday = yesterday.year == target.year &&
      yesterday.month == target.month &&
      yesterday.day == target.day;
  if (isYesterday) {
    return '昨天 $hhmm';
  }

  // 3. 一周内（7天内且在相同或相邻周）
  if (diff.inDays >= 0 && diff.inDays < 7) {
    const weekdays = ['日', '一', '二', '三', '四', '五', '六'];
    final weekName = weekdays[target.weekday % 7];
    return '星期$weekName $hhmm';
  }

  // 4. 同年
  if (current.year == target.year) {
    return '${target.month}月${target.day}日 $hhmm';
  }

  // 5. 跨年
  return '${target.year}年${target.month}月${target.day}日';
}

/// 聊天消息列表中精简的时间展示格式（如 "3-27 09:26" 或带时段）。
String formatChatMessageTime(DateTime? datetime) {
  if (datetime == null) return '';
  final target = datetime.toLocal();
  final hhmm =
      '${target.hour.toString().padLeft(2, '0')}:${target.minute.toString().padLeft(2, '0')}';
  return '${target.month}-${target.day} $hhmm';
}

/// 检查给定时间是否属于需要定期刷新的相对时间（例如：在过去 1 小时内）。
bool isDynamicRelativeTime(DateTime? datetime, {DateTime? now}) {
  if (datetime == null) return false;
  final current = now ?? DateTime.now();
  final diff = current.difference(datetime);
  return diff.inSeconds >= 0 && diff.inHours < 1;
}
