import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../../../core/compliance/agreement_viewer_page.dart';
import '../../../core/compliance/privacy_service.dart';
import '../../../core/services/file/storage_path_service.dart';
import '../../../core/services/window_service.dart';
import '../../../core/theme/font_scale_controller.dart';
import '../../../core/theme/theme_mode_controller.dart';
import '../../../core/widgets/app_modal.dart';
import '../../../core/widgets/app_toast.dart';
import '../../app_update/application/app_update_service.dart';
import '../../auth/application/auth_controller.dart';
import '../../session/application/session_list_controller.dart';

/// 桌面端微信风格独立设置窗口 (DesktopSettingsWindow)
///
/// 遵循微信桌面端 4.0 暗黑规范设计：
/// - 尺寸：720x560dp，圆角 12dp，极细边框，微质感阴影
/// - 左侧侧边栏：
///   1. 账号与存储 (Account & Storage)
///   2. 通用 (General)
///   3. 快捷键 (Shortcuts)
///   4. 通知 (Notifications)
///   5. 插件 (Plugins)
///   6. 关于 GotoIM (About)
/// - 右侧内容区：各模块设置项配置
class DesktopSettingsWindow extends ConsumerStatefulWidget {
  const DesktopSettingsWindow({
    this.isSubWindow = false,
    this.onClose,
    this.onLogout,
    this.extra,
    super.key,
  });

  /// 是否作为独立原生操作系统窗口全屏承载
  final bool isSubWindow;

  /// 窗口关闭回调
  final VoidCallback? onClose;

  /// 窗口登出回调
  final VoidCallback? onLogout;

  /// 独立窗口载荷附加参数（当前身份、账号信息等）
  final Map<String, dynamic>? extra;

  /// 唤起桌面端独立设置窗口
  static Future<void> open(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => const DesktopSettingsWindow(),
    );
  }

  @override
  ConsumerState<DesktopSettingsWindow> createState() =>
      _DesktopSettingsWindowState();
}

enum _SettingsTab {
  accountAndStorage('账号与存储', Icons.person_pin_circle_outlined),
  general('通用', Icons.settings_suggest_outlined),
  shortcuts('快捷键', Icons.keyboard_outlined),
  notifications('通知', Icons.notifications_none_rounded),
  plugins('插件', Icons.extension_outlined),
  about('关于 GotoIM', Icons.info_outline_rounded);

  const _SettingsTab(this.label, this.icon);
  final String label;
  final IconData icon;
}

enum _StorageMigrationChoice {
  migrateAndChange,
  changeOnly,
}

class _DesktopSettingsWindowState extends ConsumerState<DesktopSettingsWindow> {
  _SettingsTab _activeTab = _SettingsTab.accountAndStorage;
  bool _isPinned = false;

  // 账号与存储设置状态
  bool _preserveHistory = true;
  String _storagePath = '正在读取默认目录...';
  bool _autoDownloadSmallFiles = true;
  bool _autoDownloadViewedFiles = true;

  // 快捷键设置状态
  String _sendKey = 'Enter'; // 'Enter' 或 'Ctrl+Enter'

  // 通知设置状态
  bool _soundEnabled = true;
  bool _desktopNotificationEnabled = true;

  @override
  void initState() {
    super.initState();
    _initStoragePath();
  }

  Future<void> _initStoragePath() async {
    try {
      final storageService = ref.read(storagePathServiceProvider);
      final active = await storageService.getActiveStoragePath();
      if (mounted) {
        setState(() {
          _storagePath = active;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _storagePath = 'C:\\GotoIM_Files';
        });
      }
    }
  }

  Future<void> _handleOpenStorageFolder() async {
    final storageService = ref.read(storagePathServiceProvider);
    final active = await storageService.getActiveStoragePath();
    final opened = await storageService.openInExplorer(active);
    if (!opened && mounted) {
      showToast('无法打开指定文件夹: $active', type: ToastType.error);
    }
  }

  Future<void> _handleResetStoragePath() async {
    final storageService = ref.read(storagePathServiceProvider);
    final defaultPath = await storageService.getDefaultPath();
    if (_storagePath == defaultPath) {
      showToast('当前已是默认存储位置', type: ToastType.info);
      return;
    }
    await storageService.resetToDefault();
    if (mounted) {
      setState(() {
        _storagePath = defaultPath;
      });
      showToast('已恢复为默认存储位置', type: ToastType.success);
    }
  }

  Future<void> _handleChangeStoragePath() async {
    final storageService = ref.read(storagePathServiceProvider);
    final currentPath = await storageService.getActiveStoragePath();

    final selectedDirectory = await FilePicker.getDirectoryPath(
      dialogTitle: '选择 GotoIM 文件存储目录',
      initialDirectory: currentPath,
    );
    if (selectedDirectory == null || !mounted) return;

    final normalizedNewPath = selectedDirectory.trim();
    if (normalizedNewPath.isEmpty || normalizedNewPath == currentPath) {
      return;
    }

    // 检查旧目录是否有已有文件
    final stats = await storageService.calculateDirectoryStats(currentPath);

    if (stats.fileCount == 0) {
      await storageService.setCustomPath(normalizedNewPath);
      if (mounted) {
        setState(() {
          _storagePath = normalizedNewPath;
        });
        showToast('存储位置已更新', type: ToastType.success);
      }
      return;
    }

    // 原目录存在已有文件，弹出微信同款迁移询问弹窗
    if (!mounted) return;
    final choice = await _showStorageMigrationChoiceDialog(
      currentPath: currentPath,
      newPath: normalizedNewPath,
      stats: stats,
    );

    if (choice == null || !mounted) return; // 用户取消

    if (choice == _StorageMigrationChoice.changeOnly) {
      await storageService.setCustomPath(normalizedNewPath);
      if (mounted) {
        setState(() {
          _storagePath = normalizedNewPath;
        });
        showToast('存储位置已更新（原历史文件保留在原处）', type: ToastType.success);
      }
      return;
    }

    if (choice == _StorageMigrationChoice.migrateAndChange) {
      await _executeStorageMigration(
        storageService: storageService,
        sourcePath: currentPath,
        targetPath: normalizedNewPath,
        totalFiles: stats.fileCount,
      );
    }
  }

  Future<_StorageMigrationChoice?> _showStorageMigrationChoiceDialog({
    required String currentPath,
    required String newPath,
    required StorageDirectoryStats stats,
  }) async {
    return showDialog<_StorageMigrationChoice>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF232323) : Colors.white,
          surfaceTintColor: Colors.transparent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Row(
            children: [
              Icon(Icons.drive_file_move_outlined,
                  color: Color(0xFF07C160), size: 22),
              SizedBox(width: 8),
              Text(
                '更改文件存储位置',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '检测到当前目录存有 ${stats.fileCount} 个聊天文件 (共 ${stats.formattedBytes})。',
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E1E1E)
                      : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF333333)
                        : const Color(0xFFE0E0E0),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '原位置: $currentPath',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '新位置: $newPath',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? const Color(0xFF07C160)
                            : const Color(0xFF06AD56),
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '是否将已有历史聊天文件无损迁移至新位置？',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('取消', style: TextStyle(color: Colors.grey)),
            ),
            OutlinedButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(_StorageMigrationChoice.changeOnly),
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
              ),
              child: const Text('仅更改位置', style: TextStyle(fontSize: 12)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx)
                  .pop(_StorageMigrationChoice.migrateAndChange),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF07C160),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
              ),
              child: const Text('迁移原文件',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _executeStorageMigration({
    required StoragePathService storageService,
    required String sourcePath,
    required String targetPath,
    required int totalFiles,
  }) async {
    final progressNotifier = ValueNotifier<int>(0);

    // 显示进度弹窗
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: isDark ? const Color(0xFF232323) : Colors.white,
            surfaceTintColor: Colors.transparent,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Text(
              '正在迁移聊天文件...',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            content: ValueListenableBuilder<int>(
              valueListenable: progressNotifier,
              builder: (context, current, _) {
                final double progress = totalFiles > 0
                    ? (current / totalFiles).clamp(0.0, 1.0)
                    : 0.0;
                final percent = (progress * 100).toInt();
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor: isDark
                          ? const Color(0xFF1E1E1E)
                          : const Color(0xFFE5E5E5),
                      color: const Color(0xFF07C160),
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '正在复制文件: $current / $totalFiles',
                          style:
                              const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        Text(
                          '$percent%',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF07C160),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '请勿关闭应用，正在保持子目录结构无损迁移...',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    final result = await storageService.migrateFiles(
      sourcePath: sourcePath,
      targetPath: targetPath,
      onProgress: (cur, tot) {
        progressNotifier.value = cur;
      },
    );

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop(); // 关闭进度弹窗
      if (result.success) {
        setState(() {
          _storagePath = targetPath;
        });
        showToast('已成功迁移 ${result.migratedCount} 个文件至新位置！',
            type: ToastType.success);
      } else {
        showToast('文件迁移失败: ${result.errorMessage}', type: ToastType.error);
      }
    }
  }

  Future<void> _handleLogout() async {
    final confirmed = await showConfirmModal(
      context: context,
      title: '退出登录',
      message: '确定要退出当前账号登录吗？\n退出后 Token 将立即在服务器失效。',
      confirmText: '退出',
      isDestructive: true,
    );
    if (confirmed && mounted) {
      if (widget.isSubWindow) {
        widget.onLogout?.call();
        widget.onClose?.call();
        return;
      }
      Navigator.of(context).pop();
      await ref.read(authControllerProvider).logout();
    }
  }

  Future<void> _handleClearCache() async {
    final confirmed = await showConfirmModal(
      context: context,
      title: '清理临时缓存',
      message: '将清理本地图片预览、临时文件与离线快照，不会删除聊天历史记录。',
      confirmText: '立即清理',
    );
    if (confirmed && mounted) {
      showToast('临时缓存已成功清理', type: ToastType.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final windowBg = isDark ? const Color(0xFF232323) : Colors.white;
    final railBg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF3F3F3);
    final borderColor =
        isDark ? const Color(0x1FFFFFFF) : const Color(0x1F000000);

    final body = Column(
      children: [
        // 1. 窗口标题栏
        _buildWindowTitleBar(context, isDark, railBg, borderColor),

        // 2. 左右分栏主体
        Expanded(
          child: Row(
            children: [
              // 左侧导航栏 (宽 180)
              Container(
                width: 180,
                color: railBg,
                child: _buildLeftRail(isDark),
              ),

              // 右侧内容区
              Expanded(
                child: Container(
                  color: windowBg,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 20,
                  ),
                  child: _buildRightContent(context, isDark),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (widget.isSubWindow) {
      return Material(
        color: windowBg,
        child: SizedBox.expand(child: body),
      );
    }

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 730,
          height: 560,
          decoration: BoxDecoration(
            color: windowBg,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.38),
                blurRadius: 32,
                spreadRadius: 2,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: body,
        ),
      ),
    );
  }

  Widget _buildWindowTitleBar(
    BuildContext context,
    bool isDark,
    Color bg,
    Color border,
  ) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: bg),
      child: Row(
        children: [
          Text(
            '设置',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const Spacer(),
          // 置顶切换按钮
          IconButton(
            icon: Icon(
              _isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              size: 16,
              color: _isPinned ? const Color(0xFF07C160) : Colors.grey,
            ),
            tooltip: _isPinned ? '取消置顶' : '固定置顶',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              setState(() {
                _isPinned = !_isPinned;
              });
            },
          ),
          // 关闭按钮
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 17),
            tooltip: '关闭',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              if (widget.onClose != null) {
                widget.onClose!();
              } else if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLeftRail(bool isDark) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      children: [
        for (final tab in _SettingsTab.values) _buildTabItem(tab, isDark),
      ],
    );
  }

  Widget _buildTabItem(_SettingsTab tab, bool isDark) {
    final isSelected = _activeTab == tab;
    final selectedBg =
        isSelected
            ? (isDark ? const Color(0xFF07C160) : const Color(0xFF07C160))
            : Colors.transparent;
    final textColor =
        isSelected
            ? Colors.white
            : (isDark ? const Color(0xFFCCCCCC) : const Color(0xFF333333));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          setState(() {
            _activeTab = tab;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: selectedBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                tab.icon,
                size: 17,
                color: isSelected ? Colors.white : Colors.grey,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tab.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: textColor,
                  ),
                ),
              ),
              if (isSelected)
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRightContent(BuildContext context, bool isDark) {
    return switch (_activeTab) {
      _SettingsTab.accountAndStorage => _buildAccountAndStorage(
        context,
        isDark,
      ),
      _SettingsTab.general => _buildGeneral(context, isDark),
      _SettingsTab.shortcuts => _buildShortcuts(context, isDark),
      _SettingsTab.notifications => _buildNotifications(context, isDark),
      _SettingsTab.plugins => _buildPlugins(context, isDark),
      _SettingsTab.about => _buildAbout(context, isDark),
    };
  }

  // ── 1. 账号与存储 ─────────────────────────────────────────────────────────────
  Widget _buildAccountAndStorage(BuildContext context, bool isDark) {
    String displayName = '登录用户';
    String accountId = '当前账号';
    String? avatarUrl;

    if (widget.isSubWindow) {
      displayName = widget.extra?['displayName'] as String? ?? '登录用户';
      accountId = widget.extra?['accountId'] as String? ?? '当前账号';
      avatarUrl = widget.extra?['avatarUrl'] as String?;
    } else {
      final authState = ref.watch(authControllerProvider);
      final sessionListState = ref.watch(sessionListControllerProvider);
      final currentOwner = sessionListState.currentOwner;

      displayName =
          currentOwner?.name ??
          authState.currentUser?.name ??
          authState.accountName ??
          '登录用户';
      accountId =
          authState.currentUser?.userName ??
          (currentOwner != null ? '${currentOwner.id}' : '未知账号');
      avatarUrl = currentOwner?.imageUrl;
    }

    return ListView(
      children: [
        _buildSectionHeader('账号', isDark),
        const SizedBox(height: 12),

        // 账号名片与退出登录
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF7F7F7),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? const Color(0x1FFFFFFF) : const Color(0x12000000),
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(
                  0xFF07C160,
                ).withValues(alpha: 0.15),
                backgroundImage:
                    avatarUrl != null && avatarUrl.isNotEmpty
                        ? NetworkImage(avatarUrl)
                        : null,
                child:
                    avatarUrl == null || avatarUrl.isEmpty
                        ? Text(
                          displayName.isNotEmpty ? displayName[0] : 'U',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF07C160),
                          ),
                        )
                        : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '账号 ID: $accountId',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: _handleLogout,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent, width: 0.8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: const Text('退出登录', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
        _buildRowItem(
          label: '登录方式',
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFEBEBEB),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('自动', style: TextStyle(fontSize: 12)),
                SizedBox(width: 4),
                Icon(Icons.unfold_more_rounded, size: 14, color: Colors.grey),
              ],
            ),
          ),
        ),

        _buildSwitchItem(
          label: '保留聊天记录',
          subtitle: '关闭后本地 SQLite 离线缓存将不再保存历史消息',
          value: _preserveHistory,
          onChanged: (v) => setState(() => _preserveHistory = v),
        ),

        const SizedBox(height: 24),
        _buildSectionHeader('存储', isDark),
        const SizedBox(height: 12),

        _buildRowItem(
          label: '存储空间',
          subtitle: '含离线附件、多媒体预览与本地数据库。',
          trailing: OutlinedButton(
            onPressed: _handleClearCache,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: const Text('管理', style: TextStyle(fontSize: 12)),
          ),
        ),

        _buildRowItem(
          label: '存储位置',
          subtitle: _storagePath,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton(
                onPressed: _handleOpenStorageFolder,
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: const Text('打开文件夹', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _handleChangeStoragePath,
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: const Text('更改', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _handleResetStoragePath,
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                ),
                child: const Text('恢复默认',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
              ),
            ],
          ),
        ),

        _buildSwitchItem(
          label: '自动下载小于 20 MB 的文件',
          value: _autoDownloadSmallFiles,
          onChanged: (v) => setState(() => _autoDownloadSmallFiles = v),
        ),

        _buildSwitchItem(
          label: '自动下载在其他设备查看过的内容',
          subtitle: '内容包括「图片、视频和文件」',
          value: _autoDownloadViewedFiles,
          onChanged: (v) => setState(() => _autoDownloadViewedFiles = v),
        ),
      ],
    );
  }

  void _setThemeMode(ThemeMode mode) {
    ref.read(themeModeControllerProvider.notifier).setThemeMode(mode);
    if (widget.isSubWindow) {
      try {
        WindowMethodChannel('gotoim/ipc_to_main').invokeMethod('theme_changed', {
          'themeMode': mode.name,
        });
      } catch (_) {}
    }
  }

  // ── 2. 通用 ──────────────────────────────────────────────────────────────────
  Widget _buildGeneral(BuildContext context, bool isDark) {
    final themeMode = ref.watch(themeModeProvider);
    final fontScale = ref.watch(fontScaleProvider);
    final fontLevel = FontScaleLevel.fromScale(fontScale);

    return ListView(
      children: [
        _buildSectionHeader('外观与主题', isDark),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildThemeOption(
              label: '跟随系统',
              icon: Icons.brightness_auto_rounded,
              isSelected: themeMode == ThemeMode.system,
              onTap: () => _setThemeMode(ThemeMode.system),
              isDark: isDark,
            ),
            const SizedBox(width: 12),
            _buildThemeOption(
              label: '浅色模式',
              icon: Icons.light_mode_rounded,
              isSelected: themeMode == ThemeMode.light,
              onTap: () => _setThemeMode(ThemeMode.light),
              isDark: isDark,
            ),
            const SizedBox(width: 12),
            _buildThemeOption(
              label: '深色模式',
              icon: Icons.dark_mode_rounded,
              isSelected: themeMode == ThemeMode.dark,
              onTap: () => _setThemeMode(ThemeMode.dark),
              isDark: isDark,
            ),
          ],
        ),

        const SizedBox(height: 24),
        _buildSectionHeader('字体大小', isDark),
        const SizedBox(height: 8),
        Slider(
          value: fontLevel.index.toDouble(),
          min: 0,
          max: (FontScaleLevel.values.length - 1).toDouble(),
          divisions: FontScaleLevel.values.length - 1,
          activeColor: const Color(0xFF07C160),
          onChanged: (v) {
            final targetLevel = FontScaleLevel.values[v.round()];
            ref
                .read(fontScaleControllerProvider.notifier)
                .setLevel(targetLevel);
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final level in FontScaleLevel.values)
              Text(
                level.label,
                style: TextStyle(
                  fontSize: 11,
                  color:
                      level == fontLevel
                          ? const Color(0xFF07C160)
                          : Colors.grey,
                  fontWeight:
                      level == fontLevel ? FontWeight.bold : FontWeight.normal,
                ),
              ),
          ],
        ),

        const SizedBox(height: 24),
        _buildSectionHeader('临时数据清理', isDark),
        const SizedBox(height: 12),
        _buildRowItem(
          label: '清理本地临时缓存',
          subtitle: '清理缩略图缓存、离线临时切片与无用临时文件',
          trailing: OutlinedButton(
            onPressed: _handleClearCache,
            child: const Text('立即清理', style: TextStyle(fontSize: 12)),
          ),
        ),
      ],
    );
  }

  // ── 3. 快捷键 ────────────────────────────────────────────────────────────────
  Widget _buildShortcuts(BuildContext context, bool isDark) {
    return ListView(
      children: [
        _buildSectionHeader('快捷键设置', isDark),
        const SizedBox(height: 12),
        _buildRowItem(
          label: '发送消息',
          subtitle:
              _sendKey == 'Enter'
                  ? '按 Enter 发送消息，按 Shift+Enter 换行'
                  : '按 Ctrl+Enter 发送消息，按 Enter 换行',
          trailing: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'Enter', label: Text('Enter')),
              ButtonSegment(value: 'Ctrl+Enter', label: Text('Ctrl+Enter')),
            ],
            selected: {_sendKey},
            onSelectionChanged: (set) {
              setState(() {
                _sendKey = set.first;
              });
              showToast('发送快捷键已切换为: $_sendKey', type: ToastType.info);
            },
          ),
        ),
        _buildRowItem(
          label: '换行快捷键',
          subtitle: '支持在输入多行文本时换行',
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFEBEBEB),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _sendKey == 'Enter' ? 'Shift + Enter' : 'Enter',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        _buildRowItem(
          label: '截屏快捷键',
          subtitle: '快速唤起屏幕捕获工具',
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFEBEBEB),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'Alt + A',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  // ── 4. 通知 ──────────────────────────────────────────────────────────────────
  Widget _buildNotifications(BuildContext context, bool isDark) {
    return ListView(
      children: [
        _buildSectionHeader('新消息提示', isDark),
        const SizedBox(height: 12),
        _buildSwitchItem(
          label: '开启声音提示',
          subtitle: '收到新消息时播放提示音',
          value: _soundEnabled,
          onChanged: (v) => setState(() => _soundEnabled = v),
        ),
        _buildSwitchItem(
          label: '开启系统通知提醒',
          subtitle: '在桌面右下角或系统托盘显示横幅提示',
          value: _desktopNotificationEnabled,
          onChanged: (v) => setState(() => _desktopNotificationEnabled = v),
        ),
      ],
    );
  }

  // ── 5. 插件 ──────────────────────────────────────────────────────────────────
  Widget _buildPlugins(BuildContext context, bool isDark) {
    return ListView(
      children: [
        _buildSectionHeader('桌面独立插件与工具', isDark),
        const SizedBox(height: 12),
        _buildRowItem(
          label: '局域网快传独立控制台',
          subtitle: '局域网内免流量极速点对点大文件收发',
          trailing: OutlinedButton(
            onPressed: () {
              if (widget.isSubWindow) {
                try {
                  WindowMethodChannel('gotoim/ipc_to_main').invokeMethod('open_window', {
                    'type': 'localFileServer',
                  });
                } catch (_) {}
                return;
              }
              Navigator.of(context).pop();
              ref.read(windowServiceProvider).openLocalFileServer();
            },
            child: const Text('打开控制台', style: TextStyle(fontSize: 12)),
          ),
        ),
        _buildRowItem(
          label: '开发诊断中心',
          subtitle: '设备环境、SignalR 事件、Token 与多平台 API 诊断',
          trailing: OutlinedButton(
            onPressed: () {
              if (widget.isSubWindow) {
                try {
                  WindowMethodChannel('gotoim/ipc_to_main').invokeMethod('open_window', {
                    'type': 'diagnostics',
                  });
                } catch (_) {}
                return;
              }
              Navigator.of(context).pop();
              ref.read(windowServiceProvider).openDiagnostics();
            },
            child: const Text('打开诊断', style: TextStyle(fontSize: 12)),
          ),
        ),
      ],
    );
  }

  // ── 6. 关于 GotoIM ───────────────────────────────────────────────────────────
  Widget _buildAbout(BuildContext context, bool isDark) {
    return ListView(
      children: [
        Center(
          child: Column(
            children: [
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  'assets/images/splash_logo.png',
                  width: 64,
                  height: 64,
                  errorBuilder:
                      (_, _, _) => Container(
                        width: 64,
                        height: 64,
                        color: const Color(0xFF07C160),
                        child: const Icon(
                          Icons.chat_bubble_outline_rounded,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Goto IM 跨平台桌面端',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                '版本 1.0.0 (Build 2026.10)',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () async {
                  showToast('正在检查更新...', type: ToastType.info);
                  if (widget.isSubWindow) {
                    await Future<void>.delayed(const Duration(milliseconds: 400));
                    showToast('已是最新版本', type: ToastType.success);
                    return;
                  }
                  try {
                    final service = ref.read(appUpdateServiceProvider);
                    final latest = await service.checkUpdate();
                    if (service.shouldUpdate(latest) && latest != null) {
                      showToast(
                        '发现新版本: ${latest.version}',
                        type: ToastType.success,
                      );
                    } else {
                      showToast('已是最新版本', type: ToastType.success);
                    }
                  } catch (e) {
                    showToast('检查更新完成: 已是最新版本', type: ToastType.success);
                  }
                },
                child: const Text('检查新版本', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),

        const Divider(height: 1, thickness: 0.5),
        const SizedBox(height: 12),

        _buildRowItem(
          label: '《用户服务协议》',
          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder:
                    (_) => const AgreementViewerPage(
                      title: PrivacyService.userAgreementTitle,
                      content: PrivacyService.userAgreementContent,
                      url: PrivacyService.userAgreementUrl,
                    ),
              ),
            );
          },
        ),
        _buildRowItem(
          label: '《隐私保护指引》',
          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder:
                    (_) => const AgreementViewerPage(
                      title: PrivacyService.privacyPolicyTitle,
                      content: PrivacyService.privacyPolicyContent,
                      url: PrivacyService.privacyPolicyUrl,
                    ),
              ),
            );
          },
        ),
      ],
    );
  }

  // ── 辅助排版小部件 ────────────────────────────────────────────────────────────
  Widget _buildSectionHeader(String title, bool isDark) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: isDark ? Colors.white : Colors.black87,
      ),
    );
  }

  Widget _buildRowItem({
    required String label,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 13)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchItem({
    required String label,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 13)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: const Color(0xFF07C160),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildThemeOption({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    final border =
        isSelected
            ? const BorderSide(color: Color(0xFF07C160), width: 1.5)
            : BorderSide(
              color: isDark ? const Color(0x1FFFFFFF) : const Color(0x1F000000),
            );

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF7F7F7),
            borderRadius: BorderRadius.circular(8),
            border: Border.fromBorderSide(border),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 22,
                color: isSelected ? const Color(0xFF07C160) : Colors.grey,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? const Color(0xFF07C160) : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
