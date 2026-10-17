import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/media/media_preview.dart';
import '../../../core/services/clipboard_service.dart';
import '../../../core/services/screen_capture_service.dart';
import '../../../core/services/tray_grouped_unread_provider.dart';
import '../../../core/services/tray_service.dart';
import '../../../core/services/window_service.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/desktop_tray_message_box.dart';
import '../../chat/presentation/widgets/clipboard_files_confirm_dialog.dart';
import '../../chat/presentation/widgets/clipboard_image_confirm_dialog.dart';

/// 桌面端独立窗口测试诊断中心
class DesktopWindowsDiagnosticsPage extends ConsumerStatefulWidget {
  const DesktopWindowsDiagnosticsPage({super.key});

  @override
  ConsumerState<DesktopWindowsDiagnosticsPage> createState() =>
      _DesktopWindowsDiagnosticsPageState();
}

class _DesktopWindowsDiagnosticsPageState
    extends ConsumerState<DesktopWindowsDiagnosticsPage> {
  final TextEditingController _urlController = TextEditingController(
    text: 'https://news.qq.com',
  );
  final TextEditingController _urlTitleController = TextEditingController(
    text: '腾讯新闻',
  );
  final TextEditingController _imageUrlController = TextEditingController(
    text: 'https://picsum.photos/1200/800',
  );
  final TextEditingController _unreadCountController = TextEditingController(
    text: '5',
  );
  bool _isBlinking = true;

  String _status = '未执行';
  int _elapsedMs = 0;
  String _lastResult = '暂无执行结果';
  String? _error;

  @override
  void dispose() {
    _urlController.dispose();
    _urlTitleController.dispose();
    _imageUrlController.dispose();
    _unreadCountController.dispose();
    super.dispose();
  }

  void _resetDefaults() {
    setState(() {
      _urlController.text = 'https://news.qq.com';
      _urlTitleController.text = '腾讯新闻';
      _imageUrlController.text = 'https://picsum.photos/1200/800';
      _unreadCountController.text = '5';
      _isBlinking = true;
      _status = '已恢复默认设置';
      _lastResult = '参数已重置';
      _error = null;
    });
  }

  Future<void> _testOpenBrowser() async {
    final sw = Stopwatch()..start();
    setState(() {
      _status = '执行中...';
      _error = null;
    });
    try {
      final windowService = ref.read(windowServiceProvider);
      await windowService.openWebBrowser(
        url: _urlController.text.trim(),
        title: _urlTitleController.text.trim(),
      );
      sw.stop();
      setState(() {
        _status = '成功';
        _elapsedMs = sw.elapsedMilliseconds;
        _lastResult =
            '已成功调起独立浏览器窗口\nURL: ${_urlController.text}\n标题: ${_urlTitleController.text}';
      });
    } catch (e, st) {
      sw.stop();
      setState(() {
        _status = '失败';
        _elapsedMs = sw.elapsedMilliseconds;
        _error = '$e\n$st';
      });
    }
  }

  Future<void> _testOpenMediaViewer() async {
    final sw = Stopwatch()..start();
    setState(() {
      _status = '执行中...';
      _error = null;
    });
    try {
      final windowService = ref.read(windowServiceProvider);
      final url = _imageUrlController.text.trim();
      await windowService.openMediaViewer(
        mediaUrl: url,
        title: '示例图片预览',
        items: [
          MediaPreviewItem(
            id: 'demo-img-1',
            messageId: 'diag-1',
            type: MediaPreviewType.image,
            source: url,
            heroTag: 'diag-img-1',
          ),
          const MediaPreviewItem(
            id: 'demo-img-2',
            messageId: 'diag-2',
            type: MediaPreviewType.image,
            source: 'https://picsum.photos/800/1200',
            heroTag: 'diag-img-2',
          ),
        ],
      );
      sw.stop();
      setState(() {
        _status = '成功';
        _elapsedMs = sw.elapsedMilliseconds;
        _lastResult = '已成功调起独立图片/视频查看窗口\n媒体源: $url\n附带2张测试图切换';
      });
    } catch (e, st) {
      sw.stop();
      setState(() {
        _status = '失败';
        _elapsedMs = sw.elapsedMilliseconds;
        _error = '$e\n$st';
      });
    }
  }

  Future<void> _testOpenSettings() async {
    final sw = Stopwatch()..start();
    setState(() {
      _status = '执行中...';
      _error = null;
    });
    try {
      final windowService = ref.read(windowServiceProvider);
      await windowService.openSettings();
      sw.stop();
      setState(() {
        _status = '成功';
        _elapsedMs = sw.elapsedMilliseconds;
        _lastResult = '已成功调起独立微信风格设置窗口 (账号与存储、通用、快捷键、通知、关于)';
      });
    } catch (e, st) {
      sw.stop();
      setState(() {
        _status = '失败';
        _elapsedMs = sw.elapsedMilliseconds;
        _error = '$e\n$st';
      });
    }
  }

  Future<void> _testOpenStandaloneChat() async {
    final sw = Stopwatch()..start();
    setState(() {
      _status = '执行中...';
      _error = null;
    });
    try {
      final windowService = ref.read(windowServiceProvider);
      await windowService.openChat(
        sessionUnitId: 'diag-session-101',
        ownerId: 1001,
        title: '产品技术委员会 (独立窗口)',
      );
      sw.stop();
      setState(() {
        _status = '成功';
        _elapsedMs = sw.elapsedMilliseconds;
        _lastResult =
            '已成功调起独立聊天窗口 (真实原生操作系统 HWND)\n会话: 产品技术委员会\nSessionUnit: diag-session-101\nOwner: 1001';
      });
    } catch (e, st) {
      sw.stop();
      setState(() {
        _status = '失败';
        _elapsedMs = sw.elapsedMilliseconds;
        _error = '$e\n$st';
      });
    }
  }

  Future<void> _testOpenTrayFlyout() async {
    final sw = Stopwatch()..start();
    setState(() {
      _status = '执行中...';
      _error = null;
    });
    try {
      await DesktopTrayMessageBox.show(context);
      sw.stop();
      final state = ref.read(trayGroupedUnreadProvider);
      setState(() {
        _status = '成功';
        _elapsedMs = sw.elapsedMilliseconds;
        _lastResult =
            '已成功在右下角弹出微信风格无边框托盘未读浮窗\n未读总数: ${state.totalUnread}\n分组总数: ${state.groups.length} 个聊天对象';
      });
    } catch (e, st) {
      sw.stop();
      setState(() {
        _status = '失败';
        _elapsedMs = sw.elapsedMilliseconds;
        _error = '$e\n$st';
      });
    }
  }

  Future<void> _testUpdateTrayBadge() async {
    final sw = Stopwatch()..start();
    setState(() {
      _status = '执行中...';
      _error = null;
    });
    try {
      final count = int.tryParse(_unreadCountController.text.trim()) ?? 0;
      final trayService = ref.read(trayServiceProvider);
      await trayService.setUnread(count);
      sw.stop();
      setState(() {
        _status = '成功';
        _elapsedMs = sw.elapsedMilliseconds;
        _lastResult = '已动态合成并绘制托盘图标角标数字: $count\n支持平台: Windows / macOS / Linux';
      });
    } catch (e, st) {
      sw.stop();
      setState(() {
        _status = '失败';
        _elapsedMs = sw.elapsedMilliseconds;
        _error = '$e\n$st';
      });
    }
  }

  void _testSimulateMessage() {
    final sw = Stopwatch()..start();
    try {
      ref
          .read(trayGroupedUnreadProvider.notifier)
          .simulateIncomingMessage(
            ownerId: 1001,
            ownerName: '张三',
            sessionUnitId: 'u-101',
            targetName: '李四 (前端研发)',
            message: '模拟新推送：托盘无边框消息聚合已就绪 [${DateTime.now().second}s]',
          );
      final state = ref.read(trayGroupedUnreadProvider);
      sw.stop();
      setState(() {
        _status = '成功';
        _elapsedMs = sw.elapsedMilliseconds;
        _lastResult =
            '成功向【张三】模拟追加一条新未读消息\n当前全局未读总数: ${state.totalUnread}\n聊天对象1未读数: ${state.groups.first.totalUnread}';
      });
    } catch (e, st) {
      sw.stop();
      setState(() {
        _status = '失败';
        _elapsedMs = sw.elapsedMilliseconds;
        _error = '$e\n$st';
      });
    }
  }

  void _testLoadSampleData() {
    final sw = Stopwatch()..start();
    try {
      ref.read(trayGroupedUnreadProvider.notifier).loadSampleData();
      final state = ref.read(trayGroupedUnreadProvider);
      sw.stop();
      setState(() {
        _status = '成功';
        _elapsedMs = sw.elapsedMilliseconds;
        _lastResult =
            '已成功注入测试模拟未读数据 (张三 5 条，客服 2 条)\n当前未读总数: ${state.totalUnread}';
      });
    } catch (e, st) {
      sw.stop();
      setState(() {
        _status = '失败';
        _elapsedMs = sw.elapsedMilliseconds;
        _error = '$e\n$st';
      });
    }
  }

  void _testClearUnread() {
    final sw = Stopwatch()..start();
    try {
      ref.read(trayGroupedUnreadProvider.notifier).markAllRead();
      sw.stop();
      setState(() {
        _status = '成功';
        _elapsedMs = sw.elapsedMilliseconds;
        _lastResult = '已一键清空所有聊天对象的未读消息并重置托盘图标角标';
      });
    } catch (e, st) {
      sw.stop();
      setState(() {
        _status = '失败';
        _elapsedMs = sw.elapsedMilliseconds;
        _error = '$e\n$st';
      });
    }
  }

  void _testToggleBlinking(bool value) {
    setState(() {
      _isBlinking = value;
    });
    ref.read(trayServiceProvider).setBlinking(value);
    showToast(_isBlinking ? '已开启托盘呼吸闪烁' : '已关闭托盘呼吸闪烁', type: ToastType.info);
  }

  /// 1. 触发桌面截图 (Alt+A / ms-screenclip:)
  Future<void> _testTriggerScreenCapture() async {
    final sw = Stopwatch()..start();
    setState(() {
      _status = '执行中... (正在调起系统截图工具)';
      _error = null;
    });
    try {
      final imageBytes = await ref.read(screenCaptureServiceProvider).capture();
      sw.stop();
      if (imageBytes == null) {
        setState(() {
          _status = '未完成';
          _elapsedMs = sw.elapsedMilliseconds;
          _lastResult = '未获取到截图或用户已取消操作 (系统剪贴板中无新截图数据)';
        });
        return;
      }

      setState(() {
        _status = '成功';
        _elapsedMs = sw.elapsedMilliseconds;
        _lastResult =
            '截图成功！获取到图像数据: ${imageBytes.lengthInBytes} 字节。\n正在弹出微信同款确认发送弹窗...';
      });

      if (!mounted) return;
      final dialogResult = await ClipboardImageConfirmDialog.show(
        context,
        imageBytes: imageBytes,
      );

      setState(() {
        if (dialogResult != null && dialogResult.confirmed) {
          _lastResult += '\n用户点击了 [发送]！附加留言: "${dialogResult.caption ?? ""}"';
        } else {
          _lastResult += '\n用户点击了 [取消]';
        }
      });
    } catch (e, st) {
      sw.stop();
      setState(() {
        _status = '失败';
        _elapsedMs = sw.elapsedMilliseconds;
        _error = '$e\n$st';
      });
    }
  }

  /// 2. 从系统剪贴板读取真实图片并弹窗确认 (Ctrl+V)
  Future<void> _testReadClipboardImage() async {
    final sw = Stopwatch()..start();
    setState(() {
      _status = '执行中... (正在读取剪贴板图片)';
      _error = null;
    });
    try {
      final imageBytes = await ref.read(clipboardServiceProvider).readImage();
      sw.stop();
      if (imageBytes == null) {
        setState(() {
          _status = '成功';
          _elapsedMs = sw.elapsedMilliseconds;
          _lastResult = '当前系统剪贴板中未检测到图片数据。请按 PrintScreen 复制图片后重试。';
        });
        return;
      }

      setState(() {
        _status = '成功';
        _elapsedMs = sw.elapsedMilliseconds;
        _lastResult =
            '成功读取剪贴板图片！大小: ${(imageBytes.lengthInBytes / 1024).toStringAsFixed(1)} KB。\n正在弹出微信同款确认发送弹窗...';
      });

      if (!mounted) return;
      final dialogResult = await ClipboardImageConfirmDialog.show(
        context,
        imageBytes: imageBytes,
      );

      setState(() {
        if (dialogResult != null && dialogResult.confirmed) {
          _lastResult += '\n用户点击了 [发送]！附加留言: "${dialogResult.caption ?? ""}"';
        } else {
          _lastResult += '\n用户点击了 [取消]';
        }
      });
    } catch (e, st) {
      sw.stop();
      setState(() {
        _status = '失败';
        _elapsedMs = sw.elapsedMilliseconds;
        _error = '$e\n$st';
      });
    }
  }

  /// 3. 从系统剪贴板读取真实文件并弹窗确认 (Ctrl+V)
  Future<void> _testReadClipboardFiles() async {
    final sw = Stopwatch()..start();
    setState(() {
      _status = '执行中... (正在读取剪贴板文件)';
      _error = null;
    });
    try {
      final filePaths = await ref.read(clipboardServiceProvider).readFiles();
      sw.stop();
      if (filePaths.isEmpty) {
        setState(() {
          _status = '成功';
          _elapsedMs = sw.elapsedMilliseconds;
          _lastResult = '当前系统剪贴板中未检测到复制的文件。请在文件资源管理器中 Ctrl+C 复制文件后重试。';
        });
        return;
      }

      setState(() {
        _status = '成功';
        _elapsedMs = sw.elapsedMilliseconds;
        _lastResult =
            '成功读取剪贴板中的 ${filePaths.length} 个文件：\n${filePaths.join('\n')}\n正在弹出文件预发送确认弹窗...';
      });

      if (!mounted) return;
      final dialogResult = await ClipboardFilesConfirmDialog.show(
        context,
        filePaths: filePaths,
      );

      setState(() {
        if (dialogResult != null && dialogResult.confirmed) {
          _lastResult +=
              '\n用户确认发送 ${dialogResult.files.length} 个文件！附加留言: "${dialogResult.caption ?? ""}"';
        } else {
          _lastResult += '\n用户点击了 [取消]';
        }
      });
    } catch (e, st) {
      sw.stop();
      setState(() {
        _status = '失败';
        _elapsedMs = sw.elapsedMilliseconds;
        _error = '$e\n$st';
      });
    }
  }

  /// 4. 模拟弹出图片确认弹窗（无需剪贴板有现成图片）
  Future<void> _testMockImageConfirmDialog() async {
    final sw = Stopwatch()..start();
    setState(() {
      _status = '执行中...';
      _error = null;
    });
    try {
      final imageBytes = Uint8List.fromList(const <int>[
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        0x00,
        0x00,
        0x00,
        0x0D,
        0x49,
        0x48,
        0x44,
        0x52,
        0x00,
        0x00,
        0x00,
        0x20,
        0x00,
        0x00,
        0x00,
        0x20,
        0x08,
        0x06,
        0x00,
        0x00,
        0x00,
        0x73,
        0x7A,
        0x7A,
        0xF4,
        0x00,
        0x00,
        0x00,
        0x2B,
        0x49,
        0x44,
        0x41,
        0x54,
        0x78,
        0xDA,
        0xED,
        0xD0,
        0x41,
        0x11,
        0x00,
        0x00,
        0x0C,
        0xC2,
        0x40,
        0xDA,
        0xBF,
        0xF4,
        0x6A,
        0x16,
        0xBE,
        0x1C,
        0x04,
        0x40,
        0x72,
        0xD2,
        0x4F,
        0x9F,
        0x03,
        0x03,
        0x03,
        0x03,
        0x03,
        0x03,
        0x03,
        0x03,
        0x03,
        0x03,
        0x03,
        0x83,
        0x85,
        0x01,
        0xBB,
        0xC2,
        0x03,
        0x2D,
        0x65,
        0x41,
        0x9F,
        0x74,
        0x00,
        0x00,
        0x00,
        0x00,
        0x49,
        0x45,
        0x4E,
        0x44,
        0xAE,
        0x42,
        0x60,
        0x82,
      ]);
      sw.stop();
      setState(() {
        _status = '成功';
        _elapsedMs = sw.elapsedMilliseconds;
        _lastResult = '已生成模拟图像 (${imageBytes.length} 字节)，正在展示微信同款确认弹窗...';
      });

      if (!mounted) return;
      final dialogResult = await ClipboardImageConfirmDialog.show(
        context,
        imageBytes: imageBytes,
      );

      setState(() {
        if (dialogResult != null && dialogResult.confirmed) {
          _lastResult += '\n用户点击了 [发送]！附加留言: "${dialogResult.caption ?? ""}"';
        } else {
          _lastResult += '\n用户点击了 [取消]';
        }
      });
    } catch (e, st) {
      sw.stop();
      setState(() {
        _status = '失败';
        _elapsedMs = sw.elapsedMilliseconds;
        _error = '$e\n$st';
      });
    }
  }

  /// 5. 模拟弹出多文件确认弹窗（无需剪贴板有现成文件）
  Future<void> _testMockFilesConfirmDialog() async {
    final sw = Stopwatch()..start();
    setState(() {
      _status = '执行中...';
      _error = null;
    });
    try {
      const mockFiles = [
        'F:/Dev/GotoIM/gotoim-flutter/pubspec.yaml',
        'F:/Dev/GotoIM/gotoim-flutter/README.md',
        'F:/Dev/GotoIM/gotoim-flutter/lib/main.dart',
        'F:/Dev/GotoIM/gotoim-flutter/assets/icons/app_icon.png',
      ];
      sw.stop();
      setState(() {
        _status = '成功';
        _elapsedMs = sw.elapsedMilliseconds;
        _lastResult = '已创建 4 个模拟文件列表，正在展示微信同款文件预发送确认弹窗...';
      });

      if (!mounted) return;
      final dialogResult = await ClipboardFilesConfirmDialog.show(
        context,
        filePaths: mockFiles,
      );

      setState(() {
        if (dialogResult != null && dialogResult.confirmed) {
          _lastResult +=
              '\n用户确认发送 ${dialogResult.files.length} 个文件！文件列表: ${dialogResult.files.map((f) => f.name).join(', ')}\n附加留言: "${dialogResult.caption ?? ""}"';
        } else {
          _lastResult += '\n用户点击了 [取消]';
        }
      });
    } catch (e, st) {
      sw.stop();
      setState(() {
        _status = '失败';
        _elapsedMs = sw.elapsedMilliseconds;
        _error = '$e\n$st';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('桌面端独立窗口测试'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '恢复默认测试数据',
            onPressed: _resetDefaults,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. 功能说明与平台支持
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '功能说明',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '验证桌面端独立视窗能力（微信同款）：\n'
                    '1. 独立图片/视频查看窗口：带缩放、翻页、1:1、旋转、下载与更多操作；\n'
                    '2. 独立浏览器窗口：带标签页Tab、前进后退、置顶、外部浏览器打开；\n'
                    '3. 独立设置窗口：微信暗黑设计，支持账号卡片、存储管理、外观与快捷键；\n'
                    '4. 非桌面端（移动端/Web）平滑降级为应用内标准页面导航。',
                    style: TextStyle(fontSize: 12, height: 1.5),
                  ),
                  const SizedBox(height: 10),
                  const Divider(height: 1, thickness: 0.5),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    children: [
                      _buildPlatformBadge('Windows', true),
                      _buildPlatformBadge('macOS', true),
                      _buildPlatformBadge('Linux', true),
                      _buildPlatformBadge('Android (降级)', true),
                      _buildPlatformBadge('iOS (降级)', true),
                      _buildPlatformBadge('Web (降级)', true),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 2. 输入参数
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '输入参数',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: '网页链接 (URL)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _urlTitleController,
                    decoration: const InputDecoration(
                      labelText: '网页标题',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _imageUrlController,
                    decoration: const InputDecoration(
                      labelText: '多媒体测试图片 URL',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _unreadCountController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '测试未读消息数 (角标数字)',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Row(
                        children: [
                          const Text(
                            '未读时呼吸闪烁: ',
                            style: TextStyle(fontSize: 12),
                          ),
                          Switch(
                            value: _isBlinking,
                            onChanged: _testToggleBlinking,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 3. 执行按钮区
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF07C160),
                ),
                icon: const Icon(Icons.mark_chat_unread_rounded, size: 16),
                label: const Text('弹出托盘未读浮窗 (按聊天对象分组)'),
                onPressed: _testOpenTrayFlyout,
              ),
              FilledButton.icon(
                icon: const Icon(Icons.notifications_active_rounded, size: 16),
                label: const Text('更新托盘角标数字'),
                onPressed: _testUpdateTrayBadge,
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.add_comment_rounded, size: 16),
                label: const Text('模拟接收新消息 (+1)'),
                onPressed: _testSimulateMessage,
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.playlist_add_check_rounded, size: 16),
                label: const Text('注入测试未读数据 (Mock)'),
                onPressed: _testLoadSampleData,
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.done_all_rounded, size: 16),
                label: const Text('一键清空未读'),
                onPressed: _testClearUnread,
              ),
              FilledButton.icon(
                icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                label: const Text('打开独立浏览器窗口'),
                onPressed: _testOpenBrowser,
              ),
              FilledButton.icon(
                icon: const Icon(Icons.photo_library_outlined, size: 16),
                label: const Text('打开独立图片/视频窗口'),
                onPressed: _testOpenMediaViewer,
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.settings_outlined, size: 16),
                label: const Text('打开独立设置窗口'),
                onPressed: _testOpenSettings,
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF07C160),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                label: const Text('打开独立聊天窗口 (HWND)'),
                onPressed: _testOpenStandaloneChat,
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1E88E5),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.crop_free_rounded, size: 16),
                label: const Text('桌面截图测试 (Alt+A)'),
                onPressed: _testTriggerScreenCapture,
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.image_search_rounded, size: 16),
                label: const Text('读取剪贴板图片并确认 (Ctrl+V)'),
                onPressed: _testReadClipboardImage,
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.file_copy_rounded, size: 16),
                label: const Text('读取剪贴板文件并确认 (Ctrl+V)'),
                onPressed: _testReadClipboardFiles,
              ),
              FilledButton.tonalIcon(
                icon: const Icon(
                  Icons.photo_size_select_actual_outlined,
                  size: 16,
                ),
                label: const Text('模拟弹窗: 图片确认发送'),
                onPressed: _testMockImageConfirmDialog,
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.drive_folder_upload_outlined, size: 16),
                label: const Text('模拟弹窗: 多文件确认发送'),
                onPressed: _testMockFilesConfirmDialog,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 4. 执行状态与耗时
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        '执行状态: ',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _status,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color:
                              _status == '成功'
                                  ? Colors.green
                                  : _status == '失败'
                                  ? Colors.red
                                  : Colors.orange,
                        ),
                      ),
                      const Spacer(),
                      if (_elapsedMs > 0)
                        Text(
                          '耗时: $_elapsedMs ms',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1, thickness: 0.5),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text(
                        '返回结果:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        tooltip: '复制执行结果',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _lastResult));
                          showToast('已复制结果', type: ToastType.success);
                        },
                      ),
                    ],
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _lastResult,
                      style: const TextStyle(fontSize: 12, height: 1.4),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    const Text(
                      '异常信息:',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      color: Colors.red.withValues(alpha: 0.08),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.redAccent,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlatformBadge(String platform, bool supported) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          supported ? Icons.check_circle_rounded : Icons.cancel_rounded,
          size: 14,
          color: supported ? const Color(0xFF07C160) : Colors.grey,
        ),
        const SizedBox(width: 4),
        Text(platform, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}
