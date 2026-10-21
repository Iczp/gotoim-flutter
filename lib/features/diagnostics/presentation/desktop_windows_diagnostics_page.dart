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
import '../../../core/widgets/desktop_dialog.dart';
import '../../../core/widgets/desktop_tray_message_box.dart';
import '../../account/presentation/account_profile_page.dart';
import '../../chat/presentation/widgets/clipboard_files_confirm_dialog.dart';
import '../../chat/presentation/widgets/clipboard_image_confirm_dialog.dart';
import '../../contact/presentation/add_friend_page.dart';
import '../../group/presentation/create_group_page.dart';
import '../../search/presentation/search_page.dart';
import '../../session/presentation/login_devices_page.dart';

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
  final TextEditingController _videoUrlController = TextEditingController(
    text: 'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
  );
  final TextEditingController _unreadCountController = TextEditingController(
    text: '5',
  );
  final TextEditingController _profileNameController = TextEditingController(
    text: '张小龙',
  );
  final TextEditingController _profileDeptController = TextEditingController(
    text: '微信事业群 / 研发部',
  );
  final TextEditingController _profileStatusController = TextEditingController(
    text: '正在写代码...',
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
    _videoUrlController.dispose();
    _unreadCountController.dispose();
    _profileNameController.dispose();
    _profileDeptController.dispose();
    _profileStatusController.dispose();
    super.dispose();
  }

  void _resetDefaults() {
    setState(() {
      _urlController.text = 'https://news.qq.com';
      _urlTitleController.text = '腾讯新闻';
      _imageUrlController.text = 'https://picsum.photos/1200/800';
      _videoUrlController.text =
          'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4';
      _unreadCountController.text = '5';
      _profileNameController.text = '张小龙';
      _profileDeptController.text = '微信事业群 / 研发部';
      _profileStatusController.text = '正在写代码...';
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

  Future<void> _testOpenVideoViewer({bool cacheFirst = false}) async {
    final sw = Stopwatch()..start();
    setState(() {
      _status = '执行中';
      _error = null;
    });
    try {
      final url = _videoUrlController.text.trim();
      final item = MediaPreviewItem(
        id: url,
        messageId: 'video-diagnostic',
        type: MediaPreviewType.video,
        source: url,
        heroTag: url,
      );
      final localPath =
          cacheFirst
              ? await DefaultMediaDownloader.instance
                  .download(item)
                  .timeout(const Duration(seconds: 30))
              : null;
      if (cacheFirst && (localPath == null || localPath.isEmpty)) {
        throw StateError('未取得可播放的本地视频文件');
      }
      await ref
          .read(windowServiceProvider)
          .openMediaViewer(
            mediaUrl: url,
            title: '视频播放诊断',
            items: [
              MediaPreviewItem(
                id: url,
                messageId: 'video-diagnostic',
                localPath: localPath,
                type: MediaPreviewType.video,
                source: url,
                heroTag: url,
              ),
            ],
          );
      if (!mounted) return;
      setState(() {
        _status = '窗口已创建';
        _elapsedMs = sw.elapsedMilliseconds;
        _lastResult =
            '${cacheFirst ? '已下载并传入本地缓存。' : '直接网络播放。'}请在独立窗口确认视频画面、播放进度和关闭恢复；窗口创建不代表播放验证通过。';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = '失败';
          _error = '$error';
        });
      }
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

  Future<void> _testPrewarmSubWindows() async {
    final sw = Stopwatch()..start();
    setState(() {
      _status = '执行中...';
      _error = null;
    });
    try {
      final windowService = ref.read(windowServiceProvider);
      await windowService.prewarmProfileCard();
      await windowService.prewarmTrayFlyout();
      sw.stop();
      setState(() {
        _status = '成功';
        _elapsedMs = sw.elapsedMilliseconds;
        _lastResult =
            '已成功在后台预热常驻无边框子窗口：\n1. tool:profile_card (悬浮资料卡)\n2. tool:tray (托盘新消息悬浮窗)\n状态：常驻后台保持预热，鼠标悬浮或新消息到达呼出零延迟';
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

  Future<void> _testShowProfileCard() async {
    final sw = Stopwatch()..start();
    setState(() {
      _status = '执行中...';
      _error = null;
    });
    try {
      final windowService = ref.read(windowServiceProvider);
      final subjectData = {
        'id': 'diag_user_888',
        'displayName': _profileNameController.text.trim(),
        'name': _profileNameController.text.trim(),
        'department': _profileDeptController.text.trim(),
        'statusText': _profileStatusController.text.trim(),
        'gender': 1,
      };
      await windowService.showProfileCardAt(
        subjectData: subjectData,
        localRect: const Rect.fromLTWH(260, 240, 50, 50),
      );
      sw.stop();
      setState(() {
        _status = '成功';
        _elapsedMs = sw.elapsedMilliseconds;
        _lastResult =
            '已呼出悬浮无边框资料卡窗口\n姓名: ${_profileNameController.text}\n部门: ${_profileDeptController.text}\n状态: ${_profileStatusController.text}\n坐标: (260, 240)\n特性：无边框、阴影、移出自动隐藏、常驻后台不销毁';
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

  Future<void> _testHideProfileCard() async {
    final sw = Stopwatch()..start();
    setState(() {
      _status = '执行中...';
      _error = null;
    });
    try {
      final windowService = ref.read(windowServiceProvider);
      await windowService.hideProfileCard();
      sw.stop();
      setState(() {
        _status = '成功';
        _elapsedMs = sw.elapsedMilliseconds;
        _lastResult = '已成功隐藏悬浮资料卡窗口 (保持后台常驻，不销毁)';
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

  Future<void> _testNativeTrayFlyout() async {
    final sw = Stopwatch()..start();
    setState(() {
      _status = '执行中...';
      _error = null;
    });
    try {
      final windowService = ref.read(windowServiceProvider);
      await windowService.openTrayFlyout();
      sw.stop();
      setState(() {
        _status = '成功';
        _elapsedMs = sw.elapsedMilliseconds;
        _lastResult = '已成功调起原生无边框托盘新消息聚合浮窗 (屏幕右下角任务栏平滑滑出)';
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

  Future<void> _testMultiTabBrowserSequence() async {
    final sw = Stopwatch()..start();
    setState(() {
      _status = '执行中...';
      _error = null;
    });
    try {
      final windowService = ref.read(windowServiceProvider);
      await windowService.openWebBrowser(
        url: 'https://news.qq.com',
        title: '腾讯新闻',
      );
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await windowService.openWebBrowser(
        url: 'https://www.bing.com',
        title: '必应搜索',
      );
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await windowService.openWebBrowser(
        url: 'https://flutter.dev',
        title: 'Flutter 官网',
      );
      sw.stop();
      setState(() {
        _status = '成功';
        _elapsedMs = sw.elapsedMilliseconds;
        _lastResult =
            '已成功连续向桌面内置浏览器追加 3 个不同标签页：\n1. 腾讯新闻 (https://news.qq.com)\n2. 必应搜索 (https://www.bing.com)\n3. Flutter 官网 (https://flutter.dev)\n特性：打开新链接不覆盖已有页面，而是增加 Tab，各个标签页 WebView 独立隔离且滚动条与状态保留！';
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

  void _testOpenDesktopSearch() {
    showDesktopModalDialog<void>(
      context: context,
      title: '搜索会话与好友',
      width: 580,
      height: 600,
      child: const SearchPage(isDialog: true),
    );
    setState(() {
      _status = '成功';
      _lastResult = '已弹出桌面端居中搜索模态对话框 (消除全屏与移动端滑动条)';
    });
  }

  void _testOpenDesktopCreateGroup() {
    showDesktopModalDialog<void>(
      context: context,
      title: '发起群聊',
      width: 480,
      height: 560,
      child: const CreateGroupPage(isDialog: true),
    );
    setState(() {
      _status = '成功';
      _lastResult = '已弹出桌面端居中发起群聊模态对话框';
    });
  }

  void _testOpenDesktopAddFriend() {
    showDesktopModalDialog<void>(
      context: context,
      title: '添加好友',
      width: 520,
      height: 600,
      child: const AddFriendPage(isDialog: true),
    );
    setState(() {
      _status = '成功';
      _lastResult = '已弹出桌面端居中添加好友模态对话框';
    });
  }

  void _testOpenDesktopAccountProfile() {
    showDesktopModalDialog<void>(
      context: context,
      title: '个人信息',
      width: 500,
      height: 580,
      child: const AccountProfilePage(isDialog: true),
    );
    setState(() {
      _status = '成功';
      _lastResult = '已弹出桌面端居中个人信息模态对话框';
    });
  }

  void _testOpenDesktopLoginDevices() {
    showDesktopModalDialog<void>(
      context: context,
      title: '登录设备管理',
      width: 560,
      height: 520,
      child: const LoginDevicesPage(isDialog: true),
    );
    setState(() {
      _status = '成功';
      _lastResult = '已弹出桌面端居中登录设备管理模态对话框';
    });
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
        _lastResult =
            '主窗口已处理托盘角标更新请求（实际图标需目视确认）: $count\n支持平台: Windows / macOS / Linux';
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

          // 2. 常驻子窗口预热与复用状态监视
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
                        '常驻子窗口预热与复用状态监视',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.bolt_rounded, size: 16),
                        label: const Text('一键预热全部常驻窗口'),
                        onPressed: _testPrewarmSubWindows,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Consumer(
                    builder: (context, ref, _) {
                      final ws = ref.watch(windowServiceProvider);
                      final isProfileCardReady =
                          ws.isWindowOpen('tool:profile_card');
                      final isTrayReady = ws.isWindowOpen('tool:tray');
                      final isBrowserOpen = ws.isWindowOpen('tool:browser');
                      final isSettingsOpen = ws.isWindowOpen('tool:settings');

                      return Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          _buildWindowStatusChip(
                            '资料卡 (profile_card)',
                            isProfileCardReady,
                            '鼠标悬浮呼出 / 离开隐藏',
                          ),
                          _buildWindowStatusChip(
                            '托盘通知 (tray)',
                            isTrayReady,
                            '新消息右下角滑出 / 常驻不退出',
                          ),
                          _buildWindowStatusChip(
                            '浏览器 (browser)',
                            isBrowserOpen,
                            'Multi-Tab 多标签页复用',
                          ),
                          _buildWindowStatusChip(
                            '独立设置 (settings)',
                            isSettingsOpen,
                            '桌面居中模态独立视窗',
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 3. 输入参数
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
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _profileNameController,
                          decoration: const InputDecoration(
                            labelText: '资料卡测试姓名',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _profileDeptController,
                          decoration: const InputDecoration(
                            labelText: '测试部门 / 身份',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _profileStatusController,
                    decoration: const InputDecoration(
                      labelText: '资料卡个性签名 / 状态',
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
                  TextField(
                    controller: _videoUrlController,
                    decoration: const InputDecoration(
                      labelText: '视频测试 URL',
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

          // 4. 执行操作套件
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
                    '执行操作套件 (符合 AGENTS.md 规范)',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),

                  // ── 方向一：悬浮资料卡 ──
                  const Text(
                    '方向一：悬浮无边框资料卡独立窗口 (鼠标悬停呼出、离开隐藏、常驻不销毁)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        icon: const Icon(Icons.badge_outlined, size: 16),
                        label: const Text('呼出悬浮资料卡 (坐标 260, 240)'),
                        onPressed: _testShowProfileCard,
                      ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.visibility_off_outlined, size: 16),
                        label: const Text('隐藏悬浮资料卡 (常驻后台)'),
                        onPressed: _testHideProfileCard,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(height: 1, thickness: 0.5),
                  const SizedBox(height: 10),

                  // ── 方向二：托盘新消息悬浮窗 ──
                  const Text(
                    '方向二：托盘新消息轻量常驻悬浮窗 (预热与实时提醒、右下角滑出)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF07C160),
                        ),
                        icon: const Icon(Icons.mark_chat_unread_rounded, size: 16),
                        label: const Text('调起原生托盘常驻浮窗 (右下角滑出)'),
                        onPressed: _testNativeTrayFlyout,
                      ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                        label: const Text('应用内托盘浮窗 (模态预览)'),
                        onPressed: _testOpenTrayFlyout,
                      ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.add_comment_rounded, size: 16),
                        label: const Text('模拟新消息到达 (+1)'),
                        onPressed: _testSimulateMessage,
                      ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.playlist_add_check_rounded, size: 16),
                        label: const Text('注入测试未读数据 (Mock)'),
                        onPressed: _testLoadSampleData,
                      ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.notifications_active_rounded, size: 16),
                        label: const Text('更新托盘角标数字'),
                        onPressed: _testUpdateTrayBadge,
                      ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.menu_open, size: 16),
                        label: const Text('显示系统托盘菜单'),
                        onPressed: () => ref.read(trayServiceProvider).showContextMenu(),
                      ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.done_all_rounded, size: 16),
                        label: const Text('一键清空未读'),
                        onPressed: _testClearUnread,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(height: 1, thickness: 0.5),
                  const SizedBox(height: 10),

                  // ── 方向三：内置浏览器多标签页复用 ──
                  const Text(
                    '方向三：内置浏览器多标签页 (Multi-Tab) 复用机制 (打开新链接增加 Tab 不覆盖)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        icon: const Icon(Icons.tab_rounded, size: 16),
                        label: const Text('一键连续追加 3 个不同 Tab 复用测试'),
                        onPressed: _testMultiTabBrowserSequence,
                      ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                        label: const Text('打开当前输入 URL 浏览器窗口'),
                        onPressed: _testOpenBrowser,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(height: 1, thickness: 0.5),
                  const SizedBox(height: 10),

                  // ── 桌面居中模态对话框套件预览 ──
                  const Text(
                    '桌面居中模态对话框套件 (消除移动端全屏与底部滑动条)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.search_rounded, size: 16),
                        label: const Text('搜索会话与好友 (模态框)'),
                        onPressed: _testOpenDesktopSearch,
                      ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.group_add_rounded, size: 16),
                        label: const Text('发起群聊 (模态框)'),
                        onPressed: _testOpenDesktopCreateGroup,
                      ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.person_add_rounded, size: 16),
                        label: const Text('添加好友 (模态框)'),
                        onPressed: _testOpenDesktopAddFriend,
                      ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.account_box_rounded, size: 16),
                        label: const Text('个人信息 (模态框)'),
                        onPressed: _testOpenDesktopAccountProfile,
                      ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.devices_rounded, size: 16),
                        label: const Text('登录设备管理 (模态框)'),
                        onPressed: _testOpenDesktopLoginDevices,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(height: 1, thickness: 0.5),
                  const SizedBox(height: 10),

                  // ── 独立窗口视窗与多媒体 ──
                  const Text(
                    '媒体查看器、聊天独立窗口与剪贴板操作',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        icon: const Icon(Icons.photo_library_outlined, size: 16),
                        label: const Text('独立图片/视频窗口'),
                        onPressed: _testOpenMediaViewer,
                      ),
                      FilledButton.icon(
                        icon: const Icon(Icons.play_circle_outline, size: 16),
                        label: const Text('独立视频播放'),
                        onPressed: _testOpenVideoViewer,
                      ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.download_for_offline_outlined, size: 16),
                        label: const Text('下载后验证本地视频'),
                        onPressed: () => _testOpenVideoViewer(cacheFirst: true),
                      ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.settings_outlined, size: 16),
                        label: const Text('独立设置窗口'),
                        onPressed: _testOpenSettings,
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF07C160),
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                        label: const Text('独立聊天窗口 (HWND)'),
                        onPressed: _testOpenStandaloneChat,
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1E88E5),
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.crop_free_rounded, size: 16),
                        label: const Text('桌面截图 (Alt+A)'),
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
                ],
              ),
            ),
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

  Widget _buildWindowStatusChip(String title, bool active, String desc) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active
            ? const Color(0xFF07C160).withValues(alpha: 0.12)
            : Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: active
              ? const Color(0xFF07C160).withValues(alpha: 0.35)
              : Colors.grey.withValues(alpha: 0.2),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 14,
            color: active ? const Color(0xFF07C160) : Colors.grey,
          ),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? const Color(0xFF07C160) : null,
                ),
              ),
              Text(
                desc,
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
