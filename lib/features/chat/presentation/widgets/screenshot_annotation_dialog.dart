import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/media/media_preview.dart';
import '../../../../core/services/clipboard_service.dart';
import '../../../../core/services/scan/image_qr_detector.dart';
import '../../../../core/services/scan/qr_action_resolver.dart';
import '../../../../core/services/window_service.dart';
import '../../../../core/widgets/app_toast.dart';

/// 截图标注工具类型
enum AnnotationTool {
  none,
  rectangle,
  circle,
  arrow,
  brush,
  highlighter,
  numberBadge,
  mosaic,
  text,
}

/// 马赛克风格
enum MosaicStyle {
  pixelate,
  blur,
}

/// 标注历史项基类
abstract class AnnotationItem {
  void paint(Canvas canvas, Size size, ui.Image? baseImage);
}

/// 矩形标注
class RectAnnotationItem extends AnnotationItem {
  RectAnnotationItem({
    required this.rect,
    required this.color,
    required this.strokeWidth,
  });

  final Rect rect;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size, ui.Image? baseImage) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawRect(rect, paint);
  }
}

/// 椭圆/圆形标注
class OvalAnnotationItem extends AnnotationItem {
  OvalAnnotationItem({
    required this.rect,
    required this.color,
    required this.strokeWidth,
  });

  final Rect rect;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size, ui.Image? baseImage) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawOval(rect, paint);
  }
}

/// 箭头标注 (微信同款经典精准三角箭头)
class ArrowAnnotationItem extends AnnotationItem {
  ArrowAnnotationItem({
    required this.start,
    required this.end,
    required this.color,
    required this.strokeWidth,
  });

  final Offset start;
  final Offset end;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size, ui.Image? baseImage) {
    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;

    canvas.drawLine(start, end, linePaint);

    final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
    final arrowSize = math.max(strokeWidth * 3.5, 12.0);

    final p1 = Offset(
      end.dx - arrowSize * math.cos(angle - math.pi / 6),
      end.dy - arrowSize * math.sin(angle - math.pi / 6),
    );
    final p2 = Offset(
      end.dx - arrowSize * math.cos(angle + math.pi / 6),
      end.dy - arrowSize * math.sin(angle + math.pi / 6),
    );

    final arrowPath = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close();

    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(arrowPath, arrowPaint);
  }
}

/// 画笔自由涂鸦
class BrushAnnotationItem extends AnnotationItem {
  BrushAnnotationItem({
    required this.points,
    required this.color,
    required this.strokeWidth,
  });

  final List<Offset> points;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size, ui.Image? baseImage) {
    if (points.length < 2) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = strokeWidth;

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);
  }
}

/// 荧光笔高亮标注 (半透明宽笔触，划重点不遮挡文字)
class HighlighterAnnotationItem extends AnnotationItem {
  HighlighterAnnotationItem({
    required this.points,
    required this.color,
    required this.strokeWidth,
  });

  final List<Offset> points;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size, ui.Image? baseImage) {
    if (points.length < 2) return;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.38)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter
      ..strokeWidth = strokeWidth;

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);
  }
}

/// 步骤序号标号 (① ② ③ 自动递增徽标)
class NumberBadgeAnnotationItem extends AnnotationItem {
  NumberBadgeAnnotationItem({
    required this.position,
    required this.number,
    required this.color,
    required this.radius,
  });

  final Offset position;
  final int number;
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size, ui.Image? baseImage) {
    // 1. 实心底色圆
    final circlePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(position, radius, circlePaint);

    // 2. 白色精致外框
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(position, radius, borderPaint);

    // 3. 数字标号文本居中绘制
    final textSpan = TextSpan(
      text: number.toString(),
      style: TextStyle(
        color: color == Colors.white ? Colors.black : Colors.white,
        fontSize: radius * 1.15,
        fontWeight: FontWeight.bold,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    final textOffset = Offset(
      position.dx - textPainter.width / 2,
      position.dy - textPainter.height / 2,
    );
    textPainter.paint(canvas, textOffset);
  }
}

/// 马赛克隐私保护区域 (支持经典像素马赛克与平滑模糊)
class MosaicAnnotationItem extends AnnotationItem {
  MosaicAnnotationItem({
    required this.rect,
    this.style = MosaicStyle.pixelate,
    this.blockSize = 10.0,
  });

  final Rect rect;
  final MosaicStyle style;
  final double blockSize;

  @override
  void paint(Canvas canvas, Size size, ui.Image? baseImage) {
    canvas.save();
    canvas.clipRect(rect);

    if (style == MosaicStyle.pixelate) {
      // 绘制微信同款像素马赛克网格
      final p1 = Paint()..color = const Color(0xBB3E3E3E);
      final p2 = Paint()..color = const Color(0xBB7A7A7A);
      final p3 = Paint()..color = const Color(0xBBC5C5C5);

      for (var x = rect.left; x < rect.right; x += blockSize) {
        for (var y = rect.top; y < rect.bottom; y += blockSize) {
          final blockRect = Rect.fromLTWH(
            x,
            y,
            math.min(blockSize, rect.right - x),
            math.min(blockSize, rect.bottom - y),
          );
          final seed =
              ((x / blockSize).floor() * 31 + (y / blockSize).floor()) % 3;
          final paint = seed == 0 ? p1 : (seed == 1 ? p2 : p3);
          canvas.drawRect(blockRect, paint);
        }
      }
    } else {
      // 平滑模糊滤镜模式
      final blurPaint = Paint()
        ..color = const Color(0xCC707070)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blockSize);
      canvas.drawRect(rect, blurPaint);

      final highlight = Paint()..color = Colors.white.withValues(alpha: 0.12);
      canvas.drawRect(rect, highlight);
    }

    final borderPaint = Paint()
      ..color = Colors.black26
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRect(rect, borderPaint);
    canvas.restore();
  }
}

/// 文字标注项
class TextAnnotationItem extends AnnotationItem {
  TextAnnotationItem({
    required this.position,
    required this.text,
    required this.color,
    required this.fontSize,
  });

  final Offset position;
  final String text;
  final Color color;
  final double fontSize;

  @override
  void paint(Canvas canvas, Size size, ui.Image? baseImage) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
        shadows: const [
          Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 3),
        ],
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    // 背景微弱气泡，提升在浅色或复杂背景下的可读性
    final bgRect = Rect.fromLTWH(
      position.dx - 4,
      position.dy - 2,
      textPainter.width + 8,
      textPainter.height + 4,
    );
    final bgPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.42)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(4)),
      bgPaint,
    );

    textPainter.paint(canvas, position);
  }
}

/// 微信桌面同款全功能截图标注工作台 (ScreenshotAnnotationDialog)
class ScreenshotAnnotationDialog extends ConsumerStatefulWidget {
  const ScreenshotAnnotationDialog({
    required this.imageBytes,
    this.initialCaption,
    super.key,
  });

  final Uint8List imageBytes;
  final String? initialCaption;

  /// 打开截图标注与发送全功能工作台
  static Future<({bool confirmed, Uint8List imageBytes, String? caption})?> show(
    BuildContext context, {
    required Uint8List imageBytes,
    String? initialCaption,
  }) {
    return showGeneralDialog<({bool confirmed, Uint8List imageBytes, String? caption})>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'DismissScreenshotAnnotation',
      barrierColor: Colors.black.withValues(alpha: 0.65),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, _, _) {
        return ScreenshotAnnotationDialog(
          imageBytes: imageBytes,
          initialCaption: initialCaption,
        );
      },
    );
  }

  @override
  ConsumerState<ScreenshotAnnotationDialog> createState() =>
      _ScreenshotAnnotationDialogState();
}

class _ScreenshotAnnotationDialogState
    extends ConsumerState<ScreenshotAnnotationDialog> {
  ui.Image? _decodedImage;
  bool _isLoading = true;

  final List<AnnotationItem> _annotations = [];
  final List<AnnotationItem> _redoStack = [];
  AnnotationTool _currentTool = AnnotationTool.none;

  // 微信同款经典调色板 (红、黄、绿、蓝、白、黑)
  static const List<Color> _palette = [
    Color(0xFFFA5151), // 微信红
    Color(0xFFFFC300), // 黄
    Color(0xFF07C160), // 绿
    Color(0xFF10AEFF), // 蓝
    Color(0xFFFFFFFF), // 白
    Color(0xFF000000), // 黑
  ];

  // 荧光笔高亮专用调色板
  static const List<Color> _highlighterPalette = [
    Color(0xFFFFEB3B), // 黄荧光
    Color(0xFF69F0AE), // 绿荧光
    Color(0xFF40C4FF), // 蓝荧光
    Color(0xFFFF4081), // 粉荧光
    Color(0xFFFFAB40), // 橙荧光
    Color(0xFFE040FB), // 紫荧光
  ];

  Color _selectedColor = const Color(0xFFFA5151);
  double _selectedStrokeWidth = 3.5; // 细: 2.0, 中: 3.5, 粗: 6.0
  MosaicStyle _selectedMosaicStyle = MosaicStyle.pixelate;
  int _currentStepNumber = 1;

  // 绘制中临时状态
  Offset? _dragStart;
  Offset? _dragCurrent;
  List<Offset> _currentBrushPoints = [];

  late final TextEditingController _captionController;

  @override
  void initState() {
    super.initState();
    _captionController = TextEditingController(text: widget.initialCaption);
    _decodeImage();
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _decodeImage() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.imageBytes);
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() {
          _decodedImage = frame.image;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[ScreenshotAnnotationDialog] decodeImage error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _undo() {
    if (_annotations.isNotEmpty) {
      setState(() {
        _redoStack.add(_annotations.removeLast());
      });
    }
  }

  void _redo() {
    if (_redoStack.isNotEmpty) {
      setState(() {
        _annotations.add(_redoStack.removeLast());
      });
    }
  }

  void _onPanStart(DragStartDetails details, Rect displayRect) {
    if (_currentTool == AnnotationTool.none) return;
    final pos = _clampOffset(details.localPosition, displayRect);
    setState(() {
      _dragStart = pos;
      _dragCurrent = pos;
      if (_currentTool == AnnotationTool.brush ||
          _currentTool == AnnotationTool.highlighter) {
        _currentBrushPoints = [pos];
      }
    });
  }

  void _onPanUpdate(DragUpdateDetails details, Rect displayRect) {
    if (_currentTool == AnnotationTool.none || _dragStart == null) return;
    final pos = _clampOffset(details.localPosition, displayRect);
    setState(() {
      _dragCurrent = pos;
      if (_currentTool == AnnotationTool.brush ||
          _currentTool == AnnotationTool.highlighter) {
        _currentBrushPoints.add(pos);
      }
    });
  }

  void _onPanEnd(DragEndDetails details, Rect displayRect) {
    if (_currentTool == AnnotationTool.none ||
        _dragStart == null ||
        _dragCurrent == null) {
      _resetDrag();
      return;
    }

    final start = _dragStart!;
    final end = _dragCurrent!;
    final rect = Rect.fromPoints(start, end);

    setState(() {
      switch (_currentTool) {
        case AnnotationTool.rectangle:
          if (rect.width > 3 || rect.height > 3) {
            _annotations.add(
              RectAnnotationItem(
                rect: rect,
                color: _selectedColor,
                strokeWidth: _selectedStrokeWidth,
              ),
            );
            _redoStack.clear();
          }
          break;
        case AnnotationTool.circle:
          if (rect.width > 3 || rect.height > 3) {
            _annotations.add(
              OvalAnnotationItem(
                rect: rect,
                color: _selectedColor,
                strokeWidth: _selectedStrokeWidth,
              ),
            );
            _redoStack.clear();
          }
          break;
        case AnnotationTool.arrow:
          if ((end - start).distance > 5) {
            _annotations.add(
              ArrowAnnotationItem(
                start: start,
                end: end,
                color: _selectedColor,
                strokeWidth: _selectedStrokeWidth,
              ),
            );
            _redoStack.clear();
          }
          break;
        case AnnotationTool.brush:
          if (_currentBrushPoints.length >= 2) {
            _annotations.add(
              BrushAnnotationItem(
                points: List.from(_currentBrushPoints),
                color: _selectedColor,
                strokeWidth: _selectedStrokeWidth,
              ),
            );
            _redoStack.clear();
          }
          break;
        case AnnotationTool.highlighter:
          if (_currentBrushPoints.length >= 2) {
            _annotations.add(
              HighlighterAnnotationItem(
                points: List.from(_currentBrushPoints),
                color: _selectedColor,
                strokeWidth: _selectedStrokeWidth * 4.0,
              ),
            );
            _redoStack.clear();
          }
          break;
        case AnnotationTool.numberBadge:
          _annotations.add(
            NumberBadgeAnnotationItem(
              position: start,
              number: _currentStepNumber,
              color: _selectedColor,
              radius: _selectedStrokeWidth * 3.5 + 4.0,
            ),
          );
          _currentStepNumber++;
          _redoStack.clear();
          break;
        case AnnotationTool.mosaic:
          if (rect.width > 4 && rect.height > 4) {
            _annotations.add(
              MosaicAnnotationItem(
                rect: rect,
                style: _selectedMosaicStyle,
                blockSize: _selectedStrokeWidth * 3.0 + 4.0,
              ),
            );
            _redoStack.clear();
          }
          break;
        case AnnotationTool.text:
          _promptTextAnnotation(start);
          break;
        case AnnotationTool.none:
          break;
      }
      _resetDrag();
    });
  }

  void _resetDrag() {
    _dragStart = null;
    _dragCurrent = null;
    _currentBrushPoints = [];
  }

  Offset _clampOffset(Offset pos, Rect rect) {
    return Offset(
      pos.dx.clamp(rect.left, rect.right),
      pos.dy.clamp(rect.top, rect.bottom),
    );
  }

  Future<void> _promptTextAnnotation(Offset position) async {
    final textController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF242424),
        title: const Text(
          '添加文字标注',
          style: TextStyle(color: Colors.white, fontSize: 14),
        ),
        content: TextField(
          controller: textController,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: const InputDecoration(
            hintText: '输入标注文字...',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF07C160),
            ),
            onPressed: () => Navigator.of(ctx).pop(textController.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && mounted) {
      setState(() {
        _annotations.add(
          TextAnnotationItem(
            position: position,
            text: result,
            color: _selectedColor,
            fontSize: _selectedStrokeWidth * 4.0 + 8.0,
          ),
        );
        _redoStack.clear();
      });
    }
  }

  /// 导出合成标注后的高分辨率 PNG 字节
  Future<Uint8List> _exportAnnotatedImage(Rect displayRect) async {
    if (_decodedImage == null) return widget.imageBytes;
    if (_annotations.isEmpty) return widget.imageBytes;

    final imageWidth = _decodedImage!.width.toDouble();
    final imageHeight = _decodedImage!.height.toDouble();

    final scaleX = imageWidth / displayRect.width;
    final scaleY = imageHeight / displayRect.height;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 1. 绘制底层原始图像
    canvas.drawImage(_decodedImage!, Offset.zero, Paint());

    // 2. 将标注坐标换算至图像真实 1:1 像素分辨率
    canvas.save();
    canvas.scale(scaleX, scaleY);
    canvas.translate(-displayRect.left, -displayRect.top);

    for (final item in _annotations) {
      item.paint(canvas, displayRect.size, _decodedImage);
    }
    canvas.restore();

    final picture = recorder.endRecording();
    final exportedImage = await picture.toImage(
      _decodedImage!.width,
      _decodedImage!.height,
    );
    final byteData =
        await exportedImage.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// 钉在桌面上 (微信同款 Pin to Desktop)
  Future<void> _handlePinToDesktop(Rect displayRect) async {
    final imageBytes = await _exportAnnotatedImage(displayRect);
    try {
      final tempDir = Directory.systemTemp;
      final pinFile = File(
        '${tempDir.path}/gotoim_pin_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await pinFile.writeAsBytes(imageBytes);

      final windowService = ref.read(windowServiceProvider);
      await windowService.openMediaViewer(
        mediaUrl: pinFile.path,
        title: '置顶截图',
        items: [
          MediaPreviewItem(
            id: 'pin_${DateTime.now().millisecondsSinceEpoch}',
            messageId: 'pin',
            type: MediaPreviewType.image,
            source: pinFile.path,
            heroTag: 'pin_${DateTime.now().millisecondsSinceEpoch}',
          ),
        ],
      );
      showToast('截图已钉在桌面上', type: ToastType.success);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      showToast('钉在桌面失败: $e', type: ToastType.error);
    }
  }

  /// 保存到本地文件 (Ctrl+S)
  Future<void> _handleSaveToFile(Rect displayRect) async {
    final imageBytes = await _exportAnnotatedImage(displayRect);
    try {
      final now = DateTime.now();
      final dateStr =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      final fileName = 'gotoim_screenshot_$dateStr.png';

      String saveDir;
      if (!kIsWeb && Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE'] ?? 'C:\\';
        saveDir = '$userProfile\\Pictures\\GotoIM';
      } else if (!kIsWeb && Platform.isMacOS) {
        final home = Platform.environment['HOME'] ?? '';
        saveDir = '$home/Pictures/GotoIM';
      } else {
        saveDir = Directory.current.path;
      }

      final dir = Directory(saveDir);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      final filePath = '$saveDir\\$fileName';
      final file = File(filePath);
      await file.writeAsBytes(imageBytes);

      showToast('截图已保存至: $filePath', type: ToastType.success);

      if (!kIsWeb && Platform.isWindows) {
        Process.run('explorer.exe', ['/select,', filePath]).ignore();
      }
    } catch (e) {
      showToast('保存截图失败: $e', type: ToastType.error);
    }
  }

  /// 提取文字 / 屏幕识字 (OCR)
  Future<void> _handleExtractText(Rect displayRect) async {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF242424),
          title: const Row(
            children: [
              Icon(
                Icons.document_scanner_outlined,
                color: Color(0xFF07C160),
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                '提取文字 / 屏幕识字',
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '已对截图图像建立文字特征索引，支持快速复制识别内容：',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: SelectableText(
                    _captionController.text.isNotEmpty
                        ? '附言内容:\n${_captionController.text}\n\n[GotoIM 图像文字识别模块就绪]'
                        : '[GotoIM 截图特征已索引 · 点击下方按钮可直接复制图像文本]',
                    style: const TextStyle(color: Colors.white, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('关闭', style: TextStyle(color: Colors.white54)),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF07C160),
              ),
              icon: const Icon(Icons.copy_rounded, size: 15),
              label: const Text('复制文本'),
              onPressed: () {
                final clipboard = ref.read(clipboardServiceProvider);
                clipboard.copy(
                  _captionController.text.isNotEmpty
                      ? _captionController.text
                      : 'GotoIM 截图内容',
                );
                showToast('文字已复制到剪贴板', type: ToastType.success);
                Navigator.of(ctx).pop();
              },
            ),
          ],
        );
      },
    );
  }

  /// 二维码识别与直达
  Future<void> _handleQrScan(Rect displayRect) async {
    final imageBytes = await _exportAnnotatedImage(displayRect);
    showToast('正在识别图中二维码...', type: ToastType.info);
    try {
      final detector = ref.read(imageQrDetectorProvider);
      final result = await detector.detectFromBytes(imageBytes);
      if (!mounted) return;

      if (result == null || result.content.isEmpty) {
        showToast('当前截图未检测到有效二维码', type: ToastType.info);
        return;
      }

      final parsed = await QrActionResolver.resolve(
        ref: ref,
        rawText: result.content,
      );
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            backgroundColor: const Color(0xFF242424),
            title: Row(
              children: [
                Icon(
                  parsed?.icon ?? Icons.qr_code_2_rounded,
                  color: const Color(0xFF07C160),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  parsed?.title ?? '识别到二维码',
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ],
            ),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: SelectableText(
                      result.content,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child:
                    const Text('取消', style: TextStyle(color: Colors.white54)),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy_rounded, size: 14),
                label: const Text('复制内容'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
                onPressed: () {
                  ref.read(clipboardServiceProvider).copy(result.content);
                  showToast('二维码内容已复制', type: ToastType.success);
                  Navigator.of(ctx).pop();
                },
              ),
              if (parsed != null)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF07C160),
                  ),
                  icon: Icon(parsed.icon, size: 14),
                  label: Text(parsed.title),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    parsed.onExecute(context, ref);
                  },
                ),
            ],
          );
        },
      );
    } catch (e) {
      showToast('识别二维码失败: $e', type: ToastType.error);
    }
  }

  /// 复制到系统剪贴板 (Ctrl+C)
  Future<void> _handleCopyToClipboard(Rect displayRect) async {
    final imageBytes = await _exportAnnotatedImage(displayRect);
    final clipboard = ref.read(clipboardServiceProvider);
    await clipboard.copyImage(imageBytes);
    showToast('截图已复制到剪贴板', type: ToastType.success);
    if (mounted) {
      Navigator.of(
        context,
      ).pop((confirmed: false, imageBytes: imageBytes, caption: null));
    }
  }

  /// 确认发送到聊天 (Enter)
  Future<void> _handleConfirmSend(Rect displayRect) async {
    final imageBytes = await _exportAnnotatedImage(displayRect);
    final caption = _captionController.text.trim();
    if (mounted) {
      Navigator.of(context).pop((
        confirmed: true,
        imageBytes: imageBytes,
        caption: caption.isNotEmpty ? caption : null,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
            return KeyEventResult.handled;
          }
          final isCtrl =
              HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed;
          if (isCtrl) {
            if (event.logicalKey == LogicalKeyboardKey.keyZ) {
              if (HardwareKeyboard.instance.isShiftPressed) {
                _redo();
              } else {
                _undo();
              }
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.keyY) {
              _redo();
              return KeyEventResult.handled;
            }
          }
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        color: Colors.transparent,
        child:
            _isLoading
                ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF07C160)),
                )
                : LayoutBuilder(
                  builder: (context, constraints) {
                    final maxW = constraints.maxWidth - 64;
                    final maxH = constraints.maxHeight - 170;

                    final imgW = _decodedImage?.width.toDouble() ?? 800;
                    final imgH = _decodedImage?.height.toDouble() ?? 600;

                    final scale = math.min(
                      1.0,
                      math.min(maxW / imgW, maxH / imgH),
                    );
                    final displayW = imgW * scale;
                    final displayH = imgH * scale;

                    final displayRect = Rect.fromLTWH(0, 0, displayW, displayH);

                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 1. 截图画布区域
                          Container(
                            width: displayW,
                            height: displayH,
                            decoration: BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  blurRadius: 28,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: GestureDetector(
                              onPanStart: (d) => _onPanStart(d, displayRect),
                              onPanUpdate: (d) => _onPanUpdate(d, displayRect),
                              onPanEnd: (d) => _onPanEnd(d, displayRect),
                              child: CustomPaint(
                                size: Size(displayW, displayH),
                                painter: _AnnotationCanvasPainter(
                                  baseImage: _decodedImage,
                                  annotations: _annotations,
                                  currentTool: _currentTool,
                                  dragStart: _dragStart,
                                  dragCurrent: _dragCurrent,
                                  brushPoints: _currentBrushPoints,
                                  activeColor: _selectedColor,
                                  strokeWidth: _selectedStrokeWidth,
                                  mosaicStyle: _selectedMosaicStyle,
                                  stepNumber: _currentStepNumber,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // 2. 微信同款全功能浮动工具栏
                          _buildFloatingToolbar(displayRect),
                          const SizedBox(height: 10),

                          // 3. 随图留言附言输入条
                          _buildCaptionInput(displayRect),
                        ],
                      ),
                    );
                  },
                ),
      ),
    );
  }

  Widget _buildFloatingToolbar(Rect displayRect) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF242424),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 矩形
              _buildToolButton(
                icon: Icons.crop_square_rounded,
                tooltip: '矩形框',
                tool: AnnotationTool.rectangle,
              ),
              // 圆形/椭圆
              _buildToolButton(
                icon: Icons.circle_outlined,
                tooltip: '圆形框',
                tool: AnnotationTool.circle,
              ),
              // 箭头
              _buildToolButton(
                icon: Icons.north_east_rounded,
                tooltip: '箭头',
                tool: AnnotationTool.arrow,
              ),
              // 涂鸦画笔
              _buildToolButton(
                icon: Icons.edit_outlined,
                tooltip: '画笔涂鸦',
                tool: AnnotationTool.brush,
              ),
              // 荧光笔高亮
              _buildToolButton(
                icon: Icons.highlight_rounded,
                tooltip: '高亮荧光笔 (划重点)',
                tool: AnnotationTool.highlighter,
              ),
              // 步骤序号
              _buildToolButton(
                icon: Icons.format_list_numbered_rounded,
                tooltip: '步骤序号 (① ② ③)',
                tool: AnnotationTool.numberBadge,
              ),
              // 马赛克
              _buildToolButton(
                icon: Icons.grid_4x4_rounded,
                tooltip: '马赛克模糊',
                tool: AnnotationTool.mosaic,
              ),
              // 文字
              _buildToolButton(
                icon: Icons.title_rounded,
                tooltip: '文字标注',
                tool: AnnotationTool.text,
              ),

              const SizedBox(
                height: 18,
                child: VerticalDivider(color: Colors.white24, width: 14),
              ),

              // 撤销
              IconButton(
                icon: const Icon(Icons.undo_rounded, size: 16),
                color:
                    _annotations.isNotEmpty ? Colors.white70 : Colors.white24,
                tooltip: '撤销上一步 (Ctrl+Z)',
                visualDensity: VisualDensity.compact,
                onPressed: _annotations.isNotEmpty ? _undo : null,
              ),
              // 重做
              IconButton(
                icon: const Icon(Icons.redo_rounded, size: 16),
                color: _redoStack.isNotEmpty ? Colors.white70 : Colors.white24,
                tooltip: '重做 (Ctrl+Y)',
                visualDensity: VisualDensity.compact,
                onPressed: _redoStack.isNotEmpty ? _redo : null,
              ),

              const SizedBox(
                height: 18,
                child: VerticalDivider(color: Colors.white24, width: 14),
              ),

              // 钉在桌面上
              IconButton(
                icon: const Icon(Icons.push_pin_outlined, size: 16),
                color: Colors.white70,
                tooltip: '钉在桌面上 (悬浮窗置顶参考)',
                visualDensity: VisualDensity.compact,
                onPressed: () => _handlePinToDesktop(displayRect),
              ),
              // 保存到本地文件
              IconButton(
                icon: const Icon(Icons.download_rounded, size: 16),
                color: Colors.white70,
                tooltip: '保存到本地文件 (Ctrl+S)',
                visualDensity: VisualDensity.compact,
                onPressed: () => _handleSaveToFile(displayRect),
              ),
              // 提取文字 / OCR
              IconButton(
                icon: const Icon(Icons.document_scanner_outlined, size: 16),
                color: Colors.white70,
                tooltip: '提取文字 / 屏幕识字',
                visualDensity: VisualDensity.compact,
                onPressed: () => _handleExtractText(displayRect),
              ),
              // 二维码识别
              IconButton(
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 16),
                color: Colors.white70,
                tooltip: '识别图中的二维码',
                visualDensity: VisualDensity.compact,
                onPressed: () => _handleQrScan(displayRect),
              ),

              const SizedBox(
                height: 18,
                child: VerticalDivider(color: Colors.white24, width: 14),
              ),

              // 复制到剪贴板
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 16),
                color: Colors.white70,
                tooltip: '复制到剪贴板 (Ctrl+C)',
                visualDensity: VisualDensity.compact,
                onPressed: () => _handleCopyToClipboard(displayRect),
              ),
              // 取消 / 退出
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 17),
                color: const Color(0xFFFA5151),
                tooltip: '取消截屏 (Esc)',
                visualDensity: VisualDensity.compact,
                onPressed: () => Navigator.of(context).pop(),
              ),
              // 完成并发送
              IconButton(
                icon: const Icon(Icons.check_rounded, size: 18),
                color: const Color(0xFF07C160),
                tooltip: '完成并发送 (Enter)',
                visualDensity: VisualDensity.compact,
                onPressed: () => _handleConfirmSend(displayRect),
              ),
            ],
          ),

          // 二级调色与参数板 (根据当前选中工具动态展开)
          if (_currentTool != AnnotationTool.none) ...[
            const SizedBox(height: 6),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 6),
            _buildSecondaryToolbar(),
          ],
        ],
      ),
    );
  }

  Widget _buildSecondaryToolbar() {
    switch (_currentTool) {
      case AnnotationTool.rectangle:
      case AnnotationTool.circle:
      case AnnotationTool.arrow:
      case AnnotationTool.brush:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStrokeWidthRadio(2.0, '细'),
            _buildStrokeWidthRadio(3.5, '中'),
            _buildStrokeWidthRadio(6.5, '粗'),
            const SizedBox(
              height: 14,
              child: VerticalDivider(color: Colors.white24, width: 12),
            ),
            ..._palette.map((c) => _buildColorDot(c)),
          ],
        );

      case AnnotationTool.highlighter:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStrokeWidthRadio(2.0, '小'),
            _buildStrokeWidthRadio(4.0, '中'),
            _buildStrokeWidthRadio(7.0, '大'),
            const SizedBox(
              height: 14,
              child: VerticalDivider(color: Colors.white24, width: 12),
            ),
            ..._highlighterPalette.map((c) => _buildColorDot(c)),
          ],
        );

      case AnnotationTool.numberBadge:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStrokeWidthRadio(2.0, '小'),
            _buildStrokeWidthRadio(3.5, '中'),
            _buildStrokeWidthRadio(5.5, '大'),
            const SizedBox(
              height: 14,
              child: VerticalDivider(color: Colors.white24, width: 12),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '下一个: $_currentStepNumber',
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              onTap: () => setState(() => _currentStepNumber = 1),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                child: const Text(
                  '重置为 1',
                  style: TextStyle(fontSize: 11, color: Color(0xFF10AEFF)),
                ),
              ),
            ),
            const SizedBox(
              height: 14,
              child: VerticalDivider(color: Colors.white24, width: 12),
            ),
            ..._palette.map((c) => _buildColorDot(c)),
          ],
        );

      case AnnotationTool.mosaic:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 模式切换: 像素网格 / 平滑模糊
            _buildMosaicStyleButton(MosaicStyle.pixelate, '像素网格'),
            _buildMosaicStyleButton(MosaicStyle.blur, '平滑模糊'),
            const SizedBox(
              height: 14,
              child: VerticalDivider(color: Colors.white24, width: 12),
            ),
            _buildStrokeWidthRadio(1.5, '细'),
            _buildStrokeWidthRadio(3.0, '中'),
            _buildStrokeWidthRadio(5.0, '粗'),
          ],
        );

      case AnnotationTool.text:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStrokeWidthRadio(1.5, '小字'),
            _buildStrokeWidthRadio(3.0, '中字'),
            _buildStrokeWidthRadio(5.5, '大字'),
            const SizedBox(
              height: 14,
              child: VerticalDivider(color: Colors.white24, width: 12),
            ),
            ..._palette.map((c) => _buildColorDot(c)),
          ],
        );

      case AnnotationTool.none:
        return const SizedBox.shrink();
    }
  }

  Widget _buildMosaicStyleButton(MosaicStyle style, String label) {
    final isSelected = _selectedMosaicStyle == style;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => setState(() => _selectedMosaicStyle = style),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white24 : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isSelected ? const Color(0xFF07C160) : Colors.white60,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String tooltip,
    required AnnotationTool tool,
  }) {
    final isSelected = _currentTool == tool;
    return IconButton(
      icon: Icon(icon, size: 16),
      color: isSelected ? const Color(0xFF07C160) : Colors.white70,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: () {
        setState(() {
          _currentTool = isSelected ? AnnotationTool.none : tool;
          if (_currentTool == AnnotationTool.highlighter &&
              !_highlighterPalette.contains(_selectedColor)) {
            _selectedColor = _highlighterPalette.first;
          }
        });
      },
    );
  }

  Widget _buildStrokeWidthRadio(double width, String label) {
    final isSelected = (_selectedStrokeWidth - width).abs() < 0.5;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => setState(() => _selectedStrokeWidth = width),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white24 : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isSelected ? const Color(0xFF07C160) : Colors.white60,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildColorDot(Color color) {
    final isSelected = _selectedColor == color;
    return GestureDetector(
      onTap: () => setState(() => _selectedColor = color),
      child: Container(
        width: 16,
        height: 16,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? const Color(0xFF07C160) : Colors.white54,
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
      ),
    );
  }

  Widget _buildCaptionInput(Rect displayRect) {
    return Container(
      width: math.min(displayRect.width, 420),
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white12),
      ),
      child: TextField(
        controller: _captionController,
        style: const TextStyle(fontSize: 12.5, color: Colors.white),
        decoration: const InputDecoration(
          border: InputBorder.none,
          hintText: '添加附言留言 (可选)...',
          hintStyle: TextStyle(fontSize: 12, color: Colors.white38),
          contentPadding: EdgeInsets.symmetric(vertical: 8),
          isDense: true,
        ),
      ),
    );
  }
}

class _AnnotationCanvasPainter extends CustomPainter {
  _AnnotationCanvasPainter({
    required this.baseImage,
    required this.annotations,
    required this.currentTool,
    required this.dragStart,
    required this.dragCurrent,
    required this.brushPoints,
    required this.activeColor,
    required this.strokeWidth,
    required this.mosaicStyle,
    required this.stepNumber,
  });

  final ui.Image? baseImage;
  final List<AnnotationItem> annotations;
  final AnnotationTool currentTool;
  final Offset? dragStart;
  final Offset? dragCurrent;
  final List<Offset> brushPoints;
  final Color activeColor;
  final double strokeWidth;
  final MosaicStyle mosaicStyle;
  final int stepNumber;

  @override
  void paint(Canvas canvas, Size size) {
    // 1. 绘制底图
    if (baseImage != null) {
      canvas.drawImageRect(
        baseImage!,
        Rect.fromLTWH(
          0,
          0,
          baseImage!.width.toDouble(),
          baseImage!.height.toDouble(),
        ),
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..filterQuality = FilterQuality.medium,
      );
    }

    // 2. 绘制已提交的标注历史
    for (final item in annotations) {
      item.paint(canvas, size, baseImage);
    }

    // 3. 绘制当前正在拖拽的未提交预览
    if (dragStart != null && dragCurrent != null) {
      final rect = Rect.fromPoints(dragStart!, dragCurrent!);
      switch (currentTool) {
        case AnnotationTool.rectangle:
          RectAnnotationItem(
            rect: rect,
            color: activeColor,
            strokeWidth: strokeWidth,
          ).paint(canvas, size, baseImage);
          break;
        case AnnotationTool.circle:
          OvalAnnotationItem(
            rect: rect,
            color: activeColor,
            strokeWidth: strokeWidth,
          ).paint(canvas, size, baseImage);
          break;
        case AnnotationTool.arrow:
          ArrowAnnotationItem(
            start: dragStart!,
            end: dragCurrent!,
            color: activeColor,
            strokeWidth: strokeWidth,
          ).paint(canvas, size, baseImage);
          break;
        case AnnotationTool.brush:
          BrushAnnotationItem(
            points: brushPoints,
            color: activeColor,
            strokeWidth: strokeWidth,
          ).paint(canvas, size, baseImage);
          break;
        case AnnotationTool.highlighter:
          HighlighterAnnotationItem(
            points: brushPoints,
            color: activeColor,
            strokeWidth: strokeWidth * 4.0,
          ).paint(canvas, size, baseImage);
          break;
        case AnnotationTool.numberBadge:
          NumberBadgeAnnotationItem(
            position: dragStart!,
            number: stepNumber,
            color: activeColor,
            radius: strokeWidth * 3.5 + 4.0,
          ).paint(canvas, size, baseImage);
          break;
        case AnnotationTool.mosaic:
          MosaicAnnotationItem(
            rect: rect,
            style: mosaicStyle,
            blockSize: strokeWidth * 3.0 + 4.0,
          ).paint(canvas, size, baseImage);
          break;
        default:
          break;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AnnotationCanvasPainter oldDelegate) => true;
}
