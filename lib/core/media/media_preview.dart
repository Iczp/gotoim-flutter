import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_navigation.dart';
import '../../features/media/presentation/desktop_media_viewer_window.dart';
import '../../features/session/application/session_list_controller.dart';
import '../services/media/media_gallery_saver.dart';
import '../services/scan/image_qr_detector.dart';
import '../services/scan/qr_action_resolver.dart';
import '../services/window_service.dart';
import '../widgets/app_modal.dart';
import '../widgets/app_toast.dart';
import '../widgets/desktop_dialog.dart';
import '../widgets/target_picker/target_picker.dart';
import 'image_provider_factory.dart';
import 'image_viewer.dart';
import 'media_downloader.dart';
import 'video_viewer.dart';

export 'media_downloader.dart';
export 'video_viewer.dart' show formatMediaDuration, openFloatingVideoWindow;

enum MediaPreviewType { image, video }

@immutable
class MediaPreviewItem {
  const MediaPreviewItem({
    required this.id,
    required this.messageId,
    required this.type,
    required this.source,
    required this.heroTag,
    this.bytes,
    this.thumbnail,
    this.fileName,
    this.localPath,
    this.createdAt,
    this.userId,
    this.chatTarget,
  });
  final String id;
  final String messageId;
  final MediaPreviewType type;
  final String source;
  final Object heroTag;
  final Uint8List? bytes;
  final String? thumbnail;
  /// 下载时使用的文件名（可选）。
  final String? fileName;
  /// 本地已下载文件缓存路径（可选）。
  final String? localPath;
  /// 消息创建日期（用于按日期分类保存附件到 `LocalShare/聊天文件/<用户>/<聊天对象>/<分类>/<yyyy-MM-dd>`）。
  final DateTime? createdAt;
  /// 用户 ID（支持多账号切换隔离）。
  final String? userId;
  /// 聊天对象会话 ID 或名称。
  final String? chatTarget;

  /// 获取优先用于播放或渲染的有效地址。
  /// 若本地已存在有效下载或缓存文件，则直接返回本地文件路径；否则返回远端网络地址。
  String get playableSource {
    if (localPath != null && localPath!.isNotEmpty && !kIsWeb) {
      try {
        if (File(localPath!).existsSync()) return localPath!;
      } catch (_) {}
    }
    return source;
  }

  MediaPreviewItem copyWith({
    String? id,
    String? messageId,
    MediaPreviewType? type,
    String? source,
    Object? heroTag,
    Uint8List? bytes,
    String? thumbnail,
    String? fileName,
    String? localPath,
    DateTime? createdAt,
    String? userId,
    String? chatTarget,
  }) =>
      MediaPreviewItem(
        id: id ?? this.id,
        messageId: messageId ?? this.messageId,
        type: type ?? this.type,
        source: source ?? this.source,
        heroTag: heroTag ?? this.heroTag,
        bytes: bytes ?? this.bytes,
        thumbnail: thumbnail ?? this.thumbnail,
        fileName: fileName ?? this.fileName,
        localPath: localPath ?? this.localPath,
        createdAt: createdAt ?? this.createdAt,
        userId: userId ?? this.userId,
        chatTarget: chatTarget ?? this.chatTarget,
      );
}

String buildMediaHeroTag({
  required String messageId,
  required String mediaId,
}) => 'chat-media-$messageId-$mediaId';

abstract class MediaPreview {
  static Future<void> open(
    BuildContext context, {
    required List<MediaPreviewItem> items,
    int initialIndex = 0,
    MediaDownloader? downloader,
  }) {
    if (items.isEmpty) return Future.value();
    final safeInitialIndex = initialIndex.clamp(0, items.length - 1);
    final isDesktop =
        !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    if (isDesktop) {
      try {
        final container = ProviderScope.containerOf(context, listen: false);
        final windowService = container.read(windowServiceProvider);
        final currentItem = items[safeInitialIndex];
        return windowService.openMediaViewer(
          mediaUrl: currentItem.playableSource,
          title: '媒体预览 - ${currentItem.id}',
          items: items,
          initialIndex: safeInitialIndex,
        );
      } catch (e) {
        debugPrint('[MediaPreview] openMediaViewer fallback to dialog: $e');
      }
      return DesktopMediaViewerWindow.open(
        context,
        items: items,
        initialIndex: safeInitialIndex,
        downloader: downloader,
      );
    }
    final nav =
        Navigator.maybeOf(context, rootNavigator: true) ??
        Navigator.maybeOf(context) ??
        rootNavigatorKey.currentState;
    if (nav == null) return Future.value();
    return openWithNavigator(
      nav,
      items: items,
      initialIndex: safeInitialIndex,
      downloader: downloader,
    );
  }

  static Future<void> openWithNavigator(
    NavigatorState navigator, {
    required List<MediaPreviewItem> items,
    int initialIndex = 0,
    MediaDownloader? downloader,
  }) {
    if (items.isEmpty) return Future.value();
    final safeInitialIndex = initialIndex.clamp(0, items.length - 1);
    return navigator.push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 240),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        pageBuilder:
            (_, animation, secondaryAnimation) =>
                _MediaPreviewPage(
                  items: items,
                  initialIndex: safeInitialIndex,
                  downloader: downloader ?? DefaultMediaDownloader.instance,
                ),
      ),
    );
  }
  static Future<void> showActionSheet(
    BuildContext context, {
    required WidgetRef ref,
    required MediaPreviewItem item,
    MediaDownloader? downloader,
    VoidCallback? onShare,
    VoidCallback? onDownload,
  }) async {
    HapticFeedback.mediumImpact();
    final effectiveDownloader = downloader ?? DefaultMediaDownloader.instance;

    QrParsedAction? qrAction;
    if (item.type == MediaPreviewType.image) {
      final detector = ref.read(imageQrDetectorProvider);
      final cacheKey = item.localPath ?? item.source;
      var qrResult = detector.getCached(cacheKey);

      if (qrResult == null && !detector.hasCache(cacheKey)) {
        Uint8List? bytes = item.bytes;
        if (bytes == null && item.localPath != null && item.localPath!.isNotEmpty) {
          try {
            final f = File(item.localPath!);
            if (await f.exists()) bytes = await f.readAsBytes();
          } catch (_) {}
        }
        if (bytes == null) {
          final cached = await effectiveDownloader.getCachedPath(item);
          if (cached != null) {
            try {
              final f = File(cached);
              if (await f.exists()) bytes = await f.readAsBytes();
            } catch (_) {}
          }
        }
        if (bytes == null &&
            (item.source.startsWith('http://') || item.source.startsWith('https://'))) {
          try {
            final path = await effectiveDownloader.download(item);
            if (path.isNotEmpty) {
              final f = File(path);
              if (await f.exists()) bytes = await f.readAsBytes();
            }
          } catch (_) {}
        }
        if (bytes != null) {
          qrResult = await detector.detectFromBytes(bytes, cacheKey: cacheKey);
        }
      }

      if (qrResult != null && qrResult.content.isNotEmpty) {
        qrAction = await QrActionResolver.resolve(
          ref: ref,
          rawText: qrResult.content,
        );
      }
    }

    if (!context.mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF222222) : Colors.white;
    final itemBgColor = isDark ? const Color(0xFF2C2C2C) : Colors.white;
    final dividerColor = isDark ? const Color(0xFF333333) : const Color(0xFFF2F2F2);
    final gapColor = isDark ? const Color(0xFF181818) : const Color(0xFFF7F7F7);
    final textColor = isDark ? Colors.white : const Color(0xFF191919);

    final isDesktop = (!kIsWeb &&
            (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) ||
        MediaQuery.sizeOf(context).width >= 720;

    if (isDesktop) {
      await showDesktopModalDialog<void>(
        context: context,
        title: item.type == MediaPreviewType.video ? '视频操作' : '图片操作',
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. 发送给朋友 / 转发
            ListTile(
              leading: Icon(Icons.send_rounded, color: textColor),
              title: const Text('发送给朋友', style: TextStyle(fontSize: 15)),
              onTap: () async {
                Navigator.of(context).pop();
                if (onShare != null) {
                  onShare();
                } else {
                  await _handleForwardMedia(
                    context: context,
                    ref: ref,
                    item: item,
                  );
                }
              },
            ),
            Divider(height: 1, thickness: 0.5, color: dividerColor),

            // 2. 保存图片 / 保存视频
            ListTile(
              leading: Icon(Icons.download_rounded, color: textColor),
              title: Text(
                item.type == MediaPreviewType.video ? '保存视频' : '保存图片',
                style: const TextStyle(fontSize: 15),
              ),
              onTap: () async {
                Navigator.of(context).pop();
                if (onDownload != null) {
                  onDownload();
                } else {
                  try {
                    final cached = await effectiveDownloader.getCachedPath(item);
                    final targetPath = (cached != null && cached.isNotEmpty)
                        ? cached
                        : await effectiveDownloader.download(item);
                    if (targetPath.isNotEmpty) {
                      if (item.type == MediaPreviewType.image) {
                        await MediaGallerySaver.saveImage(targetPath);
                        showToast('已保存到系统相册', type: ToastType.success);
                      } else {
                        await MediaGallerySaver.saveVideo(targetPath);
                        showToast('已保存到系统相册', type: ToastType.success);
                      }
                    }
                  } catch (e) {
                    showToast('保存相册失败: $e', type: ToastType.error);
                  }
                }
              },
            ),

            // 3. ⭐ 如果识别到了二维码，显示识别项
            if (qrAction != null) ...[
              Divider(height: 1, thickness: 0.5, color: dividerColor),
              ListTile(
                leading: Icon(
                  qrAction.icon,
                  color: const Color(0xFF07C160),
                ),
                title: Text(
                  qrAction.title,
                  style: const TextStyle(
                    color: Color(0xFF07C160),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () async {
                  final act = qrAction;
                  Navigator.of(context).pop();
                  if (act != null) {
                    await act.onExecute(context, ref);
                  }
                },
              ),
            ],
          ],
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. 发送给朋友 / 转发
                ListTile(
                  tileColor: itemBgColor,
                  leading: Icon(Icons.send_rounded, color: textColor),
                  title: Text(
                    '发送给朋友',
                    style: TextStyle(color: textColor, fontSize: 16),
                  ),
                  onTap: () async {
                    Navigator.of(sheetCtx).pop();
                    if (onShare != null) {
                      onShare();
                    } else {
                      await _handleForwardMedia(
                        context: context,
                        ref: ref,
                        item: item,
                      );
                    }
                  },
                ),
                Divider(height: 1, thickness: 0.5, color: dividerColor),

                // 2. 保存图片 / 保存视频
                ListTile(
                  tileColor: itemBgColor,
                  leading: Icon(Icons.download_rounded, color: textColor),
                  title: Text(
                    item.type == MediaPreviewType.video ? '保存视频' : '保存图片',
                    style: TextStyle(color: textColor, fontSize: 16),
                  ),
                  onTap: () async {
                    Navigator.of(sheetCtx).pop();
                    if (onDownload != null) {
                      onDownload();
                    } else {
                      try {
                        final cached = await effectiveDownloader.getCachedPath(item);
                        final targetPath = (cached != null && cached.isNotEmpty)
                            ? cached
                            : await effectiveDownloader.download(item);
                        if (targetPath.isNotEmpty) {
                          if (item.type == MediaPreviewType.image) {
                            await MediaGallerySaver.saveImage(targetPath);
                            showToast('已保存到系统相册', type: ToastType.success);
                          } else {
                            await MediaGallerySaver.saveVideo(targetPath);
                            showToast('已保存到系统相册', type: ToastType.success);
                          }
                        }
                      } catch (e) {
                        showToast('保存相册失败: $e', type: ToastType.error);
                      }
                    }
                  },
                ),

                // 3. ⭐ 如果识别到了二维码，显示识别项（微信同款高亮）
                if (qrAction != null) ...[
                  Divider(height: 1, thickness: 0.5, color: dividerColor),
                  ListTile(
                    tileColor: itemBgColor,
                    leading: Icon(
                      qrAction.icon,
                      color: const Color(0xFF07C160), // 微信经典品牌绿
                    ),
                    title: Text(
                      qrAction.title,
                      style: const TextStyle(
                        color: Color(0xFF07C160),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () async {
                      final act = qrAction;
                      Navigator.of(sheetCtx).pop();
                      if (act != null) {
                        await act.onExecute(context, ref);
                      }
                    },
                  ),
                ],

                // 灰色间隔条
                Container(height: 8, color: gapColor),

                // 4. 取消按钮
                ListTile(
                  tileColor: itemBgColor,
                  title: const Center(
                    child: Text(
                      '取消',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  onTap: () => Navigator.of(sheetCtx).pop(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 唤起会话选择器转发当前媒体
  static Future<void> _handleForwardMedia({
    required BuildContext context,
    required WidgetRef ref,
    required MediaPreviewItem item,
  }) async {
    if (item.type == MediaPreviewType.image) {
      try {
        var bytes = item.bytes;
        if (bytes == null || bytes.isEmpty) {
          final downloader = DefaultMediaDownloader.instance;
          final path =
              item.localPath ??
              await downloader.getCachedPath(item) ??
              await downloader.download(item);
          bytes = await File(path).readAsBytes();
        }
        if (!context.mounted) return;
        await ref
            .read(windowServiceProvider)
            .requestImageSend(bytes, fileName: item.fileName);
      } catch (_) {
        showToast('图片读取或发送失败，请重试', type: ToastType.error);
      }
      return;
    }
    final targets = await ForwardTargetPicker.pickTargets(
      context: context,
      sessionLoader: () async {
        final sessionList = ref.read(sessionListControllerProvider);
        return sessionList.sessions;
      },
      title: '发送给朋友',
    );
    if (targets == null || targets.isEmpty || !context.mounted) return;

    final targetNames = targets.map((t) => t.title).join('、');
    final confirmed = await showConfirmModal(
      context: context,
      title: '确认发送',
      message: '确定要将此${item.type == MediaPreviewType.video ? "视频" : "图片"}发送给：$targetNames？',
      confirmText: '发送',
    );
    if (!confirmed || !context.mounted) return;

    showToast('已发送给 $targetNames', type: ToastType.success);
  }
}

class _MediaPreviewPage extends ConsumerStatefulWidget {
  const _MediaPreviewPage({
    required this.items,
    required this.initialIndex,
    required this.downloader,
  });
  final List<MediaPreviewItem> items;
  final int initialIndex;
  final MediaDownloader downloader;
  @override
  ConsumerState<_MediaPreviewPage> createState() => _MediaPreviewPageState();
}

class _MediaPreviewPageState extends ConsumerState<_MediaPreviewPage>
    with SingleTickerProviderStateMixin {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;
  bool _chrome = true;
  Offset _dragOffset = Offset.zero;
  bool _isDragging = false;
  double _currentScale = 1.0;
  int _pointerCount = 0;

  late final AnimationController _resetController;
  Animation<Offset>? _resetAnimation;

  @override
  void initState() {
    super.initState();
    _resetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        if (_resetAnimation != null) {
          setState(() {
            _dragOffset = _resetAnimation!.value;
          });
        }
      });

    // 预扫描初始当前大图中的二维码
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _preloadQrCode(_index);
    });
  }

  /// 后台轻量预扫描指定索引大图中的二维码
  Future<void> _preloadQrCode(int index) async {
    if (index < 0 || index >= widget.items.length) return;
    final item = widget.items[index];
    if (item.type != MediaPreviewType.image) return;

    final detector = ref.read(imageQrDetectorProvider);
    final cacheKey = item.localPath ?? item.source;
    if (detector.hasCache(cacheKey)) return;

    Uint8List? bytes = item.bytes;
    if (bytes == null && item.localPath != null && item.localPath!.isNotEmpty) {
      try {
        final f = File(item.localPath!);
        if (await f.exists()) bytes = await f.readAsBytes();
      } catch (_) {}
    }
    if (bytes == null) {
      final cached = await widget.downloader.getCachedPath(item);
      if (cached != null) {
        try {
          final f = File(cached);
          if (await f.exists()) bytes = await f.readAsBytes();
        } catch (_) {}
      }
    }
    if (bytes != null) {
      await detector.detectFromBytes(bytes, cacheKey: cacheKey);
    }
  }

  /// 长按媒体：委托给 MediaPreview.showActionSheet 处理
  Future<void> _handleMediaLongPress(MediaPreviewItem item) async {
    await MediaPreview.showActionSheet(
      context,
      ref: ref,
      item: item,
      downloader: widget.downloader,
      onShare: _shareCurrent,
      onDownload: _downloadCurrent,
    );
  }

  @override
  void dispose() {
    _resetController.dispose();
    _pages.dispose();
    super.dispose();
  }

  double get _dragProgress =>
      (_dragOffset.dy.abs() / 280.0).clamp(0.0, 1.0);

  double get _backgroundOpacity =>
      (1.0 - _dragProgress * 0.95).clamp(0.0, 1.0);

  double get _mediaScale => (1.0 - _dragProgress * 0.35).clamp(0.65, 1.0);

  void _onVerticalDragStart(DragStartDetails details) {
    if (_pointerCount >= 2 || _currentScale > 1.05) return;
    _resetController.stop();
    _isDragging = true;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_pointerCount >= 2 || _currentScale > 1.05) {
      if (_isDragging) {
        _isDragging = false;
        _dragOffset = Offset.zero;
        setState(() {});
      }
      return;
    }
    _isDragging = true;
    setState(() {
      final newDy = _dragOffset.dy + details.delta.dy;
      final newDx = _dragOffset.dx + details.delta.dx;
      _dragOffset = Offset(newDx, newDy);
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_currentScale > 1.05) return;
    _isDragging = false;
    final velocity = (details.primaryVelocity ?? 0.0).abs();
    final distance = _dragOffset.dy.abs();
    final shouldClose = distance > 80.0 || velocity > 500.0;
    if (shouldClose) {
      Navigator.of(context).pop();
    } else {
      _resetAnimation = Tween<Offset>(
        begin: _dragOffset,
        end: Offset.zero,
      ).animate(
        CurvedAnimation(
          parent: _resetController,
          curve: Curves.easeOutCubic,
        ),
      );
      _resetController.forward(from: 0.0);
    }
  }

  /// 下载/复制当前媒体到系统相册。
  Future<void> _downloadCurrent() async {
    final item = widget.items[_index];
    try {
      final cached = await widget.downloader.getCachedPath(item);
      if (cached != null) {
        // 已经下载 -> 复制到相册
        if (item.type == MediaPreviewType.image) {
          await MediaGallerySaver.saveImage(cached);
          showToast('已复制到系统相册', type: ToastType.success);
        } else if (item.type == MediaPreviewType.video) {
          await MediaGallerySaver.saveVideo(cached);
          showToast('已复制到系统相册', type: ToastType.success);
        } else {
          showToast('已保存在本地', type: ToastType.info);
        }
      } else {
        // 未下载 -> 下载到相册
        showToast('正在下载媒体文件...', type: ToastType.info);
        final path = await widget.downloader.download(item);
        if (path.isNotEmpty) {
          if (item.type == MediaPreviewType.image) {
            await MediaGallerySaver.saveImage(path);
            showToast('已下载并保存到相册', type: ToastType.success);
          } else if (item.type == MediaPreviewType.video) {
            await MediaGallerySaver.saveVideo(path);
            showToast('已下载并保存到相册', type: ToastType.success);
          } else {
            showToast('下载完成', type: ToastType.success);
          }
        }
      }
    } catch (e) {
      showToast('保存相册失败：$e', type: ToastType.error);
    }
  }

  /// 分享当前媒体（stub — 业务层可替换）。
  void _shareCurrent() {
    final item = widget.items[_index];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('分享：${item.fileName ?? item.source.split('/').last}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 将当前播放的视频缩小为画中画悬浮窗（与顶部关闭按钮平级）。
  void _minimizeCurrentVideo() {
    final item = widget.items[_index];
    if (item.type != MediaPreviewType.video) return;
    openFloatingVideoWindow(
      context,
      item: item,
      items: widget.items,
      initialIndex: _index,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final routeAnimation = ModalRoute.of(context)?.animation;
    return AnimatedBuilder(
      animation: routeAnimation ?? const AlwaysStoppedAnimation<double>(1.0),
      builder: (context, _) {
        final routeProgress = routeAnimation?.value ?? 1.0;
        final bgOpacity =
            (_backgroundOpacity * routeProgress).clamp(0.0, 1.0);
        final chromeOpacity =
            ((1.0 - _dragProgress * 3.0) * routeProgress).clamp(0.0, 1.0);

        return Scaffold(
          backgroundColor: Colors.black.withValues(alpha: bgOpacity),
          body: SafeArea(
            child: Listener(
              onPointerDown: (_) => setState(() => _pointerCount++),
              onPointerUp:
                  (_) => setState(() {
                    if (_pointerCount > 0) _pointerCount--;
                  }),
              onPointerCancel:
                  (_) => setState(() {
                    if (_pointerCount > 0) _pointerCount--;
                  }),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  if (_dragOffset == Offset.zero) {
                    setState(() => _chrome = !_chrome);
                  }
                },
                onLongPress: () {
                  if (_dragOffset == Offset.zero && _pointerCount <= 1) {
                    _handleMediaLongPress(widget.items[_index]);
                  }
                },
                onVerticalDragStart:
                    widget.items[_index].type == MediaPreviewType.video
                        ? _onVerticalDragStart
                        : null,
                onVerticalDragUpdate:
                    widget.items[_index].type == MediaPreviewType.video
                        ? _onVerticalDragUpdate
                        : null,
                onVerticalDragEnd:
                    widget.items[_index].type == MediaPreviewType.video
                        ? _onVerticalDragEnd
                        : null,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Transform.translate(
                      offset: _dragOffset,
                      child: Transform.scale(
                        scale: _mediaScale,
                        child: PageView.builder(
                          controller: _pages,
                          physics:
                              _isDragging ||
                                      _dragOffset != Offset.zero ||
                                      _pointerCount >= 2 ||
                                      _currentScale > 1.05
                                  ? const NeverScrollableScrollPhysics()
                                  : const BouncingScrollPhysics(),
                          itemCount: widget.items.length,
                          onPageChanged:
                              (value) => setState(() {
                                _index = value;
                                _currentScale = 1.0;
                                _dragOffset = Offset.zero;
                                _preloadQrCode(value);
                              }),
                          itemBuilder: (context, index) {
                            final item = widget.items[index];
                            return _MediaPreviewItemView(
                              item: item,
                              active: index == _index,
                              items: widget.items,
                              index: index,
                              downloader: widget.downloader,
                              isDragging: _isDragging || _dragOffset != Offset.zero,
                              onScaleChanged: (scale) {
                                _currentScale = scale;
                              },
                              onDismissProgress: (offset) {
                                setState(() {
                                  _dragOffset = offset;
                                  _isDragging = offset != Offset.zero;
                                });
                              },
                              onDismissEnd: () => Navigator.of(context).pop(),
                              onLongPress: () => _handleMediaLongPress(item),
                            );
                          },
                        ),
                      ),
                    ),
                    // ── 关闭按钮（左上）──────────────────────────────
                    if (_chrome && chromeOpacity > 0.0)
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Opacity(
                          opacity: chromeOpacity,
                          child: IconButton(
                            tooltip: '关闭',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close, color: Colors.white),
                          ),
                        ),
                      ),
                    // ── 浮动小窗口按钮（右上，与关闭按钮平级，手指滑动时小窗口按钮不移动）──
                    if (_chrome &&
                        chromeOpacity > 0.0 &&
                        widget.items[_index].type == MediaPreviewType.video)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Opacity(
                          opacity: chromeOpacity,
                          child: IconButton(
                            tooltip: '缩小为浮窗',
                            onPressed: _minimizeCurrentVideo,
                            icon: const Icon(
                              Icons.picture_in_picture_alt,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    // ── 页码指示器（底部中央）────────────────────────
                    if (_chrome &&
                        widget.items.length > 1 &&
                        chromeOpacity > 0.0)
                      Positioned(
                        bottom: 18,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: Opacity(
                            opacity: chromeOpacity,
                            child: Text(
                              '${_index + 1} / ${widget.items.length}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                shadows: [
                                  Shadow(blurRadius: 4, color: Colors.black54),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    // ── 下载 / 分享（右下角）─────────────────────────
                    if (_chrome && chromeOpacity > 0.0)
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Opacity(
                          opacity: chromeOpacity,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _ChromeButton(
                                tooltip: '下载',
                                icon: Icons.download_rounded,
                                onPressed: _downloadCurrent,
                              ),
                              const SizedBox(width: 4),
                              _ChromeButton(
                                tooltip: '分享',
                                icon: Icons.share_rounded,
                                onPressed: _shareCurrent,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 半透明圆形背景按钮，用于预览页 chrome 区域。
class _ChromeButton extends StatelessWidget {
  const _ChromeButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.45),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

class _MediaPreviewItemView extends StatefulWidget {
  const _MediaPreviewItemView({
    required this.item,
    required this.active,
    required this.items,
    required this.index,
    required this.downloader,
    required this.onScaleChanged,
    required this.onDismissProgress,
    required this.onDismissEnd,
    this.onLongPress,
    this.isDragging = false,
  });

  final MediaPreviewItem item;
  final bool active;
  final List<MediaPreviewItem> items;
  final int index;
  final MediaDownloader downloader;
  final ValueChanged<double> onScaleChanged;
  final ValueChanged<Offset> onDismissProgress;
  final VoidCallback onDismissEnd;
  final VoidCallback? onLongPress;
  final bool isDragging;

  @override
  State<_MediaPreviewItemView> createState() => _MediaPreviewItemViewState();
}

class _MediaPreviewItemViewState extends State<_MediaPreviewItemView>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  String? _localPath;
  bool _isReady = false;
  bool _isDownloading = false;
  double _progress = 0.0;
  Object? _error;

  String? _resolveLocalFile(String? path) {
    if (path == null || path.isEmpty) return null;
    if (kIsWeb) return null;
    try {
      var p = path;
      if (p.startsWith('file://')) {
        p = Uri.tryParse(p)?.toFilePath() ?? p.substring(7);
      }
      if (File(p).existsSync()) return p;
    } catch (_) {}
    return null;
  }

  bool _fileExists(String? path) {
    if (path == null || path.isEmpty) return false;
    if (kIsWeb) return true;
    try {
      var p = path;
      if (p.startsWith('file://')) {
        p = Uri.tryParse(p)?.toFilePath() ?? p.substring(7);
      }
      return File(p).existsSync();
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    final local = _resolveLocalFile(widget.item.localPath) ??
        _resolveLocalFile(widget.item.source);
    if (local != null) {
      _localPath = local;
      _isReady = true;
    } else if (widget.item.type == MediaPreviewType.image) {
      // 图片直接由 ImageViewer 结合 CachedNetworkImage / MemoryImage 渲染并支持缩放手势，直接标记 ready
      _isReady = true;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _checkStatus();
      });
    }
  }

  @override
  void didUpdateWidget(_MediaPreviewItemView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.item.source != oldWidget.item.source ||
        widget.item.id != oldWidget.item.id ||
        widget.item.localPath != oldWidget.item.localPath) {
      if (widget.item.type != MediaPreviewType.image) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _checkStatus();
        });
      }
    } else if (widget.active && !_isReady && !_isDownloading && _error == null) {
      if (widget.item.type != MediaPreviewType.image) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && widget.active && !_isReady && !_isDownloading && _error == null) {
            _startDownload();
          }
        });
      }
    }
  }

  Future<void> _checkStatus() async {
    final local = _resolveLocalFile(widget.item.localPath) ??
        _resolveLocalFile(widget.item.source);
    if (local != null) {
      if (mounted) {
        setState(() {
          _localPath = local;
          _isReady = true;
          _error = null;
        });
      }
      return;
    }
    if (widget.item.type == MediaPreviewType.image) {
      if (mounted) {
        setState(() {
          _isReady = true;
          _error = null;
        });
      }
      return;
    }

    final cached = await widget.downloader.getCachedPath(widget.item);
    if (!mounted) return;
    if (cached != null && _fileExists(cached)) {
      setState(() {
        _localPath = cached;
        _isReady = true;
        _error = null;
      });
    } else if (widget.active) {
      _startDownload();
    }
  }

  void _startDownload() {
    if (!mounted || _isDownloading) return;
    final local = _resolveLocalFile(widget.item.localPath) ??
        _resolveLocalFile(widget.item.source);
    if (local != null) {
      setState(() {
        _localPath = local;
        _isReady = true;
        _isDownloading = false;
        _error = null;
      });
      return;
    }

    if (widget.item.type == MediaPreviewType.image) {
      setState(() {
        _isReady = true;
        _isDownloading = false;
        _error = null;
      });
      return;
    }

    final source = widget.item.source;
    if (source.isEmpty ||
        (!source.startsWith('http://') && !source.startsWith('https://'))) {
      setState(() {
        _error = '文件不存在或已被清理';
      });
      showToast('媒体文件不存在或已被清理', type: ToastType.error);
      return;
    }
    setState(() {
      _isDownloading = true;
      _error = null;
      _progress = 0.0;
    });

    widget.downloader.download(
      widget.item,
      onProgress: (received, total) {
        if (!mounted) return;
        setState(() {
          _progress = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;
        });
      },
    ).then((path) {
      if (!mounted) return;
      setState(() {
        _localPath = path;
        _isDownloading = false;
        _isReady = true;
      });
    }).catchError((Object err) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _error = err;
      });
      showToast('下载媒体失败: $err', type: ToastType.error);
    });
  }

  Widget _buildThumbnail() {
    if (widget.item.bytes != null) {
      return Image.memory(widget.item.bytes!, fit: BoxFit.contain);
    }
    final thumb = widget.item.thumbnail;
    final source =
        (thumb != null && thumb.isNotEmpty) ? thumb : widget.item.source;
    if (source.isNotEmpty) {
      return Image(
        image: createImageProvider(source),
        fit: BoxFit.contain,
        errorBuilder:
            (_, _, _) => const Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 48,
              ),
            ),
      );
    }
    return const Center(
      child: Icon(Icons.image_outlined, color: Colors.white54, size: 48),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isImage = widget.item.type == MediaPreviewType.image;

    Widget body;
    if (isImage) {
      body = Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          ImageViewer(
            heroTag: null,
            source: _localPath ?? widget.item.source,
            bytes: widget.item.bytes,
            thumbnail: widget.item.thumbnail,
            thumbnailBytes: widget.item.bytes,
            onScaleChanged: widget.onScaleChanged,
            onDismissProgress: widget.onDismissProgress,
            onDismissEnd: widget.onDismissEnd,
            onLongPress: widget.onLongPress,
          ),
          if (_isDownloading && !_isReady)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: 40,
                      child: CircularProgressIndicator(
                        value: _progress > 0 ? _progress : null,
                        color: Colors.white,
                        backgroundColor: Colors.white24,
                        strokeWidth: 3.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${(_progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_error != null && !_isReady)
            Center(
              child: GestureDetector(
                onTap: _startDownload,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.refresh_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                      SizedBox(height: 6),
                      Text(
                        '下载失败，点击重试',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    } else {
      body = _isReady
          ? VideoViewer(
              heroTag: null,
              item: widget.item.copyWith(
                source: _localPath ?? widget.item.source,
              ),
              active: widget.active,
              items: widget.items,
              initialIndex: widget.index,
              isDragging: widget.isDragging,
            )
          : Stack(
              fit: StackFit.expand,
              alignment: Alignment.center,
              children: [
                _buildThumbnail(),
                if (!_isDownloading && _error == null)
                  const Center(
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      color: Colors.white70,
                      size: 64,
                    ),
                  ),
                if (_isDownloading && !_isReady)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox.square(
                            dimension: 40,
                            child: CircularProgressIndicator(
                              value: _progress > 0 ? _progress : null,
                              color: Colors.white,
                              backgroundColor: Colors.white24,
                              strokeWidth: 3.2,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '${(_progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_error != null)
                  Center(
                    child: GestureDetector(
                      onTap: _startDownload,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.refresh_rounded,
                              color: Colors.white,
                              size: 30,
                            ),
                            SizedBox(height: 6),
                            Text(
                              '下载失败，点击重试',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
    }

    return Hero(
      tag: widget.item.heroTag,
      child: Material(
        type: MaterialType.transparency,
        child: body,
      ),
    );
  }
}

