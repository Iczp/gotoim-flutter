import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screenshot_annotation_dialog.dart';

/// 剪贴板图片预发送确认对话框 (ClipboardImageConfirmDialog)
///
/// 核心规范：
/// 1. 微信同款纯净无边框 (border: null)，采用中性黑灰调与 12dp 现代圆角；
/// 2. 高保真图片缩略预览（自适应长宽比，最大高度 260px）；
/// 3. 显示图像大小与文件类型标签；
/// 4. 提供留言输入框（可选随图附言）；
/// 5. 提供 "编辑 / 标注" 入口，支持在发送前进行涂鸦、形状、高亮、马赛克等标注；
/// 6. 键盘快捷支持：Enter 确认发送，Esc 取消。
class ClipboardImageConfirmDialog extends StatefulWidget {
  const ClipboardImageConfirmDialog({
    required this.imageBytes,
    this.initialCaption,
    this.onAnnotatedSend,
    this.recipientLabel,
    super.key,
  });

  final Uint8List imageBytes;
  final String? initialCaption;
  final String? recipientLabel;
  final Future<void> Function(Uint8List annotatedBytes, String? caption)?
  onAnnotatedSend;

  /// 弹出图片预发送确认对话框
  static Future<({bool confirmed, String? caption})?> show(
    BuildContext context, {
    required Uint8List imageBytes,
    String? initialCaption,
    String? recipientLabel,
    Future<void> Function(Uint8List annotatedBytes, String? caption)?
    onAnnotatedSend,
  }) {
    return showGeneralDialog<({bool confirmed, String? caption})>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'DismissClipboardImage',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 200),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1.0).animate(curve),
          child: FadeTransition(opacity: curve, child: child),
        );
      },
      pageBuilder: (context, _, _) {
        return Center(
          child: ClipboardImageConfirmDialog(
            imageBytes: imageBytes,
            initialCaption: initialCaption,
            recipientLabel: recipientLabel,
            onAnnotatedSend: onAnnotatedSend,
          ),
        );
      },
    );
  }

  @override
  State<ClipboardImageConfirmDialog> createState() =>
      _ClipboardImageConfirmDialogState();
}

class _ClipboardImageConfirmDialogState
    extends State<ClipboardImageConfirmDialog> {
  Uint8List? _editedBytes;
  late final TextEditingController _captionController;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _captionController = TextEditingController(text: widget.initialCaption);
  }

  @override
  void dispose() {
    _captionController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onConfirm() {
    final caption = _captionController.text.trim();
    final edited = _editedBytes;
    if (edited != null && widget.onAnnotatedSend != null) {
      Navigator.of(context).pop((confirmed: false, caption: null));
      widget.onAnnotatedSend!(edited, caption.isNotEmpty ? caption : null);
      return;
    }
    Navigator.of(
      context,
    ).pop((confirmed: true, caption: caption.isNotEmpty ? caption : null));
  }

  void _onCancel() {
    Navigator.of(context).pop((confirmed: false, caption: null));
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 微信中性黑灰色阶统一 (#232323 / #1E1E1E)
    final surfaceBg = isDark ? const Color(0xFF232323) : Colors.white;
    final headerBg = isDark ? const Color(0xFF262626) : const Color(0xFFF5F5F5);
    final inputBg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFEFEFEF);
    final textMain = isDark ? const Color(0xFFF0F0F0) : const Color(0xFF1F2937);
    final textSecondary =
        isDark ? const Color(0xFF9E9E9E) : const Color(0xFF6B7280);
    const accentGreen = Color(0xFF07C160);

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.enter &&
              !HardwareKeyboard.instance.isShiftPressed) {
            _onConfirm();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            _onCancel();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 440,
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
          decoration: BoxDecoration(
            color: surfaceBg,
            borderRadius: BorderRadius.circular(12),
            border: null, // 严格无边框
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.25),
                blurRadius: 36,
                spreadRadius: 2,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. 顶部标题栏
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                color: headerBg,
                child: Row(
                  children: [
                    const Icon(
                      Icons.image_outlined,
                      size: 18,
                      color: accentGreen,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '发送图片',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: textMain,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      visualDensity: VisualDensity.compact,
                      tooltip: '关闭 (Esc)',
                      onPressed: _onCancel,
                    ),
                  ],
                ),
              ),

              if (widget.recipientLabel != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Text(
                    '发送给：${widget.recipientLabel}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              // 2. 图片缩略预览区
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Container(
                          constraints: const BoxConstraints(maxHeight: 250),
                          decoration: BoxDecoration(
                            color:
                                isDark
                                    ? Colors.black26
                                    : const Color(0xFFF0F0F0),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Image.memory(
                            _editedBytes ?? widget.imageBytes,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 格式与尺寸微注
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white10 : Colors.black12,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '图片 · ${_formatSize((_editedBytes ?? widget.imageBytes).lengthInBytes)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // 3. 附加留言输入框
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: inputBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: TextField(
                    controller: _captionController,
                    focusNode: _focusNode,
                    style: TextStyle(fontSize: 12.5, color: textMain),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: '添加留言 (可选)...',
                      hintStyle: TextStyle(
                        fontSize: 12.5,
                        color: textSecondary.withValues(alpha: 0.7),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 9),
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // 4. 底部操作按钮栏 (取消 / 确认发送)
              Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                color: headerBg,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    // 微信同款: "编辑 / 标注" 入口
                    TextButton.icon(
                      onPressed:
                          widget.onAnnotatedSend == null
                              ? null
                              : () async {
                                final currentCaption =
                                    _captionController.text.trim();
                                final result =
                                    await ScreenshotAnnotationDialog.show(
                                      context,
                                      imageBytes:
                                          _editedBytes ?? widget.imageBytes,
                                      initialCaption:
                                          currentCaption.isNotEmpty
                                              ? currentCaption
                                              : null,
                                    );
                                if (result != null &&
                                    result.confirmed &&
                                    mounted) {
                                  setState(
                                    () => _editedBytes = result.imageBytes,
                                  );
                                  _captionController.text =
                                      result.caption ?? '';
                                }
                              },
                      icon: const Icon(Icons.draw_outlined, size: 16),
                      label: const Text('编辑 / 标注'),
                      style: TextButton.styleFrom(
                        foregroundColor: textSecondary,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                    ),
                    TextButton(
                      onPressed: _onCancel,
                      style: TextButton.styleFrom(
                        foregroundColor: textSecondary,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      child: const Text('取消 (Esc)'),
                    ),
                    FilledButton(
                      onPressed: _onConfirm,
                      style: FilledButton.styleFrom(
                        backgroundColor: accentGreen,
                        foregroundColor: Colors.white,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(5),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        '发送 (Enter)',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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
