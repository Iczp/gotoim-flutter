import 'dart:io';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/desktop_dialog.dart';
import '../local_file_server.dart';
import '../local_file_server_controller.dart';

class SharedFileManagerPage extends StatelessWidget {
  const SharedFileManagerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SharedFileManagerView(embedded: false);
  }
}

class SharedFileManagerView extends ConsumerStatefulWidget {
  const SharedFileManagerView({this.embedded = false, super.key});

  final bool embedded;

  @override
  ConsumerState<SharedFileManagerView> createState() =>
      _SharedFileManagerViewState();
}

class _SharedFileManagerViewState extends ConsumerState<SharedFileManagerView> {
  static const folders = ['/', '/图片', '/视频', '/文档', '/下载', '/聊天文件'];
  late final LocalFileServerService service;
  String path = '/';
  bool grid = false;
  bool compact = false;

  @override
  void initState() {
    super.initState();
    service = ref.read(localFileServerProvider)..addListener(refresh);
  }

  @override
  void dispose() {
    service.removeListener(refresh);
    super.dispose();
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  void open(SharedFile file) {
    if (file.isDirectory) {
      setState(() => path = file.path);
    } else {
      service.openSharedFile(file.path);
    }
  }

  Future<void> createFolder(BuildContext c) async {
    final ctl = TextEditingController();
    await showDialog<void>(
      context: c,
      builder:
          (d) => AlertDialog(
            title: const Text('新建文件夹'),
            content: CupertinoTextField(
              controller: ctl,
              autofocus: true,
              placeholder: '文件夹名称',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(d),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () async {
                  if (ctl.text.trim().isEmpty) return;
                  Navigator.pop(d);
                  await service.createSharedDirectory(path, ctl.text.trim());
                  refresh();
                },
                child: const Text('创建'),
              ),
            ],
          ),
    );
    ctl.dispose();
  }

  Future<void> addFiles(BuildContext context) async {
    try {
      final picked = await FilePicker.pickFiles(
        dialogTitle: '选择要共享的文件',
      );
      if (picked.isNotEmpty) {
        final paths = picked.map((f) => f.path).whereType<String>().toList();
        if (paths.isNotEmpty) {
          await service.addLocalFiles(path, paths);
          if (context.mounted) {
            showToast('已添加 ${paths.length} 个文件到共享目录', type: ToastType.success);
          }
          refresh();
        }
      }
    } catch (e) {
      if (context.mounted) {
        showToast('添加文件失败: $e', type: ToastType.error);
      }
    }
  }

  Future<void> revealFolder(BuildContext context) async {
    try {
      await service.revealInExplorer(path);
    } catch (e) {
      if (context.mounted) {
        showToast('打开文件夹失败: $e', type: ToastType.error);
      }
    }
  }

  Future<void> menu(SharedFile f) async {
    final isDesktop = (!kIsWeb &&
            (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) ||
        MediaQuery.sizeOf(context).width >= 720;

    if (isDesktop) {
      await showDesktopModalDialog<void>(
        context: context,
        title: f.name,
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!f.isDirectory)
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: const Text('系统方式打开'),
                onTap: () {
                  Navigator.pop(context);
                  service.openSharedFile(f.path);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context);
                await service.deleteSharedEntry(f.path);
                refresh();
              },
            ),
          ],
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      builder:
          (s) => SafeArea(
            child: Wrap(
              children: [
                if (!f.isDirectory)
                  ListTile(
                    leading: const Icon(Icons.open_in_new),
                    title: const Text('系统方式打开'),
                    onTap: () {
                      Navigator.pop(s);
                      service.openSharedFile(f.path);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('删除', style: TextStyle(color: Colors.red)),
                  onTap: () async {
                    Navigator.pop(s);
                    await service.deleteSharedEntry(f.path);
                    refresh();
                  },
                ),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return _buildEmbeddedView(context);
    }

    return Scaffold(
      drawer: Drawer(
        child: SafeArea(
          child: _Folders(
            selected: path,
            onSelect: (value) {
              setState(() => path = value);
              Navigator.pop(context);
            },
          ),
        ),
      ),
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('资源管理器'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: '新建文件夹',
            onPressed: () => createFolder(context),
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
          IconButton(
            tooltip: '添加文件',
            onPressed: () => addFiles(context),
            icon: const Icon(Icons.upload_file_outlined),
          ),
        ],
      ),
      body: _buildContent(context, showDrawerButton: true),
    );
  }

  Widget _buildEmbeddedView(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          // 1. 顶部操作栏
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: '返回上级',
                  onPressed:
                      path == '/'
                          ? null
                          : () {
                            final parts = path.split('/')..removeLast();
                            setState(
                              () =>
                                  path =
                                      parts.join('/').isEmpty
                                          ? '/'
                                          : parts.join('/'),
                            );
                          },
                  icon: const Icon(Icons.arrow_upward_outlined, size: 20),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    path == '/' ? '全部共享文件' : path,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '添加文件到此目录',
                  onPressed: () => addFiles(context),
                  icon: const Icon(Icons.upload_file_outlined, size: 20),
                ),
                IconButton(
                  tooltip: '新建文件夹',
                  onPressed: () => createFolder(context),
                  icon: const Icon(Icons.create_new_folder_outlined, size: 20),
                ),
                IconButton(
                  tooltip: '在系统文件夹中打开',
                  onPressed: () => revealFolder(context),
                  icon: const Icon(Icons.folder_open_outlined, size: 20),
                ),
                IconButton(
                  tooltip: '刷新',
                  onPressed: refresh,
                  icon: const Icon(Icons.refresh, size: 20),
                ),
                IconButton(
                  tooltip: grid ? '切换为列表' : '切换为网格',
                  onPressed: () => setState(() => grid = !grid),
                  icon: Icon(
                    grid
                        ? Icons.view_list_outlined
                        : Icons.grid_view_rounded,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),

          // 2. 文件夹快速切换标签栏
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: folders.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final f = folders[i];
                final isSelected = path == f;
                return ChoiceChip(
                  label: Text(f == '/' ? '全部' : f.substring(1)),
                  selected: isSelected,
                  onSelected: (_) => setState(() => path = f),
                );
              },
            ),
          ),

          // 3. 文件列表区
          Expanded(child: _buildFileList(context)),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context, {
    required bool showDrawerButton,
  }) {
    return Row(
      children: [
        const SizedBox.shrink(),
        Expanded(
          child: ClipRRect(
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(24)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: .86),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 16, 6),
                      child: Row(
                        children: [
                          if (showDrawerButton)
                            Builder(
                              builder:
                                  (drawerContext) => IconButton(
                                    onPressed:
                                        () =>
                                            Scaffold.of(
                                              drawerContext,
                                            ).openDrawer(),
                                    icon: const Icon(Icons.menu),
                                    tooltip: '打开目录树',
                                  ),
                            ),
                          IconButton(
                            tooltip: '返回上级',
                            onPressed:
                                path == '/'
                                    ? null
                                    : () {
                                      final parts = path.split('/')
                                        ..removeLast();
                                      setState(
                                        () =>
                                            path =
                                                parts.join('/').isEmpty
                                                    ? '/'
                                                    : parts.join('/'),
                                      );
                                    },
                            icon: const Icon(Icons.arrow_upward_outlined),
                          ),
                          Expanded(
                            child: Text(
                              path,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          IconButton(
                            tooltip: '添加文件',
                            onPressed: () => addFiles(context),
                            icon: const Icon(Icons.upload_file_outlined),
                          ),
                          IconButton(
                            tooltip: grid ? '切换为列表' : '切换为网格',
                            onPressed: () => setState(() => grid = !grid),
                            icon: Icon(
                              grid
                                  ? Icons.view_list_outlined
                                  : Icons.grid_view_rounded,
                            ),
                          ),
                          if (!grid)
                            IconButton(
                              onPressed:
                                  () => setState(() => compact = !compact),
                              icon: Icon(
                                compact
                                    ? Icons.view_headline
                                    : Icons.view_agenda,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(child: _buildFileList(context)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFileList(BuildContext context) {
    return FutureBuilder<List<SharedFile>>(
      future: service.listSharedFiles(path),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final files = snap.data!;
        if (files.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.folder_open_outlined,
                  size: 48,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 10),
                Text(
                  '此文件夹暂无共享文件',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => addFiles(context),
                  icon: const Icon(Icons.upload_file_outlined, size: 16),
                  label: const Text('添加文件'),
                ),
              ],
            ),
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth - 24;
            final crossAxisCount = (availableWidth / 150).floor().clamp(1, 8);
            return grid
                ? GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisExtent: 160,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: files.length,
                  itemBuilder:
                      (_, i) => _Grid(
                        file: files[i],
                        onOpen: open,
                        onMenu: menu,
                      ),
                )
                : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: files.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder:
                      (_, i) => _Row(
                        file: files[i],
                        compact: compact,
                        onOpen: open,
                        onMenu: menu,
                      ),
                );
          },
        );
      },
    );
  }
}

class _Folders extends StatelessWidget {
  const _Folders({required this.selected, required this.onSelect});
  final String selected;
  final ValueChanged<String> onSelect;
  @override
  Widget build(BuildContext c) => Container(
    width: 166,
    color: Theme.of(c).colorScheme.surfaceContainerLow,
    child: ListView(
      padding: const EdgeInsets.all(10),
      children:
          _SharedFileManagerViewState.folders
              .map(
                (p) => ListTile(
                  dense: true,
                  selected: p == selected,
                  selectedTileColor: Theme.of(c).colorScheme.primaryContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  leading: Icon(
                    p == '/' ? Icons.home_outlined : Icons.folder_outlined,
                  ),
                  title: Text(p == '/' ? '全部文件' : p.substring(1)),
                  onTap: () => onSelect(p),
                ),
              )
              .toList(),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.file,
    required this.compact,
    required this.onOpen,
    required this.onMenu,
  });
  final SharedFile file;
  final bool compact;
  final ValueChanged<SharedFile> onOpen, onMenu;
  @override
  Widget build(BuildContext c) => Card(
    elevation: 0,
    child: ListTile(
      leading: _Icon(file),
      title: Text(file.name, overflow: TextOverflow.ellipsis),
      subtitle: compact ? null : Text(info(file)),
      trailing: IconButton(
        onPressed: () => onMenu(file),
        icon: const Icon(Icons.more_vert),
      ),
      onTap: () => onOpen(file),
    ),
  );
}

class _Grid extends StatelessWidget {
  const _Grid({required this.file, required this.onOpen, required this.onMenu});
  final SharedFile file;
  final ValueChanged<SharedFile> onOpen, onMenu;
  @override
  Widget build(BuildContext c) => Card(
    elevation: 0,
    child: InkWell(
      onTap: () => onOpen(file),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: _Icon(file, large: true),
                ),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    splashRadius: 16,
                    constraints: const BoxConstraints(),
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => onMenu(file),
                    icon: const Icon(Icons.more_vert, size: 18),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              file.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              info(file),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(c).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}

class _Icon extends StatelessWidget {
  const _Icon(this.file, {this.large = false});
  final SharedFile file;
  final bool large;
  @override
  Widget build(BuildContext c) {
    final color =
        file.isDirectory
            ? Colors.amber.shade700
            : Theme.of(c).colorScheme.primary;
    return Container(
      width: large ? 45 : 40,
      height: large ? 45 : 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(
        file.isDirectory ? Icons.folder_rounded : Icons.description_rounded,
        color: color,
        size: large ? 28 : 24,
      ),
    );
  }
}

String info(SharedFile f) =>
    '${f.isDirectory ? '文件夹' : size(f.size)} · ${f.modifiedAt.year}-${f.modifiedAt.month.toString().padLeft(2, '0')}-${f.modifiedAt.day.toString().padLeft(2, '0')}';

String size(int v) =>
    v < 1024
        ? '$v B'
        : v < 1048576
        ? '${(v / 1024).toStringAsFixed(1)} KB'
        : '${(v / 1048576).toStringAsFixed(1)} MB';
