import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app/application_providers.dart';
import '../../../core/capabilities/client_capability_models.dart';
import '../../../core/services/clipboard_service.dart';
import '../../../core/services/window_service.dart';
import '../../../core/widgets/app_toast.dart';
import '../local_file_server.dart';
import '../local_file_server_controller.dart';

/// 桌面端微信 4.0 风格局域网快传三栏主视图 (DesktopLocalFileServerSplitView)
///
/// 核心结构与「通讯录三栏视图」高度一致：
/// 1. 左栏（导航 Dock）：由应用外层 ApplicationShell / DesktopDockRail 统一承载；
/// 2. 中栏（290px，可拖拽调节宽度）：搜索栏、快传服务状态/终端快捷入口、共享目录分类与文件列表；
/// 3. 右栏（自适应画布）：在第三栏展示所选中文件的详细资料与操作，或快传服务状态管理与二维码、已连接终端详情。
class DesktopLocalFileServerSplitView extends ConsumerStatefulWidget {
  const DesktopLocalFileServerSplitView({super.key});

  @override
  ConsumerState<DesktopLocalFileServerSplitView> createState() =>
      _DesktopLocalFileServerSplitViewState();
}

class _DesktopLocalFileServerSplitViewState
    extends ConsumerState<DesktopLocalFileServerSplitView> {
  static const List<String> _presetFolders = [
    '/',
    '/图片',
    '/视频',
    '/文档',
    '/下载',
    '/聊天文件',
  ];

  late final LocalFileServerService _service;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String _currentPath = '/';
  List<SharedFile> _files = [];
  bool _isLoadingFiles = false;
  SharedFile? _selectedFile;
  String? _selectedQuickAction = 'server';
  String _searchKeyword = '';
  double _paneWidth = 290.0;

  Future<ClientWifiInfo>? _wifiInfo;
  late ClientNetworkStatus _networkStatus;
  StreamSubscription<ClientNetworkStatus>? _networkSubscription;

  @override
  void initState() {
    super.initState();
    _service = ref.read(localFileServerProvider)
      ..addListener(_onServiceChanged);

    _networkStatus = ClientNetworkStatus(
      types: const [ClientNetworkType.none],
      observedAt: DateTime.now(),
    );

    final capabilities = ref.read(clientCapabilityServiceProvider);
    _networkSubscription = capabilities.networkStatusChanges.listen((status) {
      if (mounted) setState(() => _networkStatus = status);
    });

    _refreshWifiInfo();
    _loadFiles();
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    _networkSubscription?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) {
      setState(() {});
      _loadFiles(silent: true);
    }
  }

  Future<void> _refreshWifiInfo() async {
    final capabilities = ref.read(clientCapabilityServiceProvider);
    final info = await capabilities.getWifiInfo();
    if (mounted) {
      setState(() {
        _wifiInfo = Future.value(info);
      });
    }
  }

  Future<void> _loadFiles({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() => _isLoadingFiles = true);
    }
    try {
      final list = await _service.listSharedFiles(_currentPath);
      if (mounted) {
        setState(() {
          _files = list;
          _isLoadingFiles = false;
          // 若之前选中的文件不在当前目录，同步清理
          if (_selectedFile != null &&
              !list.any((f) => f.path == _selectedFile!.path)) {
            _selectedFile = null;
            _selectedQuickAction ??= 'server';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingFiles = false);
      }
    }
  }

  Future<void> _switchFolder(String folderPath) async {
    setState(() {
      _currentPath = folderPath;
      _selectedFile = null;
      _searchController.clear();
      _searchKeyword = '';
    });
    await _loadFiles();
  }

  Future<void> _addFiles() async {
    try {
      final picked = await FilePicker.pickFiles(dialogTitle: '选择要共享的文件');
      if (picked.isEmpty) return;
      final filePaths = picked
          .map((f) => f.path)
          .whereType<String>()
          .where((p) => p.trim().isNotEmpty)
          .toList(growable: false);
      if (filePaths.isEmpty) return;

      await _service.addLocalFiles(_currentPath, filePaths);
      await _loadFiles();
      showToast('已添加 ${filePaths.length} 个文件到共享');
    } catch (e) {
      showToast('添加文件失败: $e', type: ToastType.error);
    }
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('新建文件夹'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '请输入文件夹名称',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () async {
                  final name = controller.text.trim();
                  if (name.isEmpty) return;
                  Navigator.pop(ctx);
                  try {
                    await _service.createSharedDirectory(_currentPath, name);
                    await _loadFiles();
                    showToast('已创建文件夹 $name');
                  } catch (e) {
                    showToast('创建文件夹失败: $e', type: ToastType.error);
                  }
                },
                child: const Text('创建'),
              ),
            ],
          ),
    );
    controller.dispose();
  }

  Future<void> _renameEntry(SharedFile file) async {
    final controller = TextEditingController(text: file.name);
    await showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text('重命名${file.isDirectory ? '文件夹' : '文件'}'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '新名称',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () async {
                  final newName = controller.text.trim();
                  if (newName.isEmpty || newName == file.name) return;
                  Navigator.pop(ctx);
                  try {
                    await _service.renameSharedEntry(file.path, newName);
                    await _loadFiles();
                    showToast('重命名成功');
                  } catch (e) {
                    showToast('重命名失败: $e', type: ToastType.error);
                  }
                },
                child: const Text('确认'),
              ),
            ],
          ),
    );
    controller.dispose();
  }

  Future<void> _deleteEntry(SharedFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('确认删除'),
            content: Text('确定要删除「${file.name}」吗？此操作不可逆。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('删除'),
              ),
            ],
          ),
    );
    if (confirmed == true) {
      try {
        await _service.deleteSharedEntry(file.path);
        if (_selectedFile?.path == file.path) {
          setState(() {
            _selectedFile = null;
            _selectedQuickAction = 'server';
          });
        }
        await _loadFiles();
        showToast('已删除 ${file.name}');
      } catch (e) {
        showToast('删除失败: $e', type: ToastType.error);
      }
    }
  }

  void _openFileOrFolder(SharedFile file) {
    if (file.isDirectory) {
      _switchFolder(file.path);
    } else {
      _service.openSharedFile(file.path);
    }
  }

  void _copyToClipboard(String text, String tip) {
    ref.read(clipboardServiceProvider).copy(text);
    showToast(tip);
  }

  Future<void> _showFileContextMenu(
    BuildContext context,
    TapDownDetails details,
    SharedFile file,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final position = RelativeRect.fromRect(
      details.globalPosition & const Size(1, 1),
      Offset.zero & overlay.size,
    );

    final isServerRunning =
        _service.state.status == LocalFileServerStatus.running;

    final action = await showMenu<String>(
      context: context,
      position: position,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        PopupMenuItem<String>(
          value: 'open',
          height: 36,
          child: Row(
            children: [
              Icon(
                file.isDirectory
                    ? Icons.folder_open_rounded
                    : Icons.open_in_new_rounded,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                file.isDirectory ? '打开文件夹' : '打开文件',
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'reveal',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.snippet_folder_outlined, size: 16),
              SizedBox(width: 8),
              Text('在文件资源管理器中显示', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        if (!file.isDirectory && isServerRunning)
          const PopupMenuItem<String>(
            value: 'copy_link',
            height: 36,
            child: Row(
              children: [
                Icon(Icons.link_rounded, size: 16),
                SizedBox(width: 8),
                Text('复制局域网下载链接', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
        const PopupMenuItem<String>(
          value: 'rename',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 16),
              SizedBox(width: 8),
              Text('重命名', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        const PopupMenuItem<String>(
          value: 'delete',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, size: 16, color: Colors.red),
              SizedBox(width: 8),
              Text('删除', style: TextStyle(fontSize: 13, color: Colors.red)),
            ],
          ),
        ),
      ],
    );

    if (action == null || !mounted) return;

    if (action == 'open') {
      _openFileOrFolder(file);
    } else if (action == 'reveal') {
      await _service.revealInExplorer(file.path);
    } else if (action == 'copy_link') {
      final url =
          '${_service.state.address}/api/files/content?path=${Uri.encodeComponent(file.path)}';
      _copyToClipboard(url, '已复制局域网下载链接');
    } else if (action == 'rename') {
      await _renameEntry(file);
    } else if (action == 'delete') {
      await _deleteEntry(file);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    final state = _service.state;
    final isServerRunning = state.status == LocalFileServerStatus.running;

    // 过滤文件
    final filteredFiles =
        _searchKeyword.isEmpty
            ? _files
            : _files
                .where(
                  (f) => f.name.toLowerCase().contains(
                    _searchKeyword.toLowerCase(),
                  ),
                )
                .toList();

    final listPaneBg =
        isDark ? const Color(0xFF232323) : const Color(0xFFF7F7F7);
    final dividerColor =
        isDark ? const Color(0x1FFFFFFF) : const Color(0x1F000000);

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        double effectivePaneWidth = _paneWidth;
        if (totalWidth.isFinite && totalWidth < 760) {
          final maxPane = (totalWidth - 360.0).clamp(180.0, 260.0);
          if (effectivePaneWidth > maxPane) {
            effectivePaneWidth = maxPane;
          }
        }

        return Row(
          children: [
            // ── 中栏：快传列表栏 (宽 effectivePaneWidth，与通讯录列表栏风格完全对齐) ──
            Container(
              width: effectivePaneWidth,
              color: listPaneBg,
              child: Column(
                children: [
                  const SizedBox(height: 12),

                  // 1. 顶部搜索框
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Container(
                      height: 32,
                      decoration: BoxDecoration(
                        color:
                            isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(fontSize: 12.5),
                        decoration: InputDecoration(
                          hintText: '搜索共享文件或文件夹',
                          hintStyle: TextStyle(
                            fontSize: 12.5,
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.6,
                            ),
                          ),
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            size: 16,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 30,
                          ),
                          suffixIcon:
                              _searchKeyword.isNotEmpty
                                  ? IconButton(
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 14,
                                    ),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchKeyword = '');
                                    },
                                  )
                                  : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 7,
                          ),
                        ),
                        onChanged:
                            (val) => setState(() => _searchKeyword = val),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // 2. 快捷功能入口与共享文件列表
                  Expanded(
                    child: ListView(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      children: [
                        // 快捷功能项：与通讯录的「新的朋友/群聊」一致
                        if (_searchKeyword.isEmpty) ...[
                          _QuickActionRow(
                            icon: Icons.wifi_tethering_rounded,
                            iconBgColor:
                                isServerRunning
                                    ? const Color(0xFF07C160) // 微信经典绿
                                    : Colors.grey.shade600,
                            title: '快传服务与二维码',
                            subtitle: isServerRunning ? '服务运行中' : '服务已停止',
                            isSelected:
                                _selectedQuickAction == 'server' &&
                                _selectedFile == null,
                            onTap: () {
                              setState(() {
                                _selectedQuickAction = 'server';
                                _selectedFile = null;
                              });
                            },
                          ),
                          _QuickActionRow(
                            icon: Icons.devices_rounded,
                            iconBgColor: const Color(0xFF2782D7),
                            title: '已连接终端',
                            subtitle:
                                state.terminals.isNotEmpty
                                    ? '${state.terminals.length} 台设备已连接'
                                    : '暂无连接终端',
                            isSelected:
                                _selectedQuickAction == 'terminals' &&
                                _selectedFile == null,
                            badgeCount: state.terminals.length,
                            onTap: () {
                              setState(() {
                                _selectedQuickAction = 'terminals';
                                _selectedFile = null;
                              });
                            },
                          ),
                          Divider(
                            height: 1,
                            thickness: 0.5,
                            color: dividerColor,
                          ),
                        ],

                        // 3. 目录分类与操作小工具栏
                        _DirectoryToolbar(
                          currentPath: _currentPath,
                          folders: _presetFolders,
                          onSelectFolder: _switchFolder,
                          onAddFiles: _addFiles,
                          onCreateFolder: _createFolder,
                          onRevealRoot:
                              () => _service.revealInExplorer(_currentPath),
                        ),

                        Divider(height: 1, thickness: 0.5, color: dividerColor),

                        // 4. 当前目录下文件列表
                        if (_isLoadingFiles)
                          const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          )
                        else if (filteredFiles.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(28),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.folder_open_outlined,
                                    size: 36,
                                    color: colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.35),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _searchKeyword.isNotEmpty
                                        ? '未找到匹配项'
                                        : '此文件夹为空\n点击上方加号添加文件',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.onSurfaceVariant
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          for (final file in filteredFiles)
                            _SharedFileItemRow(
                              file: file,
                              isSelected: _selectedFile?.path == file.path,
                              onTap: () {
                                setState(() {
                                  _selectedFile = file;
                                  _selectedQuickAction = null;
                                });
                              },
                              onDoubleTap: () => _openFileOrFolder(file),
                              onSecondaryTapDown:
                                  (details) => _showFileContextMenu(
                                    context,
                                    details,
                                    file,
                                  ),
                            ),

                        if (filteredFiles.isNotEmpty && _searchKeyword.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: Text(
                                '当前目录共有 ${filteredFiles.length} 项',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── 左右拖拽调节宽度的垂直分割手柄 ──────────────────────────
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) {
                setState(() {
                  final maxAllowed = (totalWidth.isFinite
                          ? totalWidth - 320.0
                          : 480.0)
                      .clamp(220.0, 480.0);
                  _paneWidth = (_paneWidth + details.delta.dx).clamp(
                    180.0,
                    maxAllowed,
                  );
                });
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: Container(
                  width: 5,
                  color: Colors.transparent,
                  child: Center(
                    child: Container(width: 0.5, color: dividerColor),
                  ),
                ),
              ),
            ),

            // ── 第三栏：右侧主画布（展示文件详情卡片 / 服务管理与二维码 / 终端） ────
            Expanded(
              child:
                  _selectedFile != null
                      ? _DesktopFileDetailCanvas(
                        file: _selectedFile!,
                        isServerRunning: isServerRunning,
                        serverAddress: state.address,
                        onOpen: () => _openFileOrFolder(_selectedFile!),
                        onReveal:
                            () =>
                                _service.revealInExplorer(_selectedFile!.path),
                        onCopyLink: () {
                          final url =
                              '${state.address}/api/files/content?path=${Uri.encodeComponent(_selectedFile!.path)}';
                          _copyToClipboard(url, '已复制局域网下载链接');
                        },
                        onRename: () => _renameEntry(_selectedFile!),
                        onDelete: () => _deleteEntry(_selectedFile!),
                      )
                      : _selectedQuickAction == 'terminals'
                      ? _DesktopTerminalsCanvas(service: _service, state: state)
                      : _DesktopServerManagementCanvas(
                        service: _service,
                        state: state,
                        wifiInfo: _wifiInfo,
                        networkStatus: _networkStatus,
                        onRefreshWifi: _refreshWifiInfo,
                        onAddFiles: _addFiles,
                        onCreateFolder: _createFolder,
                        onRevealExplorer:
                            () => _service.revealInExplorer(_currentPath),
                        onCopyAddress: () {
                          if (state.address != null) {
                            _copyToClipboard(state.address!, '已复制访问地址到剪贴板');
                          }
                        },
                        onOpenBrowser: () {
                          if (state.address != null) {
                            ref
                                .read(windowServiceProvider)
                                .openWebBrowser(
                                  url: state.address!,
                                  title: '局域网快传 Web 端',
                                );
                          }
                        },
                      ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 中栏快捷功能项组件（与通讯录中的 _QuickActionRow 风格一致）
// ─────────────────────────────────────────────────────────────────────────────
class _QuickActionRow extends StatelessWidget {
  const _QuickActionRow({
    required this.icon,
    required this.iconBgColor,
    required this.title,
    this.subtitle,
    required this.isSelected,
    required this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final Color iconBgColor;
  final String title;
  final String? subtitle;
  final bool isSelected;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final selectedBg =
        isDark
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.black.withValues(alpha: 0.08);

    return InkWell(
      onTap: onTap,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        color: isSelected ? selectedBg : Colors.transparent,
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, color: Colors.white, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (badgeCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badgeCount',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 目录切换与操作小工具栏
// ─────────────────────────────────────────────────────────────────────────────
class _DirectoryToolbar extends StatelessWidget {
  const _DirectoryToolbar({
    required this.currentPath,
    required this.folders,
    required this.onSelectFolder,
    required this.onAddFiles,
    required this.onCreateFolder,
    required this.onRevealRoot,
  });

  final String currentPath;
  final List<String> folders;
  final ValueChanged<String> onSelectFolder;
  final VoidCallback onAddFiles;
  final VoidCallback onCreateFolder;
  final VoidCallback onRevealRoot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '共享目录',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.7,
                  ),
                ),
              ),
              const Spacer(),
              Tooltip(
                message: '新建文件夹',
                child: InkWell(
                  onTap: onCreateFolder,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.create_new_folder_outlined,
                      size: 17,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: '添加文件到共享',
                child: InkWell(
                  onTap: onAddFiles,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.note_add_outlined,
                      size: 17,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: '在系统文件资源管理器中打开',
                child: InkWell(
                  onTap: onRevealRoot,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.folder_open_rounded,
                      size: 17,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // 水平滚动分类芯片
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children:
                  folders.map((folder) {
                    final isSelected = currentPath == folder;
                    final label = folder == '/' ? '全部' : folder.substring(1);
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: isSelected,
                        onSelected: (_) => onSelectFolder(folder),
                        visualDensity: VisualDensity.compact,
                        labelStyle: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        selectedColor:
                            isDark
                                ? theme.colorScheme.primary.withValues(
                                  alpha: 0.3,
                                )
                                : theme.colorScheme.primary.withValues(
                                  alpha: 0.15,
                                ),
                      ),
                    );
                  }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 单个共享文件条目行（中栏列表行）
// ─────────────────────────────────────────────────────────────────────────────
class _SharedFileItemRow extends StatelessWidget {
  const _SharedFileItemRow({
    required this.file,
    required this.isSelected,
    required this.onTap,
    required this.onDoubleTap,
    required this.onSecondaryTapDown,
  });

  final SharedFile file;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final GestureTapDownCallback onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final selectedBg =
        isDark
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.black.withValues(alpha: 0.08);

    return InkWell(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onSecondaryTapDown: onSecondaryTapDown,
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        color: isSelected ? selectedBg : Colors.transparent,
        child: Row(
          children: [
            _FileIconBadge(file: file, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    file.isDirectory
                        ? '文件夹 · ${_formatDate(file.modifiedAt)}'
                        : '${_formatSize(file.size)} · ${_formatDate(file.modifiedAt)}',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.65,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 第三栏：文件详情主画布 (_DesktopFileDetailCanvas)
// ─────────────────────────────────────────────────────────────────────────────
class _DesktopFileDetailCanvas extends StatelessWidget {
  const _DesktopFileDetailCanvas({
    required this.file,
    required this.isServerRunning,
    required this.serverAddress,
    required this.onOpen,
    required this.onReveal,
    required this.onCopyLink,
    required this.onRename,
    required this.onDelete,
  });

  final SharedFile file;
  final bool isServerRunning;
  final String? serverAddress;
  final VoidCallback onOpen;
  final VoidCallback onReveal;
  final VoidCallback onCopyLink;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    final directDownloadUrl =
        isServerRunning && serverAddress != null
            ? '$serverAddress/api/files/content?path=${Uri.encodeComponent(file.path)}'
            : null;

    return Container(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 大文件图标
                _FileIconBadge(file: file, size: 76, iconSize: 42),
                const SizedBox(height: 20),

                // 文件名
                SelectableText(
                  file.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),

                // 虚拟路径标签
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color:
                        isDark
                            ? Colors.white10
                            : Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    file.path,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // 文件元数据卡片
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color:
                        isDark
                            ? Colors.white.withValues(alpha: 0.04)
                            : Colors.black.withValues(alpha: 0.025),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.black12,
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      _MetaRow(
                        label: '类型',
                        value:
                            file.isDirectory
                                ? '文件夹'
                                : _fileExtensionName(file.name),
                      ),
                      const Divider(height: 16, thickness: 0.5),
                      if (!file.isDirectory) ...[
                        _MetaRow(label: '大小', value: _formatSize(file.size)),
                        const Divider(height: 16, thickness: 0.5),
                      ],
                      _MetaRow(
                        label: '修改时间',
                        value:
                            '${file.modifiedAt.year}-${file.modifiedAt.month.toString().padLeft(2, '0')}-${file.modifiedAt.day.toString().padLeft(2, '0')} ${file.modifiedAt.hour.toString().padLeft(2, '0')}:${file.modifiedAt.minute.toString().padLeft(2, '0')}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // 核心操作按钮组
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: onOpen,
                      icon: Icon(
                        file.isDirectory
                            ? Icons.folder_open_rounded
                            : Icons.open_in_new_rounded,
                        size: 18,
                      ),
                      label: Text(file.isDirectory ? '进入文件夹' : '打开文件'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: onReveal,
                      icon: const Icon(Icons.snippet_folder_outlined, size: 18),
                      label: const Text('在本地目录中显示'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                    if (!file.isDirectory && isServerRunning)
                      OutlinedButton.icon(
                        onPressed: onCopyLink,
                        icon: const Icon(Icons.link_rounded, size: 18),
                        label: const Text('复制局域网下载链接'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: onRename,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('重命名'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: onDelete,
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        size: 18,
                        color: Colors.red,
                      ),
                      label: const Text(
                        '删除共享',
                        style: TextStyle(color: Colors.red),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: Colors.red.withValues(alpha: 0.5),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),

                // 局域网独立文件扫码下载卡片
                if (!file.isDirectory && directDownloadUrl != null) ...[
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color:
                          isDark
                              ? Colors.white.withValues(alpha: 0.03)
                              : const Color(0xFFF9F9F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? Colors.white12 : Colors.black12,
                        width: 0.5,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.qr_code_2_rounded,
                              size: 18,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              '手机扫码直连下载',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: QrImageView(
                            data: directDownloadUrl,
                            size: 130,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '同 Wi-Fi 下手机相机扫码即可直接免安装高速下载',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 第三栏：服务管理与二维码画布 (_DesktopServerManagementCanvas)
// ─────────────────────────────────────────────────────────────────────────────
class _DesktopServerManagementCanvas extends StatelessWidget {
  const _DesktopServerManagementCanvas({
    required this.service,
    required this.state,
    required this.wifiInfo,
    required this.networkStatus,
    required this.onRefreshWifi,
    required this.onAddFiles,
    required this.onCreateFolder,
    required this.onRevealExplorer,
    required this.onCopyAddress,
    required this.onOpenBrowser,
  });

  final LocalFileServerService service;
  final LocalFileServerState state;
  final Future<ClientWifiInfo>? wifiInfo;
  final ClientNetworkStatus networkStatus;
  final VoidCallback onRefreshWifi;
  final VoidCallback onAddFiles;
  final VoidCallback onCreateFolder;
  final VoidCallback onRevealExplorer;
  final VoidCallback onCopyAddress;
  final VoidCallback onOpenBrowser;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    final isRunning = state.status == LocalFileServerStatus.running;

    return Container(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(36),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. 服务主状态横幅
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors:
                          isRunning
                              ? [
                                const Color(0xFF07C160).withValues(alpha: 0.15),
                                const Color(0xFF07C160).withValues(alpha: 0.05),
                              ]
                              : [
                                Colors.grey.withValues(alpha: 0.15),
                                Colors.grey.withValues(alpha: 0.05),
                              ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color:
                          isRunning
                              ? const Color(0xFF07C160).withValues(alpha: 0.4)
                              : Colors.grey.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color:
                              isRunning
                                  ? const Color(0xFF07C160)
                                  : Colors.grey.shade600,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isRunning
                              ? Icons.wifi_tethering_rounded
                              : Icons.wifi_tethering_off_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '局域网极速快传服务',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isRunning
                                  ? '服务正在运行 · 随时可局域网免安装互传文件'
                                  : '服务已停止 · 启动后同 Wi-Fi 终端可扫码访问',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed:
                            state.status == LocalFileServerStatus.starting
                                ? null
                                : (isRunning ? service.stop : service.start),
                        icon: Icon(
                          isRunning
                              ? Icons.stop_circle_outlined
                              : Icons.play_arrow_rounded,
                          size: 18,
                        ),
                        label: Text(isRunning ? '停止服务' : '启动服务'),
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              isRunning
                                  ? Colors.red.shade700
                                  : const Color(0xFF07C160),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // 2. Wi-Fi 网络状态卡片
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isDark ? Colors.white12 : Colors.black12,
                      width: 0.5,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: FutureBuilder<ClientWifiInfo>(
                      future: wifiInfo,
                      builder: (context, snapshot) {
                        final wifi = snapshot.data;
                        final hasWifi =
                            networkStatus.types.contains(
                              ClientNetworkType.wifi,
                            ) ||
                            wifi?.ssid != null;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  hasWifi
                                      ? Icons.wifi_rounded
                                      : Icons.network_check_rounded,
                                  size: 20,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  hasWifi ? '当前 Wi-Fi 网络' : '网络连接状态',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Spacer(),
                                TextButton.icon(
                                  onPressed: onRefreshWifi,
                                  icon: const Icon(
                                    Icons.refresh_rounded,
                                    size: 16,
                                  ),
                                  label: const Text('刷新网络'),
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _MetaRow(
                              label: 'Wi-Fi 名称 (SSID)',
                              value: wifi?.ssid ?? '局域网在线',
                            ),
                            const Divider(height: 12, thickness: 0.5),
                            _MetaRow(
                              label: '本机内网 IPv4',
                              value: wifi?.ipAddress ?? '127.0.0.1',
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 3. Web 访问与扫码二维码卡片（服务运行态展示）
                if (isRunning && state.address != null) ...[
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isDark ? Colors.white12 : Colors.black12,
                        width: 0.5,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Text(
                            '同网络设备免安装访问',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '任意手机、平板或电脑连接相同 Wi-Fi，用浏览器打开或直接扫码：',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Web 访问链接框
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  isDark
                                      ? Colors.white10
                                      : Colors.black.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: SelectableText(
                                    state.address!,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: '复制链接',
                                  icon: const Icon(
                                    Icons.copy_rounded,
                                    size: 18,
                                  ),
                                  onPressed: onCopyAddress,
                                ),
                                IconButton(
                                  tooltip: '在浏览器中打开',
                                  icon: const Icon(
                                    Icons.open_in_browser_rounded,
                                    size: 18,
                                  ),
                                  onPressed: onOpenBrowser,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 二维码
                          if (state.qrLoginUrl != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: QrImageView(
                                data: state.qrLoginUrl!,
                                size: 160,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '微信、手机相机或浏览器扫一扫即可免密互传',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // 4. 底部快捷操作条
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: onAddFiles,
                      icon: const Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 18,
                      ),
                      label: const Text('添加文件到共享'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: onCreateFolder,
                      icon: const Icon(
                        Icons.create_new_folder_outlined,
                        size: 18,
                      ),
                      label: const Text('新建共享文件夹'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onRevealExplorer,
                      icon: const Icon(Icons.folder_shared_outlined, size: 18),
                      label: const Text('打开本地共享根目录'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 第三栏：已连接终端画布 (_DesktopTerminalsCanvas)
// ─────────────────────────────────────────────────────────────────────────────
class _DesktopTerminalsCanvas extends StatelessWidget {
  const _DesktopTerminalsCanvas({required this.service, required this.state});

  final LocalFileServerService service;
  final LocalFileServerState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    final terminals = state.terminals;
    final recent = service.recentTerminals;

    return Container(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: ListView(
        padding: const EdgeInsets.all(32),
        children: [
          Row(
            children: [
              Icon(Icons.devices_rounded, size: 22, color: colorScheme.primary),
              const SizedBox(width: 10),
              const Text(
                '已连接设备与终端协同',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '在线: ${terminals.length} 台',
                style: TextStyle(
                  fontSize: 12.5,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (terminals.isEmpty)
            Container(
              padding: const EdgeInsets.all(36),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color:
                    isDark
                        ? Colors.white10
                        : Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.devices_other_rounded,
                    size: 48,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 12),
                  const Text('暂无终端连接'),
                  const SizedBox(height: 4),
                  Text(
                    '同 Wi-Fi 设备扫码或访问地址后即可在此协同管理',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.6,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            for (final terminal in terminals)
              Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isDark ? Colors.white12 : Colors.black12,
                    width: 0.5,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          _platformIcon(terminal.platform),
                          color: colorScheme.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  terminal.name,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF07C160,
                                    ).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    terminal.status.name,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      color: Color(0xFF07C160),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'IP: ${terminal.ip} · 平台: ${terminal.platform}',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              '连接时间: ${terminal.connectedAt.hour.toString().padLeft(2, '0')}:${terminal.connectedAt.minute.toString().padLeft(2, '0')}',
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            () => service.disconnectTerminal(terminal.id),
                        icon: const Icon(Icons.link_off_rounded, size: 16),
                        label: const Text('断开'),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

          if (recent.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              '历史连接设备',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            for (final terminal in recent)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(_platformIcon(terminal.platform)),
                title: Text(
                  terminal.name,
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: Text(
                  'IP: ${terminal.ip} · 已离线',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
          ],
        ],
      ),
    );
  }

  IconData _platformIcon(String platform) {
    final lower = platform.toLowerCase();
    if (lower.contains('android')) return Icons.android_rounded;
    if (lower.contains('ios') ||
        lower.contains('iphone') ||
        lower.contains('ipad')) {
      return Icons.phone_iphone_rounded;
    }
    if (lower.contains('windows')) return Icons.desktop_windows_rounded;
    if (lower.contains('mac') || lower.contains('darwin')) {
      return Icons.laptop_mac_rounded;
    }
    if (lower.contains('linux')) return Icons.computer_rounded;
    return Icons.devices_other_rounded;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 工具组件与助手函数
// ─────────────────────────────────────────────────────────────────────────────
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
          ),
        ),
        const Spacer(),
        SelectableText(
          value,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

class _FileIconBadge extends StatelessWidget {
  const _FileIconBadge({required this.file, required this.size, this.iconSize});

  final SharedFile file;
  final double size;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _resolveFileIcon(file);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.26),
      ),
      child: Center(
        child: Icon(icon, color: color, size: iconSize ?? (size * 0.58)),
      ),
    );
  }
}

(IconData, Color) _resolveFileIcon(SharedFile file) {
  if (file.isDirectory) {
    return (Icons.folder_rounded, Colors.amber.shade700);
  }
  final ext =
      file.name.contains('.') ? file.name.split('.').last.toLowerCase() : '';
  switch (ext) {
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
    case 'webp':
    case 'svg':
    case 'bmp':
      return (Icons.image_rounded, Colors.teal);
    case 'mp4':
    case 'mov':
    case 'mkv':
    case 'avi':
    case 'flv':
    case 'webm':
      return (Icons.movie_rounded, Colors.purple);
    case 'mp3':
    case 'wav':
    case 'm4a':
    case 'flac':
    case 'aac':
      return (Icons.music_note_rounded, Colors.orange);
    case 'pdf':
      return (Icons.picture_as_pdf_rounded, Colors.red.shade700);
    case 'doc':
    case 'docx':
      return (Icons.description_rounded, Colors.blue.shade700);
    case 'xls':
    case 'xlsx':
    case 'csv':
      return (Icons.table_chart_rounded, Colors.green.shade700);
    case 'ppt':
    case 'pptx':
      return (Icons.slideshow_rounded, Colors.deepOrange);
    case 'zip':
    case 'rar':
    case '7z':
    case 'tar':
    case 'gz':
      return (Icons.folder_zip_rounded, Colors.amber.shade800);
    case 'dart':
    case 'js':
    case 'ts':
    case 'json':
    case 'py':
    case 'html':
    case 'css':
      return (Icons.code_rounded, Colors.blueGrey);
    default:
      return (Icons.insert_drive_file_rounded, Colors.grey.shade700);
  }
}

String _fileExtensionName(String fileName) {
  if (!fileName.contains('.')) return '未知类型文件';
  final ext = fileName.split('.').last.toUpperCase();
  return '$ext 文件';
}

String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
}

String _formatDate(DateTime date) {
  final now = DateTime.now();
  if (date.year == now.year && date.month == now.month && date.day == now.day) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
  return '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
