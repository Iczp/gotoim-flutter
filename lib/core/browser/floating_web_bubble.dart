import 'package:flutter/material.dart';

/// 微信同款高保真网页浮窗悬浮球/胶囊组件。
///
/// 特性：
/// - 显示网站图标与网页标题/域名缩略；
/// - 点击主体呼叫 [onRestore] 重新全屏恢复网页；
/// - 提供右上角微型关闭 [onClose] 按钮，可直接移除浮窗；
/// - 优雅的圆角卡片、阴影和毛玻璃半透质感。
class FloatingWebBubble extends StatelessWidget {
  const FloatingWebBubble({
    required this.url,
    required this.onRestore,
    required this.onClose,
    this.title,
    super.key,
  });

  final String url;
  final String? title;
  final VoidCallback onRestore;
  final VoidCallback onClose;

  String get _domain {
    try {
      final uri = Uri.parse(url);
      return uri.host.isNotEmpty ? uri.host : '网页';
    } catch (_) {
      return '网页';
    }
  }

  String get _displayTitle =>
      (title != null && title!.isNotEmpty) ? title! : _domain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xE62A2A2A) : const Color(0xF2FFFFFF),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onRestore,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 网页标识圆点/图标
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: Color(0xFF07C160),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.language_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                // 网页标题
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 110),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : const Color(0xFF222222),
                          ),
                        ),
                        Text(
                          _domain,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // 关闭按钮
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClose,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      size: 13,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
