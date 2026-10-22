import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/media/media_preview.dart';
import '../../../../core/platform/windows/windows_window_adapter.dart';
import '../../../../core/services/clipboard_service.dart';
import '../../../../core/services/window_service.dart';
import '../../../../core/widgets/app_toast.dart';
import 'screenshot_annotation_dialog.dart';

/// 截图选区交互阶段
enum _CropPhase {
  none,
  draggingNew,
  selected,
  resizingHandle,
  movingBox,
}

/// 8个控制锚点定义
enum _ResizeHandle {
  topLeft,
  topCenter,
  topRight,
  middleRight,
  bottomRight,
  bottomCenter,
  bottomLeft,
  middleLeft,
}

/// 独立全功能桌面截图标注工作台 (DesktopScreenCaptureView)
///
/// 特性：
/// 1. 独立窗口预热常驻与瞬时唤醒复用，免去每次创建 Flutter 引擎的漫长冷启动；
/// 2. 选取后保持选区可见，提供 8 点拖拽锚点自由调整选区尺寸与位置；
/// 3. 内嵌直接涂鸦、矩形、椭圆、箭头、荧光笔高亮、步骤序号、马赛克模糊与文字标注；
/// 4. 支持快捷键 (Esc取消、Enter完成、Ctrl+C复制、Ctrl+S保存、Ctrl+Z撤销) 与选区内双击瞬时确认发送。
class DesktopScreenCaptureView extends ConsumerStatefulWidget {
  const DesktopScreenCaptureView({
    this.onClose,
    this.onRegisterMethodHandler,
    super.key,
  });

  final VoidCallback? onClose;
  final void Function(Future<dynamic> Function(MethodCall call) handler)?
  onRegisterMethodHandler;

  @override
  ConsumerState<DesktopScreenCaptureView> createState() =>
      _DesktopScreenCaptureViewState();
}

class _DesktopScreenCaptureViewState
    extends ConsumerState<DesktopScreenCaptureView> {
  ui.Image? _baseImage;
  int _screenWidth = 1920;
  int _screenHeight = 1080;
  bool _isLoading = false;

  Rect? _cropRect;
  _CropPhase _phase = _CropPhase.none;
  _ResizeHandle? _activeHandle;
  Offset? _dragStart;
  Offset? _moveOffsetStart;
  MouseCursor _cursor = SystemMouseCursors.basic;

  // 标注数据与工具状态
  final List<AnnotationItem> _annotations = [];
  final List<AnnotationItem> _redoStack = [];
  AnnotationTool _currentTool = AnnotationTool.none;
  Color _selectedColor = const Color(0xFFFA5151); // 经典微信红
  double _selectedStrokeWidth = 3.5;
  final MosaicStyle _selectedMosaicStyle = MosaicStyle.pixelate;
  int _currentStepNumber = 1;

  // 绘制中临时状态
  Offset? _toolDragStart;
  Offset? _toolDragCurrent;
  List<Offset> _currentBrushPoints = [];

  // IPC 通道
  static const _mainIpcChannel = WindowMethodChannel(
    'gotoim/ipc_to_main',
    mode: ChannelMode.unidirectional,
  );

  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.onRegisterMethodHandler?.call(_handleMethodCall);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'show_screen_capture':
        final args = call.arguments as Map?;
        if (args != null) {
          final path = args['imagePath'] as String? ?? '';
          final w = (args['width'] as num?)?.toInt() ?? 1920;
          final h = (args['height'] as num?)?.toInt() ?? 1080;
          final x = (args['x'] as num?)?.toInt() ?? 0;
          final y = (args['y'] as num?)?.toInt() ?? 0;
          final dpi = (args['dpi'] as num?)?.toInt() ?? 96;
          await _loadAndActivate(
            path: path,
            width: w,
            height: h,
            x: x,
            y: y,
            dpi: dpi,
          );
        }
        return true;
      case 'hide_screen_capture':
        await _handleCancel();
        return true;
      default:
        return null;
    }
  }

  Future<void> _loadAndActivate({
    required String path,
    required int width,
    required int height,
    required int x,
    required int y,
    required int dpi,
  }) async {
    setState(() {
      _isLoading = true;
      _screenWidth = width;
      _screenHeight = height;
      _cropRect = null;
      _phase = _CropPhase.none;
      _activeHandle = null;
      _annotations.clear();
      _redoStack.clear();
      _currentTool = AnnotationTool.none;
      _currentStepNumber = 1;
    });

    try {
      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        if (mounted) {
          setState(() {
            _baseImage = frame.image;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('[DesktopScreenCaptureView] 加载截图底图失败: $e');
      if (mounted) setState(() => _isLoading = false);
    }

    await WindowsWindowAdapter.showScreenCapture(
      x: x,
      y: y,
      width: width,
      height: height,
    );
    _focusNode.requestFocus();
  }

  // -------------------------------------------------------------
  // 选区与 8 锚点 Hit-Test & 调整
  // -------------------------------------------------------------

  Map<_ResizeHandle, Offset> _getHandleOffsets(Rect rect) {
    return {
      _ResizeHandle.topLeft: rect.topLeft,
      _ResizeHandle.topCenter: Offset(rect.center.dx, rect.top),
      _ResizeHandle.topRight: rect.topRight,
      _ResizeHandle.middleRight: Offset(rect.right, rect.center.dy),
      _ResizeHandle.bottomRight: rect.bottomRight,
      _ResizeHandle.bottomCenter: Offset(rect.center.dx, rect.bottom),
      _ResizeHandle.bottomLeft: rect.bottomLeft,
      _ResizeHandle.middleLeft: Offset(rect.left, rect.center.dy),
    };
  }

  _ResizeHandle? _hitTestHandle(Offset pos, Rect rect) {
    const handleHitRadius = 12.0;
    final handles = _getHandleOffsets(rect);
    for (final entry in handles.entries) {
      if ((pos - entry.value).distance <= handleHitRadius) {
        return entry.key;
      }
    }
    return null;
  }

  MouseCursor _cursorForHandle(_ResizeHandle handle) {
    switch (handle) {
      case _ResizeHandle.topLeft:
      case _ResizeHandle.bottomRight:
        return SystemMouseCursors.resizeUpLeftDownRight;
      case _ResizeHandle.topRight:
      case _ResizeHandle.bottomLeft:
        return SystemMouseCursors.resizeUpRightDownLeft;
      case _ResizeHandle.topCenter:
      case _ResizeHandle.bottomCenter:
        return SystemMouseCursors.resizeUpDown;
      case _ResizeHandle.middleLeft:
      case _ResizeHandle.middleRight:
        return SystemMouseCursors.resizeLeftRight;
    }
  }

  void _onHover(PointerHoverEvent event) {
    if (_phase == _CropPhase.selected && _cropRect != null) {
      final pos = event.localPosition;
      final handle = _hitTestHandle(pos, _cropRect!);
      if (handle != null) {
        final newCursor = _cursorForHandle(handle);
        if (_cursor != newCursor) setState(() => _cursor = newCursor);
        return;
      }
      if (_cropRect!.contains(pos)) {
        final newCursor =
            _currentTool == AnnotationTool.none
                ? SystemMouseCursors.move
                : SystemMouseCursors.precise;
        if (_cursor != newCursor) setState(() => _cursor = newCursor);
        return;
      }
      if (_cursor != SystemMouseCursors.basic) {
        setState(() => _cursor = SystemMouseCursors.basic);
      }
    } else {
      if (_cursor != SystemMouseCursors.basic) {
        setState(() => _cursor = SystemMouseCursors.basic);
      }
    }
  }

  void _onPanStart(DragStartDetails details) {
    final pos = details.localPosition;
    if (_phase == _CropPhase.selected && _cropRect != null) {
      // 1. 检查是否点中了 8 锚点
      final handle = _hitTestHandle(pos, _cropRect!);
      if (handle != null) {
        setState(() {
          _phase = _CropPhase.resizingHandle;
          _activeHandle = handle;
          _dragStart = pos;
        });
        return;
      }

      // 2. 检查是否点在选区内
      if (_cropRect!.contains(pos)) {
        if (_currentTool == AnnotationTool.none) {
          // 移动选区
          setState(() {
            _phase = _CropPhase.movingBox;
            _moveOffsetStart = pos - _cropRect!.topLeft;
          });
        } else {
          // 在选区内直接涂鸦 / 绘制标注
          _startDrawing(pos);
        }
        return;
      }

      // 3. 点击在选区外部：重置选区并开始重新拖拽
      setState(() {
        _annotations.clear();
        _redoStack.clear();
        _currentTool = AnnotationTool.none;
        _phase = _CropPhase.draggingNew;
        _dragStart = pos;
        _cropRect = Rect.fromPoints(pos, pos);
      });
    } else {
      // 首次拉取选区
      setState(() {
        _phase = _CropPhase.draggingNew;
        _dragStart = pos;
        _cropRect = Rect.fromPoints(pos, pos);
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final pos = details.localPosition;
    final maxW = _screenWidth.toDouble();
    final maxH = _screenHeight.toDouble();

    if (_phase == _CropPhase.draggingNew && _dragStart != null) {
      setState(() {
        _cropRect = Rect.fromPoints(_dragStart!, pos);
      });
    } else if (_phase == _CropPhase.resizingHandle &&
        _activeHandle != null &&
        _cropRect != null) {
      double left = _cropRect!.left;
      double top = _cropRect!.top;
      double right = _cropRect!.right;
      double bottom = _cropRect!.bottom;

      switch (_activeHandle!) {
        case _ResizeHandle.topLeft:
          left = pos.dx.clamp(0.0, right - 24.0);
          top = pos.dy.clamp(0.0, bottom - 24.0);
          break;
        case _ResizeHandle.topCenter:
          top = pos.dy.clamp(0.0, bottom - 24.0);
          break;
        case _ResizeHandle.topRight:
          right = pos.dx.clamp(left + 24.0, maxW);
          top = pos.dy.clamp(0.0, bottom - 24.0);
          break;
        case _ResizeHandle.middleRight:
          right = pos.dx.clamp(left + 24.0, maxW);
          break;
        case _ResizeHandle.bottomRight:
          right = pos.dx.clamp(left + 24.0, maxW);
          bottom = pos.dy.clamp(top + 24.0, maxH);
          break;
        case _ResizeHandle.bottomCenter:
          bottom = pos.dy.clamp(top + 24.0, maxH);
          break;
        case _ResizeHandle.bottomLeft:
          left = pos.dx.clamp(0.0, right - 24.0);
          bottom = pos.dy.clamp(top + 24.0, maxH);
          break;
        case _ResizeHandle.middleLeft:
          left = pos.dx.clamp(0.0, right - 24.0);
          break;
      }

      setState(() {
        _cropRect = Rect.fromLTRB(left, top, right, bottom);
      });
    } else if (_phase == _CropPhase.movingBox &&
        _moveOffsetStart != null &&
        _cropRect != null) {
      final newLeft = (pos.dx - _moveOffsetStart!.dx).clamp(
        0.0,
        maxW - _cropRect!.width,
      );
      final newTop = (pos.dy - _moveOffsetStart!.dy).clamp(
        0.0,
        maxH - _cropRect!.height,
      );
      setState(() {
        _cropRect = Rect.fromLTWH(
          newLeft,
          newTop,
          _cropRect!.width,
          _cropRect!.height,
        );
      });
    } else if (_currentTool != AnnotationTool.none && _cropRect != null) {
      _updateDrawing(pos);
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (_phase == _CropPhase.draggingNew) {
      if (_cropRect != null) {
        // 规格化正方形 / 矩形
        final normRect = Rect.fromLTRB(
          math.min(_cropRect!.left, _cropRect!.right),
          math.min(_cropRect!.top, _cropRect!.bottom),
          math.max(_cropRect!.left, _cropRect!.right),
          math.max(_cropRect!.top, _cropRect!.bottom),
        );
        if (normRect.width >= 16 && normRect.height >= 16) {
          setState(() {
            _cropRect = normRect;
            _phase = _CropPhase.selected;
          });
        } else {
          setState(() {
            _cropRect = null;
            _phase = _CropPhase.none;
          });
        }
      }
    } else if (_phase == _CropPhase.resizingHandle ||
        _phase == _CropPhase.movingBox) {
      setState(() {
        _phase = _CropPhase.selected;
        _activeHandle = null;
        _moveOffsetStart = null;
      });
    } else if (_currentTool != AnnotationTool.none && _cropRect != null) {
      _finishDrawing();
    }
  }

  // -------------------------------------------------------------
  // 直接涂鸦与标注绘制
  // -------------------------------------------------------------

  Offset _clampToCrop(Offset pos) {
    if (_cropRect == null) return pos;
    return Offset(
      pos.dx.clamp(_cropRect!.left, _cropRect!.right),
      pos.dy.clamp(_cropRect!.top, _cropRect!.bottom),
    );
  }

  void _startDrawing(Offset rawPos) {
    final pos = _clampToCrop(rawPos);
    setState(() {
      _toolDragStart = pos;
      _toolDragCurrent = pos;
      if (_currentTool == AnnotationTool.brush ||
          _currentTool == AnnotationTool.highlighter) {
        _currentBrushPoints = [pos];
      }
    });
  }

  void _updateDrawing(Offset rawPos) {
    final pos = _clampToCrop(rawPos);
    setState(() {
      _toolDragCurrent = pos;
      if (_currentTool == AnnotationTool.brush ||
          _currentTool == AnnotationTool.highlighter) {
        _currentBrushPoints.add(pos);
      }
    });
  }

  void _finishDrawing() {
    if (_toolDragStart == null || _toolDragCurrent == null) {
      _resetToolDrag();
      return;
    }

    final start = _toolDragStart!;
    final end = _toolDragCurrent!;
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
      _resetToolDrag();
    });
  }

  void _resetToolDrag() {
    _toolDragStart = null;
    _toolDragCurrent = null;
    _currentBrushPoints = [];
  }

  void _undo() {
    if (_annotations.isNotEmpty) {
      setState(() => _redoStack.add(_annotations.removeLast()));
    }
  }

  void _redo() {
    if (_redoStack.isNotEmpty) {
      setState(() => _annotations.add(_redoStack.removeLast()));
    }
  }

  Future<void> _promptTextAnnotation(Offset position) async {
    final textController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
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
                child: const Text(
                  '取消',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF07C160),
                ),
                onPressed:
                    () => Navigator.of(ctx).pop(textController.text.trim()),
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

  // -------------------------------------------------------------
  // 图像高分辨率裁切与合成导出
  // -------------------------------------------------------------

  Future<Uint8List> _exportCroppedImage() async {
    if (_baseImage == null || _cropRect == null) {
      return Uint8List(0);
    }

    final crop = _cropRect!;
    final cropW = crop.width.round().clamp(1, _baseImage!.width);
    final cropH = crop.height.round().clamp(1, _baseImage!.height);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 1. 将原图裁切区域绘制至画布
    final srcRect = Rect.fromLTWH(
      crop.left * (_baseImage!.width / _screenWidth),
      crop.top * (_baseImage!.height / _screenHeight),
      crop.width * (_baseImage!.width / _screenWidth),
      crop.height * (_baseImage!.height / _screenHeight),
    );
    final dstRect = Rect.fromLTWH(0, 0, cropW.toDouble(), cropH.toDouble());
    canvas.drawImageRect(_baseImage!, srcRect, dstRect, Paint());

    // 2. 坐标换算并绘制标注
    canvas.save();
    final scaleX = cropW / crop.width;
    final scaleY = cropH / crop.height;
    canvas.scale(scaleX, scaleY);
    canvas.translate(-crop.left, -crop.top);

    for (final item in _annotations) {
      item.paint(canvas, crop.size, _baseImage);
    }
    canvas.restore();

    final picture = recorder.endRecording();
    final img = await picture.toImage(cropW, cropH);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  // -------------------------------------------------------------
  // 动作与快捷键操作 (完成/复制/保存/置顶/取消)
  // -------------------------------------------------------------

  Future<void> _confirmAndSend() async {
    if (_cropRect == null) return;
    try {
      final imageBytes = await _exportCroppedImage();
      final clipboard = ref.read(clipboardServiceProvider);
      await clipboard.copyImage(imageBytes);
      await _mainIpcChannel.invokeMethod('screen_capture_result', {
        'bytes': imageBytes.toList(),
      });
      await WindowsWindowAdapter.hide();
    } catch (e) {
      debugPrint('[DesktopScreenCaptureView] 确认导出失败: $e');
    }
  }

  int _lastClickTime = 0;
  Offset? _lastClickPos;

  void _onPointerDown(PointerDownEvent event) {
    if (_cropRect != null && _cropRect!.contains(event.localPosition)) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (_lastClickPos != null &&
          (event.localPosition - _lastClickPos!).distance < 12 &&
          (now - _lastClickTime) < 350) {
        _lastClickTime = 0;
        _lastClickPos = null;
        _confirmAndSend();
        return;
      }
      _lastClickTime = now;
      _lastClickPos = event.localPosition;
    }
  }

  Future<void> _handleCopy() async {
    if (_cropRect == null) return;
    try {
      final imageBytes = await _exportCroppedImage();
      final clipboard = ref.read(clipboardServiceProvider);
      await clipboard.copyImage(imageBytes);
      showToast('已复制截图到剪贴板', type: ToastType.success);
      await _mainIpcChannel.invokeMethod('screen_capture_result', {
        'bytes': imageBytes.toList(),
      });
      await WindowsWindowAdapter.hide();
    } catch (e) {
      debugPrint('[DesktopScreenCaptureView] 复制截图失败: $e');
    }
  }

  Future<void> _handleSaveToFile() async {
    if (_cropRect == null) return;
    try {
      final imageBytes = await _exportCroppedImage();
      final now = DateTime.now();
      final dateStr =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      final fileName = 'gotoim_screenshot_$dateStr.png';

      final userProfile = Platform.environment['USERPROFILE'] ?? 'C:\\';
      final saveDir = '$userProfile\\Pictures\\GotoIM';
      final dir = Directory(saveDir);
      if (!dir.existsSync()) dir.createSync(recursive: true);

      final filePath = '$saveDir\\$fileName';
      final file = File(filePath);
      await file.writeAsBytes(imageBytes);

      showToast('截图已保存至: $filePath', type: ToastType.success);
      Process.run('explorer.exe', ['/select,', filePath]).ignore();
    } catch (e) {
      showToast('保存截图失败: $e', type: ToastType.error);
    }
  }

  Future<void> _handlePinToDesktop() async {
    if (_cropRect == null) return;
    try {
      final imageBytes = await _exportCroppedImage();
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
      await _handleCancel();
    } catch (e) {
      showToast('置顶失败: $e', type: ToastType.error);
    }
  }

  Future<void> _handleCancel() async {
    try {
      await _mainIpcChannel.invokeMethod('screen_capture_cancel');
    } catch (_) {}
    await WindowsWindowAdapter.hide();
  }

  // -------------------------------------------------------------
  // UI 结构渲染
  // -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Material(
        color: Colors.black,
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFF07C160)),
        ),
      );
    }

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            _handleCancel();
          } else if (event.logicalKey == LogicalKeyboardKey.enter) {
            _confirmAndSend();
          } else if (event.logicalKey == LogicalKeyboardKey.keyZ &&
              HardwareKeyboard.instance.isControlPressed) {
            _undo();
          } else if (event.logicalKey == LogicalKeyboardKey.keyC &&
              HardwareKeyboard.instance.isControlPressed) {
            _handleCopy();
          } else if (event.logicalKey == LogicalKeyboardKey.keyS &&
              HardwareKeyboard.instance.isControlPressed) {
            _handleSaveToFile();
          }
        }
      },
      child: MouseRegion(
        cursor: _cursor,
        onHover: _onHover,
        child: Listener(
          onPointerDown: _onPointerDown,
          child: GestureDetector(
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            onDoubleTap: _confirmAndSend,
            child: Stack(
            children: [
              // 1. 全屏底图与遮罩 CustomPaint
              Positioned.fill(
                child: CustomPaint(
                  painter: _ScreenCaptureCanvasPainter(
                    baseImage: _baseImage,
                    cropRect: _cropRect,
                    phase: _phase,
                    annotations: _annotations,
                    currentTool: _currentTool,
                    toolDragStart: _toolDragStart,
                    toolDragCurrent: _toolDragCurrent,
                    brushPoints: _currentBrushPoints,
                    selectedColor: _selectedColor,
                    strokeWidth: _selectedStrokeWidth,
                    mosaicStyle: _selectedMosaicStyle,
                    stepNumber: _currentStepNumber,
                  ),
                ),
              ),

              // 2. 提示气泡 (在未框选时显示引导提示)
              if (_cropRect == null)
                Positioned(
                  top: 40,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(color: Colors.black45, blurRadius: 8),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.crop_rounded,
                            color: Color(0xFF07C160),
                            size: 16,
                          ),
                          SizedBox(width: 8),
                          Text(
                            '按住鼠标左键拖拽框选截图区域 · Esc 退出截图',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // 3. 悬浮在选区下方的微信全功能工具条
              if (_cropRect != null && _phase == _CropPhase.selected)
                _buildFloatingToolbar(),
            ],
          ),
        ),
      ),
    ),
  );
}

  Widget _buildFloatingToolbar() {
    final crop = _cropRect!;
    const toolbarHeight = 44.0;
    const toolbarWidth = 530.0;

    // 默认附着在选区正下方 8px，若贴底则附着在选区上方
    double top = crop.bottom + 8.0;
    if (top + toolbarHeight > _screenHeight - 12.0) {
      top = crop.top - toolbarHeight - 8.0;
      if (top < 8.0) top = 8.0;
    }

    double left = crop.right - toolbarWidth;
    if (left < 10.0) left = 10.0;
    if (left + toolbarWidth > _screenWidth - 10.0) {
      left = _screenWidth - toolbarWidth - 10.0;
    }

    return Positioned(
      left: left,
      top: top,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 调色板与粗细选择条 (当激活标注工具时展开)
          if (_currentTool != AnnotationTool.none) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF242424),
                borderRadius: BorderRadius.circular(6),
                boxShadow: const [
                  BoxShadow(color: Colors.black45, blurRadius: 10),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...[
                    const Color(0xFFFA5151), // 红
                    const Color(0xFFFFC300), // 黄
                    const Color(0xFF07C160), // 绿
                    const Color(0xFF10AEFF), // 蓝
                    const Color(0xFFFFFFFF), // 白
                    const Color(0xFF000000), // 黑
                  ].map((color) {
                    final isSel = _selectedColor == color;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedColor = color),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSel ? Colors.white : Colors.white24,
                            width: isSel ? 2.5 : 1.0,
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(
                    height: 14,
                    child: VerticalDivider(color: Colors.white24, width: 14),
                  ),
                  _buildStrokeButton(label: '细', width: 2.0),
                  _buildStrokeButton(label: '中', width: 3.5),
                  _buildStrokeButton(label: '粗', width: 6.0),
                ],
              ),
            ),
          ],

          // 核心浮动工具栏
          Container(
            height: toolbarHeight,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF242424),
              borderRadius: BorderRadius.circular(6),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildToolButton(
                  icon: Icons.crop_square_rounded,
                  tooltip: '矩形框',
                  tool: AnnotationTool.rectangle,
                ),
                _buildToolButton(
                  icon: Icons.circle_outlined,
                  tooltip: '圆形框',
                  tool: AnnotationTool.circle,
                ),
                _buildToolButton(
                  icon: Icons.north_east_rounded,
                  tooltip: '箭头',
                  tool: AnnotationTool.arrow,
                ),
                _buildToolButton(
                  icon: Icons.edit_outlined,
                  tooltip: '画笔涂鸦',
                  tool: AnnotationTool.brush,
                ),
                _buildToolButton(
                  icon: Icons.highlight_rounded,
                  tooltip: '高亮荧光笔',
                  tool: AnnotationTool.highlighter,
                ),
                _buildToolButton(
                  icon: Icons.format_list_numbered_rounded,
                  tooltip: '序号标注',
                  tool: AnnotationTool.numberBadge,
                ),
                _buildToolButton(
                  icon: Icons.grid_4x4_rounded,
                  tooltip: '马赛克',
                  tool: AnnotationTool.mosaic,
                ),
                _buildToolButton(
                  icon: Icons.title_rounded,
                  tooltip: '文字标注',
                  tool: AnnotationTool.text,
                ),

                const SizedBox(
                  height: 18,
                  child: VerticalDivider(color: Colors.white24, width: 12),
                ),

                // 撤销 / 重做
                IconButton(
                  icon: const Icon(Icons.undo_rounded, size: 16),
                  color:
                      _annotations.isNotEmpty ? Colors.white70 : Colors.white24,
                  tooltip: '撤销 (Ctrl+Z)',
                  visualDensity: VisualDensity.compact,
                  onPressed: _annotations.isNotEmpty ? _undo : null,
                ),
                IconButton(
                  icon: const Icon(Icons.redo_rounded, size: 16),
                  color:
                      _redoStack.isNotEmpty ? Colors.white70 : Colors.white24,
                  tooltip: '重做',
                  visualDensity: VisualDensity.compact,
                  onPressed: _redoStack.isNotEmpty ? _redo : null,
                ),

                const SizedBox(
                  height: 18,
                  child: VerticalDivider(color: Colors.white24, width: 12),
                ),

                // 钉在桌面
                IconButton(
                  icon: const Icon(Icons.push_pin_outlined, size: 16),
                  color: Colors.white70,
                  tooltip: '钉在桌面上',
                  visualDensity: VisualDensity.compact,
                  onPressed: _handlePinToDesktop,
                ),

                // 保存到文件
                IconButton(
                  icon: const Icon(Icons.download_rounded, size: 16),
                  color: Colors.white70,
                  tooltip: '保存到本地 (Ctrl+S)',
                  visualDensity: VisualDensity.compact,
                  onPressed: _handleSaveToFile,
                ),

                // 复制到剪贴板
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  color: Colors.white70,
                  tooltip: '复制到剪贴板 (Ctrl+C)',
                  visualDensity: VisualDensity.compact,
                  onPressed: _handleCopy,
                ),

                // 取消
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  color: Colors.white70,
                  tooltip: '取消 (Esc)',
                  visualDensity: VisualDensity.compact,
                  onPressed: _handleCancel,
                ),

                const SizedBox(width: 4),

                // 完成 / 发送 (微信经典绿底打勾)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF07C160),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    minimumSize: const Size(60, 30),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text(
                    '发送',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  onPressed: _confirmAndSend,
                ),
              ],
            ),
          ),
        ],
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
        });
      },
    );
  }

  Widget _buildStrokeButton({required String label, required double width}) {
    final isSel = (_selectedStrokeWidth - width).abs() < 0.2;
    return GestureDetector(
      onTap: () => setState(() => _selectedStrokeWidth = width),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: isSel ? Colors.white24 : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSel ? Colors.white : Colors.white60,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

/// 截图全屏底层画布绘制器 (包含暗色遮罩挖空、8 锚点、选区尺寸提示与实时涂鸦)
class _ScreenCaptureCanvasPainter extends CustomPainter {
  _ScreenCaptureCanvasPainter({
    required this.baseImage,
    required this.cropRect,
    required this.phase,
    required this.annotations,
    required this.currentTool,
    required this.toolDragStart,
    required this.toolDragCurrent,
    required this.brushPoints,
    required this.selectedColor,
    required this.strokeWidth,
    required this.mosaicStyle,
    required this.stepNumber,
  });

  final ui.Image? baseImage;
  final Rect? cropRect;
  final _CropPhase phase;
  final List<AnnotationItem> annotations;
  final AnnotationTool currentTool;
  final Offset? toolDragStart;
  final Offset? toolDragCurrent;
  final List<Offset> brushPoints;
  final Color selectedColor;
  final double strokeWidth;
  final MosaicStyle mosaicStyle;
  final int stepNumber;

  @override
  void paint(Canvas canvas, Size size) {
    // 1. 绘制底层屏幕原图
    if (baseImage != null) {
      final src = Rect.fromLTWH(
        0,
        0,
        baseImage!.width.toDouble(),
        baseImage!.height.toDouble(),
      );
      final dst = Offset.zero & size;
      canvas.drawImageRect(baseImage!, src, dst, Paint());
    }

    // 2. 绘制半透明黑色遮罩 (使用 saveLayer + BlendMode.clear 挖空选区)
    final layerPaint = Paint();
    canvas.saveLayer(Offset.zero & size, layerPaint);

    final maskPaint =
        Paint()
          ..color = Colors.black.withValues(
            alpha: cropRect != null ? 0.40 : 0.28,
          );
    canvas.drawRect(Offset.zero & size, maskPaint);

    if (cropRect != null) {
      final clearPaint = Paint()..blendMode = BlendMode.clear;
      canvas.drawRect(cropRect!, clearPaint);
    }
    canvas.restore();

    // 3. 选区外框与 8 个锚点
    if (cropRect != null) {
      final borderPaint =
          Paint()
            ..color = const Color(0xFF07C160)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0;
      canvas.drawRect(cropRect!, borderPaint);

      // 绘制尺寸提示标签 (位于选区左上方)
      final sizeText =
          '${cropRect!.width.round()} × ${cropRect!.height.round()}';
      final textPainter = TextPainter(
        text: TextSpan(
          text: sizeText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final tagTop =
          cropRect!.top >= 24.0 ? cropRect!.top - 20.0 : cropRect!.bottom + 6.0;
      final tagRect = Rect.fromLTWH(
        cropRect!.left,
        tagTop,
        textPainter.width + 10,
        textPainter.height + 4,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(tagRect, const Radius.circular(3)),
        Paint()..color = Colors.black.withValues(alpha: 0.75),
      );
      textPainter.paint(canvas, Offset(tagRect.left + 5, tagRect.top + 2));

      // 绘制 8 个控制锚点 (白心绿边)
      if (phase == _CropPhase.selected) {
        final handlePaint =
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.fill;
        final handleBorder =
            Paint()
              ..color = const Color(0xFF07C160)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5;

        final handles = [
          cropRect!.topLeft,
          Offset(cropRect!.center.dx, cropRect!.top),
          cropRect!.topRight,
          Offset(cropRect!.right, cropRect!.center.dy),
          cropRect!.bottomRight,
          Offset(cropRect!.center.dx, cropRect!.bottom),
          cropRect!.bottomLeft,
          Offset(cropRect!.left, cropRect!.center.dy),
        ];

        for (final pt in handles) {
          final handleRect = Rect.fromCenter(center: pt, width: 8, height: 8);
          canvas.drawRect(handleRect, handlePaint);
          canvas.drawRect(handleRect, handleBorder);
        }
      }

      // 4. 将标注严格限制在选区内
      canvas.save();
      canvas.clipRect(cropRect!);

      for (final item in annotations) {
        item.paint(canvas, cropRect!.size, baseImage);
      }

      // 5. 绘制当前正在拖拽的标注临时状态
      if (toolDragStart != null && toolDragCurrent != null) {
        final dragRect = Rect.fromPoints(toolDragStart!, toolDragCurrent!);
        final previewPaint =
            Paint()
              ..color = selectedColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeWidth;

        switch (currentTool) {
          case AnnotationTool.rectangle:
            canvas.drawRect(dragRect, previewPaint);
            break;
          case AnnotationTool.circle:
            canvas.drawOval(dragRect, previewPaint);
            break;
          case AnnotationTool.arrow:
            final item = ArrowAnnotationItem(
              start: toolDragStart!,
              end: toolDragCurrent!,
              color: selectedColor,
              strokeWidth: strokeWidth,
            );
            item.paint(canvas, cropRect!.size, baseImage);
            break;
          case AnnotationTool.brush:
            if (brushPoints.length >= 2) {
              final item = BrushAnnotationItem(
                points: brushPoints,
                color: selectedColor,
                strokeWidth: strokeWidth,
              );
              item.paint(canvas, cropRect!.size, baseImage);
            }
            break;
          case AnnotationTool.highlighter:
            if (brushPoints.length >= 2) {
              final item = HighlighterAnnotationItem(
                points: brushPoints,
                color: selectedColor,
                strokeWidth: strokeWidth * 4.0,
              );
              item.paint(canvas, cropRect!.size, baseImage);
            }
            break;
          case AnnotationTool.numberBadge:
            final item = NumberBadgeAnnotationItem(
              position: toolDragStart!,
              number: stepNumber,
              color: selectedColor,
              radius: strokeWidth * 3.5 + 4.0,
            );
            item.paint(canvas, cropRect!.size, baseImage);
            break;
          case AnnotationTool.mosaic:
            final item = MosaicAnnotationItem(
              rect: dragRect,
              style: mosaicStyle,
              blockSize: strokeWidth * 3.0 + 4.0,
            );
            item.paint(canvas, cropRect!.size, baseImage);
            break;
          case AnnotationTool.text:
          case AnnotationTool.none:
            break;
        }
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ScreenCaptureCanvasPainter oldDelegate) => true;
}
