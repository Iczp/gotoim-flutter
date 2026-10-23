import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show Uint8List;

/// 微信同款高保真网页浮窗悬浮球/胶囊组件。
///
/// 特性：
/// - 显示网站图标与网页标题/域名缩略；
/// - 点击主体呼叫 [onRestore] 重新全屏恢复网页；
/// - 提供右上角微型关闭 [onClose] 按钮，可直接移除浮窗；
/// - 优雅的圆角卡片、阴影和毛玻璃半透质感。
class FloatingWebBubble extends StatefulWidget {
  const FloatingWebBubble({
    required this.url,
    required this.onRestore,
    required this.onClose,
    this.title,
    this.thumbnail,
    super.key,
  });

  final String url;
  final String? title;
  final Uint8List? thumbnail;
  final VoidCallback onRestore;
  final VoidCallback onClose;

  @override
  State<FloatingWebBubble> createState() => _FloatingWebBubbleState();
}

class _FloatingWebBubbleState extends State<FloatingWebBubble> {
  final _preview = OverlayPortalController();
  final _link = LayerLink();
  bool _below = false;
  double _previewShift = 0;
  void _showPreview() {
    if (widget.thumbnail == null || _preview.isShowing) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero);
    final center = origin.dx + box.size.width / 2;
    final screen = MediaQuery.sizeOf(context);
    _below = origin.dy < 200;
    final previewWidth = (screen.width - 16).clamp(0.0, 240.0);
    _previewShift =
        (center - previewWidth / 2).clamp(
          8.0,
          screen.width - previewWidth - 8,
        ) -
        (center - previewWidth / 2);
    _preview.show();
  }

  void _togglePreview() =>
      _preview.isShowing ? _preview.hide() : _showPreview();

  String get _domain {
    try {
      final uri = Uri.parse(widget.url);
      return uri.host.isNotEmpty ? uri.host : '网页';
    } catch (_) {
      return '网页';
    }
  }

  String get _displayTitle =>
      (widget.title != null && widget.title!.isNotEmpty)
          ? widget.title!
          : _domain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return OverlayPortal(
      controller: _preview,
      overlayChildBuilder:
          (context) => Positioned(
            width: (MediaQuery.sizeOf(context).width - 16).clamp(0.0, 240.0),
            height: 180,
            child: CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor:
                  _below ? Alignment.bottomCenter : Alignment.topCenter,
              followerAnchor:
                  _below ? Alignment.topCenter : Alignment.bottomCenter,
              offset: Offset(_previewShift, _below ? 8 : -8),
              child: IgnorePointer(
                child: Material(
                  key: const ValueKey('floating_web_thumbnail_preview'),
                  elevation: 8,
                  borderRadius: BorderRadius.circular(10),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      Expanded(
                        child: Image.memory(
                          widget.thumbnail!,
                          width: 240,
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          errorBuilder:
                              (_, _, _) => const Center(
                                child: Icon(Icons.broken_image_outlined),
                              ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          _displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      child: CompositedTransformTarget(
        link: _link,
        child: MouseRegion(
          onEnter: (_) => _showPreview(),
          onExit: (_) => _preview.hide(),
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xE62A2A2A) : const Color(0xF2FFFFFF),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color:
                      isDark
                          ? Colors.white12
                          : Colors.black.withValues(alpha: 0.08),
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
                onTap: widget.onRestore,
                onLongPress: widget.thumbnail == null ? null : _togglePreview,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
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
                        clipBehavior: Clip.antiAlias,
                        child:
                            widget.thumbnail != null
                                ? Image.memory(
                                  widget.thumbnail!,
                                  fit: BoxFit.cover,
                                  errorBuilder:
                                      (_, _, _) => const Icon(
                                        Icons.language_rounded,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                )
                                : const Icon(
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
                                  color:
                                      isDark
                                          ? Colors.white
                                          : const Color(0xFF222222),
                                ),
                              ),
                              Text(
                                _domain,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  color:
                                      isDark ? Colors.white54 : Colors.black45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      if (widget.thumbnail != null)
                        GestureDetector(
                          key: const ValueKey('floating_web_thumbnail_button'),
                          behavior: HitTestBehavior.opaque,
                          onTap: _togglePreview,
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.visibility_outlined, size: 17),
                          ),
                        ),
                      // 关闭按钮
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onClose,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color:
                                isDark
                                    ? Colors.white12
                                    : Colors.black.withValues(alpha: 0.06),
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
          ),
        ),
      ),
    );
  }
}
