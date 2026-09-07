import 'dart:async';
import 'package:flutter/widgets.dart';

import '../../../core/utils/message_time_formatter.dart';

/// 可自动定期刷新的相对时间显示组件。
///
/// 当时间处于 1 小时以内的相对时间（如“刚刚”、“1分钟前”）时，启动内部定时器自动触发刷新，
/// 避免静态停留，并在组件销毁时及时清理 Timer。
class RelativeTimeText extends StatefulWidget {
  const RelativeTimeText({
    required this.time,
    this.style,
    this.refreshInterval = const Duration(seconds: 30),
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    super.key,
  });

  final DateTime? time;
  final TextStyle? style;
  final Duration refreshInterval;
  final int maxLines;
  final TextOverflow overflow;

  @override
  State<RelativeTimeText> createState() => _RelativeTimeTextState();
}

class _RelativeTimeTextState extends State<RelativeTimeText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _checkAndScheduleTimer();
  }

  @override
  void didUpdateWidget(RelativeTimeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.time != oldWidget.time ||
        widget.refreshInterval != oldWidget.refreshInterval) {
      _checkAndScheduleTimer();
    }
  }

  @override
  void dispose() {
    _cancelTimer();
    super.dispose();
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _checkAndScheduleTimer() {
    _cancelTimer();
    if (!mounted || widget.time == null) return;

    if (isDynamicRelativeTime(widget.time)) {
      _timer = Timer.periodic(widget.refreshInterval, (_) {
        if (!mounted) return;
        setState(() {});
        // 若已经超出动态刷新区间，则自动停止定时器
        if (!isDynamicRelativeTime(widget.time)) {
          _cancelTimer();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = formatMessageTime(widget.time, isRelative: true);
    return Text(
      text,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      style: widget.style,
    );
  }
}
