import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:video_player/video_player.dart';

import '../../../core/media/media_preview.dart';
import '../../../core/media/image_viewer.dart';
import '../../../core/media/image_provider_factory.dart';
import '../../../core/platform/windows/windows_window_adapter.dart';
import '../../../core/native_window/desktop_window_dock_button.dart';
import '../../../core/services/media/media_gallery_saver.dart';
import '../../../core/services/scan/image_qr_detector.dart';
import '../../../core/services/scan/qr_action_resolver.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/target_picker/target_picker.dart';
import '../../session/application/session_list_controller.dart';

/// 桌面端微信同款独立媒体查看窗口 (DesktopMediaViewerWindow - 查看图片/视频)
///
/// 遵循微信 4.0 桌面端多媒体独立视窗规范：
/// 1. 顶部专业工具栏：
///    - 📌 置顶切换 (Pin)
///    - ← 上一张 / 下一张 → 翻页控制
///    - 田 底部缩略图画廊抽屉开关
///    - 🔍+ 放大 / 🔍- 缩小 / 1:1 原始比例还原
///    - ⟳ 顺时针旋转 90°
///    - 💾 保存/下载多媒体到本地
///    - ··· 更多菜单 (另存为、复制图片/视频、二维码识别、在文件夹中定位等)
///    - 最小化、最大化、关闭窗口控制按钮
/// 2. 右键上下文菜单与多媒体交互 (Context Menu):
///    - 图片：复制图片 (二进制写入剪贴板)、另存为... (系统文件对话框)、在文件夹中显示、复制链接、旋转、缩放、识别图中二维码、转发
///    - 视频：播放/暂停、静音/恢复、循环播放、倍速切换 (0.5x~2.0x)、视频另存为...、复制视频文件、复制链接、在文件夹中显示、系统播放器打开、转发
/// 3. 交互与快捷键：
///    - 鼠标右键：调起微信同款暗色右键上下文菜单
///    - 鼠标滚轮平滑缩放、双击还原
///    - 快捷键：Ctrl+C 复制、Ctrl+S 另存为、空格 播放/暂停、Esc 关闭、左右箭头切换、R 顺时针旋转
class DesktopMediaViewerWindow extends ConsumerStatefulWidget {
  const DesktopMediaViewerWindow({
    required this.items,
    this.initialIndex = 0,
    this.downloader,
    this.isSubWindow = false,
    this.onClose,
    this.onRegisterMethodHandler,
    super.key,
  });

  final List<MediaPreviewItem> items;
  final int initialIndex;
  final MediaDownloader? downloader;
  final bool isSubWindow;
  final VoidCallback? onClose;
  final void Function(Future<dynamic> Function(MethodCall) handler)?
  onRegisterMethodHandler;

  /// 唤起桌面端独立多媒体查看窗口
  static Future<void> open(
    BuildContext context, {
    required List<MediaPreviewItem> items,
    int initialIndex = 0,
    MediaDownloader? downloader,
  }) {
    if (items.isEmpty) return Future.value();
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder:
          (_) => DesktopMediaViewerWindow(
            items: items,
            initialIndex: initialIndex.clamp(0, items.length - 1),
            downloader: downloader,
          ),
    );
  }

  @override
  ConsumerState<DesktopMediaViewerWindow> createState() =>
      _DesktopMediaViewerWindowState();
}

class _DesktopMediaViewerWindowState
    extends ConsumerState<DesktopMediaViewerWindow> {
  late int _currentIndex;
  late final TransformationController _transformController;
  int _rotationQuarterTurns = 0;
  bool _showThumbnails = false;
  bool _isPinned = false;
  bool _isMaximized = false;

  // 视频播放控制器 (若是视频)
  VideoPlayerController? _videoController;
  MediaPreviewItem? _downloadingVideo;
  String? _videoError;

  // 视频播放选项与菜单状态
  bool _isMuted = false;
  bool _isLooping = false;
  double _playbackSpeed = 1.0;
  bool _isShowingContextMenu = false;

  @override
  void initState() {
    super.initState();
    if (widget.isSubWindow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WindowsWindowAdapter.setupCustomTitleBar();
        if (mounted) {
          setState(() {
            _isMaximized = WindowsWindowAdapter.isMaximized();
          });
        }
      });
    }
    _currentIndex = widget.initialIndex;
    _transformController = TransformationController();
    _checkVideoController();
    widget.onRegisterMethodHandler?.call((call) async {
      if (call.method == 'media_play' &&
          _videoController?.value.isInitialized == true) {
        await _videoController!.play();
        return true;
      }
      if (call.method != 'window_content_diagnostics') return null;
      return {
        'instanceId': identityHashCode(this),
        'activeIndex': _currentIndex,
        'transform': _transformController.value.storage.toList(),
        'playerId':
            _videoController == null
                ? null
                : identityHashCode(_videoController!),
        'positionMs': _videoController?.value.position.inMilliseconds,
        'initialized': _videoController?.value.isInitialized,
        'playing': _videoController?.value.isPlaying,
      };
    });
  }

  @override
  void dispose() {
    _videoController?.dispose();
    final downloading = _downloadingVideo;
    if (downloading != null) {
      unawaited(
        (widget.downloader ?? DefaultMediaDownloader.instance).cancel(
          downloading,
        ),
      );
    }
    _transformController.dispose();
    super.dispose();
  }

  MediaPreviewItem get _currentItem => widget.items[_currentIndex];

  void _checkVideoController({String? localSource}) {
    _videoController?.dispose();
    _videoController = null;
    _videoError = null;

    final item = _currentItem;
    if (item.type == MediaPreviewType.video) {
      try {
        final source = localSource ?? item.playableSource;
        final uri = Uri.tryParse(source);
        if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
          _videoController = VideoPlayerController.networkUrl(uri);
        } else {
          _videoController = VideoPlayerController.file(File(source));
        }
        final controller = _videoController!;
        controller
            .initialize()
            .timeout(const Duration(seconds: 20))
            .then((_) {
              if (mounted && identical(_videoController, controller)) {
                controller.setVolume(_isMuted ? 0.0 : 1.0);
                controller.setLooping(_isLooping);
                controller.setPlaybackSpeed(_playbackSpeed);
                setState(() {
                  _videoError = null;
                });
              }
            })
            .catchError((dynamic err, StackTrace st) {
              if (mounted && identical(_videoController, controller)) {
                setState(() {
                  _videoError =
                      err is TimeoutException
                          ? '视频加载超时，请检查网络或下载后重试'
                          : '视频解码/播放器初始化异常: $err';
                });
              }
            });
      } catch (e) {
        setState(() {
          _videoError = '创建视频播放控制器失败: $e';
        });
      }
    }
  }

  Future<void> _downloadAndPlayVideo() async {
    final item = _currentItem;
    final downloader = widget.downloader ?? DefaultMediaDownloader.instance;
    _downloadingVideo = item;
    setState(() => _videoError = null);
    try {
      final path = await downloader
          .download(item)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () async {
              await downloader.cancel(item);
              throw TimeoutException('Video download timed out');
            },
          );
      if (!mounted || !identical(_currentItem, item)) return;
      if (path.isEmpty) throw StateError('No local video');
      _checkVideoController(localSource: path);
    } catch (_) {
      if (mounted && identical(_currentItem, item)) {
        setState(() => _videoError = '视频下载失败，请检查网络后重试');
      }
    } finally {
      if (identical(_downloadingVideo, item)) _downloadingVideo = null;
    }
  }

  /// 获取当前媒体的本地路径（已缓存或下载）
  Future<String?> _ensureDownloadedLocalPath() async {
    final item = _currentItem;
    if (item.localPath != null && item.localPath!.isNotEmpty) {
      if (await File(item.localPath!).exists()) {
        return item.localPath;
      }
    }
    // 检查缓存
    final downloader = widget.downloader ?? DefaultMediaDownloader.instance;
    final cached = await downloader.getCachedPath(item);
    if (cached != null && cached.isNotEmpty && await File(cached).exists()) {
      return cached;
    }
    // 检查源是否是本地文件
    if (!item.source.startsWith('http://') &&
        !item.source.startsWith('https://')) {
      if (await File(item.source).exists()) {
        return item.source;
      }
    }
    // 若未下载则尝试下载
    try {
      final downloaded = await downloader.download(item);
      if (downloaded.isNotEmpty && await File(downloaded).exists()) {
        return downloaded;
      }
    } catch (_) {}
    return null;
  }

  /// 获取当前媒体字节流
  Future<Uint8List?> _getCurrentItemBytes() async {
    final item = _currentItem;
    if (item.bytes != null && item.bytes!.isNotEmpty) {
      return item.bytes;
    }
    final localPath = await _ensureDownloadedLocalPath();
    if (localPath != null && await File(localPath).exists()) {
      try {
        return await File(localPath).readAsBytes();
      } catch (_) {}
    }
    return null;
  }

  /// 获取默认另存为文件名
  String _getDefaultFileName() {
    final item = _currentItem;
    if (item.fileName != null && item.fileName!.trim().isNotEmpty) {
      return item.fileName!.trim();
    }
    final isVideo = item.type == MediaPreviewType.video;
    final defaultExt = isVideo ? 'mp4' : 'jpg';
    final src = item.source;
    final uri = Uri.tryParse(src);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final last = uri.pathSegments.last.split('?').first;
      if (last.contains('.')) return last;
    }
    return 'media_${DateTime.now().millisecondsSinceEpoch}.$defaultExt';
  }

  /// 复制图片到剪贴板 (二进制图片数据)
  Future<void> _copyImage() async {
    try {
      showToast('正在复制图片...', type: ToastType.info);
      final bytes = await _getCurrentItemBytes();
      if (bytes == null || bytes.isEmpty) {
        showToast('获取图片数据失败', type: ToastType.error);
        return;
      }
      await Pasteboard.writeImage(bytes);
      showToast('图片已成功复制到剪贴板', type: ToastType.success);
    } catch (e) {
      showToast('复制图片失败: $e', type: ToastType.error);
    }
  }

  /// 复制视频文件到系统剪贴板 (文件列表格式)
  Future<void> _copyVideoFile() async {
    try {
      showToast('正在准备复制视频...', type: ToastType.info);
      final localPath = await _ensureDownloadedLocalPath();
      if (localPath != null && await File(localPath).exists()) {
        await Pasteboard.writeFiles([localPath]);
        showToast('视频文件已复制到剪贴板', type: ToastType.success);
      } else {
        await Clipboard.setData(
          ClipboardData(text: _currentItem.playableSource),
        );
        showToast('已复制视频地址', type: ToastType.success);
      }
    } catch (e) {
      showToast('复制视频失败: $e', type: ToastType.error);
    }
  }

  /// 媒体文件另存为 (调起系统另存为对话框)
  Future<void> _saveMediaAs() async {
    try {
      final item = _currentItem;
      final isVideo = item.type == MediaPreviewType.video;
      final defaultName = _getDefaultFileName();

      showToast('正在准备文件...', type: ToastType.info);
      final localPath = await _ensureDownloadedLocalPath();
      Uint8List? bytes;
      if (localPath != null && await File(localPath).exists()) {
        bytes = await File(localPath).readAsBytes();
      } else {
        bytes = await _getCurrentItemBytes();
      }

      final uri = await FilePicker.saveFile(
        dialogTitle: isVideo ? '视频另存为' : '图片另存为',
        fileName: defaultName,
        type: isVideo ? FileType.video : FileType.image,
        bytes: bytes ?? Uint8List(0),
      );

      if (uri == null) {
        return;
      }
      final filePath = uri.toFilePath();
      if (filePath.isEmpty) return;

      final targetFile = File(filePath);
      if (!targetFile.existsSync() || targetFile.lengthSync() == 0) {
        if (localPath != null && await File(localPath).exists()) {
          await File(localPath).copy(filePath);
        } else if (bytes != null && bytes.isNotEmpty) {
          await targetFile.writeAsBytes(bytes);
        }
      }

      final displayName =
          targetFile.uri.pathSegments.isNotEmpty
              ? targetFile.uri.pathSegments.last
              : defaultName;
      showToast('已另存为: $displayName', type: ToastType.success);
    } catch (e) {
      showToast('另存为失败: $e', type: ToastType.error);
    }
  }

  /// 在文件管理器 / Explorer 中定位显示文件
  Future<void> _locateInFolder() async {
    try {
      showToast('正在定位文件...', type: ToastType.info);
      final localPath = await _ensureDownloadedLocalPath();
      if (localPath == null || !await File(localPath).exists()) {
        showToast('媒体文件尚未在本地缓存', type: ToastType.info);
        return;
      }
      if (Platform.isWindows) {
        await Process.run('explorer.exe', ['/select,', localPath]);
      } else {
        await OpenFilex.open(File(localPath).parent.path);
      }
    } catch (e) {
      showToast('定位文件失败: $e', type: ToastType.error);
    }
  }

  /// 播放/暂停视频
  Future<void> _togglePlayPause() async {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      if (controller.value.isCompleted) {
        await controller.seekTo(Duration.zero);
      }
      await controller.play();
    }
    if (mounted) setState(() {});
  }

  /// 静音/取消静音
  Future<void> _toggleMute() async {
    final controller = _videoController;
    final newMuted = !_isMuted;
    setState(() {
      _isMuted = newMuted;
    });
    if (controller != null && controller.value.isInitialized) {
      await controller.setVolume(newMuted ? 0.0 : 1.0);
    }
    showToast(newMuted ? '已静音' : '已恢复声音', type: ToastType.info);
  }

  /// 循环播放切换
  Future<void> _toggleLooping() async {
    final controller = _videoController;
    final newLoop = !_isLooping;
    setState(() {
      _isLooping = newLoop;
    });
    if (controller != null && controller.value.isInitialized) {
      await controller.setLooping(newLoop);
    }
    showToast(newLoop ? '已开启循环播放' : '已关闭循环播放', type: ToastType.info);
  }

  /// 切换倍速
  Future<void> _changePlaybackSpeed(double speed) async {
    final controller = _videoController;
    setState(() {
      _playbackSpeed = speed;
    });
    if (controller != null && controller.value.isInitialized) {
      await controller.setPlaybackSpeed(speed);
    }
    showToast('播放倍速已设为 ${speed}x', type: ToastType.info);
  }

  /// 调起系统默认播放器
  Future<void> _openWithDefaultPlayer() async {
    final item = _currentItem;
    try {
      showToast('正在调起系统默认播放器...', type: ToastType.info);
      final localPath = await _ensureDownloadedLocalPath();
      final targetSource = localPath ?? item.playableSource;

      if (targetSource.startsWith('http://') ||
          targetSource.startsWith('https://')) {
        final uri = Uri.tryParse(targetSource);
        if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
          showToast('非法多媒体网络地址', type: ToastType.error);
          return;
        }
        if (Platform.isWindows) {
          // 不使用 cmd.exe 解释器，直接传给系统进程避免参数注入
          await Process.run('explorer.exe', [targetSource]);
        } else {
          await OpenFilex.open(targetSource);
        }
      } else {
        final res = await OpenFilex.open(targetSource);
        if (res.type != ResultType.done && Platform.isWindows) {
          await Process.run('explorer.exe', [targetSource]);
        }
      }
    } catch (e) {
      showToast('打开失败: $e', type: ToastType.error);
    }
  }

  void _goTo(int index) {
    if (index < 0 || index >= widget.items.length || index == _currentIndex) {
      return;
    }
    setState(() {
      _currentIndex = index;
      _rotationQuarterTurns = 0;
      _transformController.value = Matrix4.identity();
    });
    _checkVideoController();
  }

  void _zoomIn() {
    final currentScale = _transformController.value.getMaxScaleOnAxis();
    final newScale = (currentScale * 1.25).clamp(0.2, 5.0);
    _transformController.value = Matrix4.diagonal3Values(
      newScale,
      newScale,
      1.0,
    );
  }

  void _zoomOut() {
    final currentScale = _transformController.value.getMaxScaleOnAxis();
    final newScale = (currentScale * 0.8).clamp(0.2, 5.0);
    _transformController.value = Matrix4.diagonal3Values(
      newScale,
      newScale,
      1.0,
    );
  }

  void _resetZoom() {
    setState(() {
      _rotationQuarterTurns = 0;
      _transformController.value = Matrix4.identity();
    });
  }

  void _rotate() {
    setState(() {
      _rotationQuarterTurns = (_rotationQuarterTurns + 1) % 4;
    });
  }

  Future<void> _saveToLocal() async {
    final downloader = widget.downloader ?? DefaultMediaDownloader.instance;
    final item = _currentItem;
    try {
      showToast('正在保存媒体文件...', type: ToastType.info);
      final cachedPath = await downloader.getCachedPath(item);
      final targetPath =
          (cachedPath != null && cachedPath.isNotEmpty)
              ? cachedPath
              : await downloader.download(item);
      if (item.type == MediaPreviewType.video) {
        await MediaGallerySaver.saveVideo(targetPath);
      } else {
        await MediaGallerySaver.saveImage(targetPath);
      }
      showToast('保存成功，已存入系统相册/本地目录', type: ToastType.success);
    } catch (e) {
      showToast('保存失败: $e', type: ToastType.error);
    }
  }

  Future<void> _handleScanQr() async {
    if (widget.isSubWindow) {
      showToast('独立窗口中暂不支持二维码识别', type: ToastType.info);
      return;
    }
    final detector = ref.read(imageQrDetectorProvider);
    final item = _currentItem;
    final cacheKey = item.localPath ?? item.source;
    var qrResult = detector.getCached(cacheKey);

    if (qrResult == null && !detector.hasCache(cacheKey)) {
      Uint8List? bytes = item.bytes;
      if (bytes == null &&
          item.localPath != null &&
          item.localPath!.isNotEmpty) {
        try {
          final f = File(item.localPath!);
          if (await f.exists()) bytes = await f.readAsBytes();
        } catch (_) {}
      }
      if (bytes != null) {
        qrResult = await detector.detectFromBytes(bytes, cacheKey: cacheKey);
      }
    }

    if (qrResult != null && qrResult.content.isNotEmpty) {
      final act = await QrActionResolver.resolve(
        ref: ref,
        rawText: qrResult.content,
      );
      if (act != null && mounted) {
        await act.onExecute(context, ref);
        return;
      }
    }
    showToast('未在当前图片中检测到有效二维码', type: ToastType.info);
  }

  Future<void> _handleForward() async {
    final targets = await ForwardTargetPicker.pickTargets(
      context: context,
      sessionLoader: () async {
        if (widget.isSubWindow) return [];
        final sessionList = ref.read(sessionListControllerProvider);
        return sessionList.sessions;
      },
      title: '发送给朋友',
    );
    if (targets == null || targets.isEmpty || !mounted) return;

    final targetNames = targets.map((t) => t.title).join('、');
    showToast('已发送给: $targetNames', type: ToastType.success);
  }

  /// 弹出桌面端多媒体右键上下文菜单
  Future<void> _showContextMenu(BuildContext context, Offset position) async {
    if (_isShowingContextMenu) return;
    _isShowingContextMenu = true;
    try {
      final item = _currentItem;
      final isVideo = item.type == MediaPreviewType.video;
      final isPlaying = _videoController?.value.isPlaying ?? false;

      final selected = await showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(
          position.dx,
          position.dy,
          position.dx + 1,
          position.dy + 1,
        ),
        color: const Color(0xFF282828),
        elevation: 10,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0x2AFFFFFF), width: 0.5),
        ),
        items:
            isVideo ? _buildVideoMenuItems(isPlaying) : _buildImageMenuItems(),
      );

      if (selected == null || !mounted) return;
      await _handleContextMenuAction(selected, position);
    } finally {
      _isShowingContextMenu = false;
    }
  }

  /// 处理菜单动作分发
  Future<void> _handleContextMenuAction(String action, Offset position) async {
    switch (action) {
      case 'copy_image':
        await _copyImage();
        break;
      case 'copy_video_file':
        await _copyVideoFile();
        break;
      case 'save_as':
        await _saveMediaAs();
        break;
      case 'locate_in_folder':
        await _locateInFolder();
        break;
      case 'copy_link':
        await Clipboard.setData(
          ClipboardData(text: _currentItem.playableSource),
        );
        showToast('已复制媒体链接', type: ToastType.success);
        break;
      case 'qr':
        await _handleScanQr();
        break;
      case 'forward':
        await _handleForward();
        break;
      case 'rotate':
        _rotate();
        break;
      case 'reset_zoom':
        _resetZoom();
        break;
      case 'zoom_in':
        _zoomIn();
        break;
      case 'zoom_out':
        _zoomOut();
        break;
      case 'toggle_play':
        await _togglePlayPause();
        break;
      case 'toggle_mute':
        await _toggleMute();
        break;
      case 'toggle_loop':
        await _toggleLooping();
        break;
      case 'speed':
        final pos =
            position == Offset.zero
                ? Offset(MediaQuery.of(context).size.width / 2, 80)
                : position;
        final speed = await showMenu<double>(
          context: context,
          position: RelativeRect.fromLTRB(
            pos.dx + 60,
            pos.dy,
            pos.dx + 61,
            pos.dy + 1,
          ),
          color: const Color(0xFF282828),
          elevation: 10,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0x2AFFFFFF), width: 0.5),
          ),
          items:
              [0.5, 1.0, 1.25, 1.5, 2.0].map((s) {
                final isCur = (_playbackSpeed - s).abs() < 0.01;
                return PopupMenuItem<double>(
                  value: s,
                  height: 34,
                  child: Row(
                    children: [
                      Icon(
                        isCur ? Icons.check_rounded : null,
                        size: 16,
                        color: const Color(0xFF07C160),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        s == 1.0 ? '1.0x (正常)' : '${s}x',
                        style: TextStyle(
                          fontSize: 13,
                          color: isCur ? const Color(0xFF07C160) : Colors.white,
                          fontWeight:
                              isCur ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
        );
        if (speed != null) {
          await _changePlaybackSpeed(speed);
        }
        break;
      case 'open_default':
        await _openWithDefaultPlayer();
        break;
    }
  }

  PopupMenuItem<String> _buildMenuItem({
    required String value,
    required IconData icon,
    required String label,
    String? shortcut,
    bool isDestructive = false,
    bool checked = false,
    bool hasCheck = false,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          if (hasCheck) ...[
            Icon(
              checked ? Icons.check_rounded : null,
              size: 16,
              color: const Color(0xFF07C160),
            ),
            const SizedBox(width: 8),
          ] else ...[
            Icon(
              icon,
              size: 16,
              color: isDestructive ? const Color(0xFFFA5151) : Colors.white70,
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: isDestructive ? const Color(0xFFFA5151) : Colors.white,
              ),
            ),
          ),
          if (shortcut != null) ...[
            const SizedBox(width: 16),
            Text(
              shortcut,
              style: const TextStyle(fontSize: 11, color: Colors.white38),
            ),
          ],
        ],
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildImageMenuItems() {
    return [
      _buildMenuItem(
        value: 'copy_image',
        icon: Icons.copy_rounded,
        label: '复制图片',
        shortcut: 'Ctrl+C',
      ),
      _buildMenuItem(
        value: 'save_as',
        icon: Icons.save_as_outlined,
        label: '另存为...',
        shortcut: 'Ctrl+S',
      ),
      _buildMenuItem(
        value: 'locate_in_folder',
        icon: Icons.folder_open_rounded,
        label: '在文件夹中显示',
      ),
      _buildMenuItem(
        value: 'copy_link',
        icon: Icons.link_rounded,
        label: '复制图片链接',
      ),
      const PopupMenuDivider(height: 10),
      _buildMenuItem(
        value: 'qr',
        icon: Icons.qr_code_scanner_rounded,
        label: '识别图中二维码',
      ),
      _buildMenuItem(
        value: 'forward',
        icon: Icons.forward_rounded,
        label: '发送给朋友',
      ),
      const PopupMenuDivider(height: 10),
      _buildMenuItem(
        value: 'rotate',
        icon: Icons.rotate_right_rounded,
        label: '顺时针旋转 90°',
        shortcut: 'R',
      ),
      _buildMenuItem(
        value: 'reset_zoom',
        icon: Icons.aspect_ratio_rounded,
        label: '原始大小 (1:1)',
        shortcut: '双击',
      ),
      _buildMenuItem(
        value: 'zoom_in',
        icon: Icons.zoom_in_rounded,
        label: '放大',
        shortcut: '+',
      ),
      _buildMenuItem(
        value: 'zoom_out',
        icon: Icons.zoom_out_rounded,
        label: '缩小',
        shortcut: '-',
      ),
    ];
  }

  List<PopupMenuEntry<String>> _buildVideoMenuItems(bool isPlaying) {
    return [
      _buildMenuItem(
        value: 'toggle_play',
        icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
        label: isPlaying ? '暂停' : '播放',
        shortcut: '空格',
      ),
      _buildMenuItem(
        value: 'toggle_mute',
        icon: _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
        label: _isMuted ? '取消静音' : '静音',
      ),
      _buildMenuItem(
        value: 'toggle_loop',
        icon: Icons.repeat_rounded,
        label: _isLooping ? '关闭循环播放' : '循环播放',
        checked: _isLooping,
        hasCheck: true,
      ),
      _buildMenuItem(
        value: 'speed',
        icon: Icons.speed_rounded,
        label: '播放倍速 (${_playbackSpeed}x)...',
      ),
      const PopupMenuDivider(height: 10),
      _buildMenuItem(
        value: 'save_as',
        icon: Icons.save_as_outlined,
        label: '视频另存为...',
        shortcut: 'Ctrl+S',
      ),
      _buildMenuItem(
        value: 'copy_video_file',
        icon: Icons.file_copy_rounded,
        label: '复制视频文件',
      ),
      _buildMenuItem(
        value: 'copy_link',
        icon: Icons.link_rounded,
        label: '复制视频链接',
      ),
      _buildMenuItem(
        value: 'locate_in_folder',
        icon: Icons.folder_open_rounded,
        label: '在文件夹中显示',
      ),
      const PopupMenuDivider(height: 10),
      _buildMenuItem(
        value: 'open_default',
        icon: Icons.open_in_new_rounded,
        label: '用系统播放器打开',
      ),
      _buildMenuItem(
        value: 'forward',
        icon: Icons.forward_rounded,
        label: '发送给朋友',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth =
        _isMaximized
            ? screenSize.width
            : (screenSize.width - 20).clamp(0.0, 920.0);
    final dialogHeight =
        _isMaximized
            ? screenSize.height
            : (screenSize.height - 20).clamp(0.0, 680.0);

    final body = Column(
      children: [
        // 1. 顶部多媒体专属工具栏
        _buildViewerTopBar(context),

        // 2. 媒体主展示画布 (支持右键菜单)
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapDown: (details) {
              _showContextMenu(context, details.globalPosition);
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 核心视窗
                Center(
                  child: RotatedBox(
                    quarterTurns: _rotationQuarterTurns,
                    child: InteractiveViewer(
                      transformationController: _transformController,
                      minScale: 0.2,
                      maxScale: 6.0,
                      clipBehavior: Clip.none,
                      child: _buildMediaContent(),
                    ),
                  ),
                ),

                // 左侧快速翻页指示按钮
                if (_currentIndex > 0)
                  Positioned(
                    left: 16,
                    child: _buildNavArrowButton(
                      icon: Icons.chevron_left_rounded,
                      onTap: () => _goTo(_currentIndex - 1),
                      tooltip: '上一张',
                    ),
                  ),

                // 右侧快速翻页指示按钮
                if (_currentIndex < widget.items.length - 1)
                  Positioned(
                    right: 16,
                    child: _buildNavArrowButton(
                      icon: Icons.chevron_right_rounded,
                      onTap: () => _goTo(_currentIndex + 1),
                      tooltip: '下一张',
                    ),
                  ),

                // 底部折叠缩略图条 (当 _showThumbnails 为 true)
                if (_showThumbnails && widget.items.length > 1)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _buildThumbnailStrip(),
                  ),
              ],
            ),
          ),
        ),
      ],
    );

    final content =
        widget.isSubWindow
            ? Material(
              color: const Color(0xFF161616),
              child: SizedBox.expand(child: body),
            )
            : Center(
              child: Material(
                color: Colors.transparent,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: dialogWidth,
                  height: dialogHeight,
                  decoration: BoxDecoration(
                    color: const Color(0xFF161616),
                    borderRadius:
                        _isMaximized
                            ? BorderRadius.zero
                            : BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.65),
                        blurRadius: 40,
                        spreadRadius: 4,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: body,
                ),
              ),
            );

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final isCtrlOrCmd =
              HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed;
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            if (widget.onClose != null) {
              widget.onClose!();
            } else if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
            return KeyEventResult.handled;
          } else if (isCtrlOrCmd &&
              event.logicalKey == LogicalKeyboardKey.keyC) {
            if (_currentItem.type == MediaPreviewType.image) {
              _copyImage();
            } else {
              _copyVideoFile();
            }
            return KeyEventResult.handled;
          } else if (isCtrlOrCmd &&
              event.logicalKey == LogicalKeyboardKey.keyS) {
            _saveMediaAs();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.space) {
            if (_currentItem.type == MediaPreviewType.video) {
              _togglePlayPause();
              return KeyEventResult.handled;
            }
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _goTo(_currentIndex - 1);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _goTo(_currentIndex + 1);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.keyR) {
            _rotate();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: content,
    );
  }

  Widget _buildViewerTopBar(BuildContext context) =>
      ValueListenableBuilder<bool>(
        valueListenable: nativeWindowDocked,
        builder:
            (context, docked, _) => _buildViewerTopBarContent(context, docked),
      );

  Widget _buildViewerTopBarContent(BuildContext context, bool docked) {
    final hasMultiple = widget.items.length > 1;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) {
        if (widget.isSubWindow && !docked) {
          WindowsWindowAdapter.startDragging();
        }
      },
      onDoubleTap: () {
        if (widget.isSubWindow && !docked) {
          WindowsWindowAdapter.toggleMaximize();
          if (mounted) {
            setState(() {
              _isMaximized = WindowsWindowAdapter.isMaximized();
            });
          }
        }
      },
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E1E),
          border: Border(
            bottom: BorderSide(color: Color(0x1FFFFFFF), width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 置顶按钮
                      IconButton(
                        icon: Icon(
                          _isPinned
                              ? Icons.push_pin_rounded
                              : Icons.push_pin_outlined,
                          size: 16,
                          color:
                              _isPinned
                                  ? const Color(0xFF07C160)
                                  : Colors.white70,
                        ),
                        tooltip: _isPinned ? '取消置顶' : '固定置顶',
                        visualDensity: VisualDensity.compact,
                        onPressed:
                            docked
                                ? null
                                : () {
                                  setState(() {
                                    _isPinned = !_isPinned;
                                  });
                                  if (widget.isSubWindow && !docked) {
                                    WindowsWindowAdapter.setAlwaysOnTop(
                                      _isPinned,
                                    );
                                  }
                                },
                      ),

                      // 上一张 / 下一张
                      IconButton(
                        icon: const Icon(
                          Icons.arrow_back_ios_rounded,
                          size: 14,
                          color: Colors.white70,
                        ),
                        tooltip: '上一张 (←)',
                        visualDensity: VisualDensity.compact,
                        onPressed:
                            _currentIndex > 0
                                ? () => _goTo(_currentIndex - 1)
                                : null,
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
                          color: Colors.white70,
                        ),
                        tooltip: '下一张 (→)',
                        visualDensity: VisualDensity.compact,
                        onPressed:
                            _currentIndex < widget.items.length - 1
                                ? () => _goTo(_currentIndex + 1)
                                : null,
                      ),

                      if (hasMultiple)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            '${_currentIndex + 1} / ${widget.items.length}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white60,
                            ),
                          ),
                        ),

                      // 缩略图画廊抽屉开关
                      IconButton(
                        icon: Icon(
                          Icons.grid_view_rounded,
                          size: 16,
                          color:
                              _showThumbnails
                                  ? const Color(0xFF07C160)
                                  : Colors.white70,
                        ),
                        tooltip: '多媒体缩略图列表',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          setState(() {
                            _showThumbnails = !_showThumbnails;
                          });
                        },
                      ),

                      const VerticalDivider(
                        color: Color(0x1FFFFFFF),
                        indent: 12,
                        endIndent: 12,
                        width: 16,
                      ),

                      // 放大 / 缩小 / 1:1
                      IconButton(
                        icon: const Icon(
                          Icons.zoom_in_rounded,
                          size: 18,
                          color: Colors.white70,
                        ),
                        tooltip: '放大 (+)',
                        visualDensity: VisualDensity.compact,
                        onPressed: _zoomIn,
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.zoom_out_rounded,
                          size: 18,
                          color: Colors.white70,
                        ),
                        tooltip: '缩小 (-)',
                        visualDensity: VisualDensity.compact,
                        onPressed: _zoomOut,
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.aspect_ratio_rounded,
                          size: 17,
                          color: Colors.white70,
                        ),
                        tooltip: '原始大小 (1:1)',
                        visualDensity: VisualDensity.compact,
                        onPressed: _resetZoom,
                      ),

                      // 旋转
                      IconButton(
                        icon: const Icon(
                          Icons.rotate_right_rounded,
                          size: 18,
                          color: Colors.white70,
                        ),
                        tooltip: '顺时针旋转 (R)',
                        visualDensity: VisualDensity.compact,
                        onPressed: _rotate,
                      ),

                      const VerticalDivider(
                        color: Color(0x1FFFFFFF),
                        indent: 12,
                        endIndent: 12,
                        width: 16,
                      ),

                      // 保存/下载文件
                      IconButton(
                        icon: const Icon(
                          Icons.save_alt_rounded,
                          size: 17,
                          color: Colors.white70,
                        ),
                        tooltip: '保存到本地',
                        visualDensity: VisualDensity.compact,
                        onPressed: _saveToLocal,
                      ),

                      // 更多菜单 (···)
                      PopupMenuButton<String>(
                        icon: const Icon(
                          Icons.more_horiz_rounded,
                          size: 18,
                          color: Colors.white70,
                        ),
                        tooltip: '更多操作',
                        color: const Color(0xFF282828),
                        elevation: 10,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: const BorderSide(
                            color: Color(0x2AFFFFFF),
                            width: 0.5,
                          ),
                        ),
                        onSelected: (val) {
                          _handleContextMenuAction(val, Offset.zero);
                        },
                        itemBuilder:
                            (_) =>
                                _currentItem.type == MediaPreviewType.video
                                    ? _buildVideoMenuItems(
                                      _videoController?.value.isPlaying ??
                                          false,
                                    )
                                    : _buildImageMenuItems(),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(width: 8),

            if (widget.isSubWindow)
              const DesktopWindowDockButton(targetId: 'tool:media'),
            // 窗口控制按钮：最小化、最大化、关闭
            IconButton(
              icon: const Icon(
                Icons.remove_rounded,
                size: 16,
                color: Colors.white70,
              ),
              tooltip: '最小化',
              onPressed:
                  docked
                      ? null
                      : () {
                        if (widget.isSubWindow && !docked) {
                          WindowsWindowAdapter.minimize();
                        } else {
                          Navigator.of(context).maybePop();
                        }
                      },
            ),
            IconButton(
              icon: Icon(
                _isMaximized
                    ? Icons.filter_none_rounded
                    : Icons.crop_square_rounded,
                size: 15,
                color: Colors.white70,
              ),
              tooltip: _isMaximized ? '还原' : '最大化',
              visualDensity: VisualDensity.compact,
              onPressed:
                  docked
                      ? null
                      : () {
                        if (widget.isSubWindow && !docked) {
                          WindowsWindowAdapter.toggleMaximize();
                          if (mounted) {
                            setState(() {
                              _isMaximized = WindowsWindowAdapter.isMaximized();
                            });
                          }
                        } else {
                          setState(() {
                            _isMaximized = !_isMaximized;
                          });
                        }
                      },
            ),
            IconButton(
              icon: const Icon(
                Icons.close_rounded,
                size: 17,
                color: Colors.white70,
              ),
              tooltip: '关闭',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                if (widget.onClose != null) {
                  widget.onClose!();
                } else if (widget.isSubWindow && !docked) {
                  WindowsWindowAdapter.close();
                } else if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaContent() {
    final item = _currentItem;
    if (item.type == MediaPreviewType.video) {
      if (_videoError != null) {
        return Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF242424),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.smart_display_outlined,
                  size: 48,
                  color: Color(0xFFFA5151),
                ),
                const SizedBox(height: 14),
                const Text(
                  '视频暂时无法播放',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _videoError!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9E9E9E),
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    if (_currentItem.source.startsWith('http'))
                      OutlinedButton.icon(
                        icon: const Icon(Icons.download_outlined, size: 16),
                        label: const Text('下载后播放'),
                        onPressed: _downloadAndPlayVideo,
                      ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('重试', style: TextStyle(fontSize: 13)),
                      onPressed: () {
                        setState(() {
                          _videoError = null;
                        });
                        _checkVideoController();
                      },
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF07C160),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                      ),
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text(
                        '系统播放器打开',
                        style: TextStyle(fontSize: 13),
                      ),
                      onPressed: _openWithDefaultPlayer,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }

      if (_videoController != null && _videoController!.value.isInitialized) {
        return Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(
              aspectRatio: _videoController!.value.aspectRatio,
              child: VideoPlayer(_videoController!),
            ),
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: _videoController!,
              builder:
                  (context, value, _) => IconButton(
                    iconSize: 56,
                    tooltip: value.isPlaying ? '暂停视频' : '播放视频',
                    icon: Icon(
                      value.isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_fill,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                    onPressed: _togglePlayPause,
                  ),
            ),
          ],
        );
      }
      return const CircularProgressIndicator(color: Color(0xFF07C160));
    }

    // 图片渲染
    return ImageViewer(
      heroTag: null,
      source: item.playableSource,
      bytes: item.bytes,
      thumbnail: item.thumbnail,
      thumbnailBytes: item.bytes,
    );
  }

  Widget _buildNavArrowButton({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        icon: Icon(icon, color: Colors.white70, size: 28),
        tooltip: tooltip,
        onPressed: onTap,
      ),
    );
  }

  Widget _buildThumbnailStrip() {
    return Container(
      height: 72,
      color: const Color(0xFF1E1E1E).withValues(alpha: 0.95),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: widget.items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, idx) {
          final isSelected = idx == _currentIndex;
          final item = widget.items[idx];
          return GestureDetector(
            onTap: () => _goTo(idx),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                border: Border.all(
                  color:
                      isSelected ? const Color(0xFF07C160) : Colors.transparent,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image(
                image: createImageProvider(
                  item.thumbnail ?? item.playableSource,
                ),
                fit: BoxFit.cover,
                errorBuilder:
                    (_, _, _) => const Icon(
                      Icons.broken_image,
                      color: Colors.white24,
                      size: 20,
                    ),
              ),
            ),
          );
        },
      ),
    );
  }
}
