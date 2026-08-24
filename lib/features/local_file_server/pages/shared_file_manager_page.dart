import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../local_file_server.dart';
import '../local_file_server_controller.dart';

class SharedFileManagerPage extends ConsumerStatefulWidget {
  const SharedFileManagerPage({super.key});
  @override
  ConsumerState<SharedFileManagerPage> createState() => _State();
}

class _State extends ConsumerState<SharedFileManagerPage> {
  static const folders = ['/', '/图片', '/视频', '/文档', '/下载', '/聊天文件'];
  late final LocalFileServerService service;
  String path = '/';
  bool grid = false, compact = false;
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

  @override
  Widget build(BuildContext context) => Scaffold(
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
      title: const Text('资源管理器'),
      actions: [
        IconButton(
          onPressed: () => setState(() => grid = !grid),
          icon: Icon(grid ? Icons.view_list_outlined : Icons.grid_view_rounded),
        ),
        IconButton(
          onPressed: () => createFolder(context),
          icon: const Icon(Icons.create_new_folder_outlined),
        ),
      ],
    ),
    body: Row(
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
                          Expanded(
                            child: Text(
                              path,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
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
                    Expanded(
                      child: FutureBuilder<List<SharedFile>>(
                        future: service.listSharedFiles(path),
                        builder: (context, snap) {
                          if (!snap.hasData)
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          final files = snap.data!;
                          if (files.isEmpty)
                            return const Center(child: Text('此文件夹为空'));
                          return grid
                              ? GridView.builder(
                                padding: const EdgeInsets.all(12),
                                gridDelegate:
                                    const SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 180,
                                      mainAxisExtent: 168,
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
                                separatorBuilder:
                                    (_, __) => const SizedBox(height: 6),
                                itemBuilder:
                                    (_, i) => _Row(
                                      file: files[i],
                                      compact: compact,
                                      onOpen: open,
                                      onMenu: menu,
                                    ),
                              );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
  void open(SharedFile file) {
    if (file.isDirectory)
      setState(() => path = file.path);
    else
      service.openSharedFile(file.path);
  }

  Future<void> createFolder(BuildContext c) async {
    final ctl = TextEditingController();
    await showDialog<void>(
      context: c,
      builder:
          (d) => AlertDialog(
            title: const Text('新建文件夹'),
            content: TextField(controller: ctl, autofocus: true),
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
                },
                child: const Text('创建'),
              ),
            ],
          ),
    );
    ctl.dispose();
  }

  Future<void> menu(SharedFile f) async {
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
                  onTap: () {
                    Navigator.pop(s);
                    service.deleteSharedEntry(f.path);
                  },
                ),
              ],
            ),
          ),
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
          _State.folders
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
        icon: const Icon(Icons.more_horiz),
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
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Icon(file, large: true),
                const Spacer(),
                IconButton(
                  onPressed: () => onMenu(file),
                  icon: const Icon(Icons.more_horiz),
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
