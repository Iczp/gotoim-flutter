import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../local_file_server.dart';
import '../local_file_server_controller.dart';

class SharedFileManagerPage extends ConsumerStatefulWidget {
  const SharedFileManagerPage({super.key});

  @override
  ConsumerState<SharedFileManagerPage> createState() =>
      _SharedFileManagerPageState();
}

class _SharedFileManagerPageState extends ConsumerState<SharedFileManagerPage> {
  late final LocalFileServerService _service;
  String _path = '/';

  @override
  void initState() {
    super.initState();
    _service = ref.read(localFileServerProvider)..addListener(_refresh);
  }

  @override
  void dispose() {
    _service.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _nameDialog(
    String title,
    Future<void> Function(String) action, {
    String value = '',
  }) async {
    final controller = TextEditingController(text: value);
    await showCupertinoDialog<void>(
      context: context,
      builder:
          (dialogContext) => CupertinoAlertDialog(
            title: Text(title),
            content: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: CupertinoTextField(
                controller: controller,
                placeholder: '名称',
                autofocus: true,
              ),
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () async {
                  final name = controller.text.trim();
                  if (name.isEmpty) return;
                  Navigator.pop(dialogContext);
                  await action(name);
                },
                child: const Text('确定'),
              ),
            ],
          ),
    );
    controller.dispose();
  }

  Future<void> _entryMenu(SharedFile file) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder:
          (context) => CupertinoActionSheet(
            title: Text(file.name),
            actions: [
              if (!file.isDirectory)
                CupertinoActionSheetAction(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _service.openSharedFile(file.path);
                  },
                  child: const Text('使用系统应用打开'),
                ),
              CupertinoActionSheetAction(
                onPressed: () async {
                  Navigator.pop(context);
                  await _nameDialog(
                    '重命名',
                    (name) => _service.renameSharedEntry(file.path, name),
                    value: file.name,
                  );
                },
                child: const Text('重命名'),
              ),
              CupertinoActionSheetAction(
                isDestructiveAction: true,
                onPressed: () async {
                  Navigator.pop(context);
                  await _service.deleteSharedEntry(file.path);
                },
                child: const Text('删除'),
              ),
            ],
            cancelButton: CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: CupertinoNavigationBar(
      middle: const Text('资源管理器'),
      leading:
          _path == '/'
              ? null
              : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () {
                  final pieces = _path.split('/')..removeLast();
                  setState(
                    () =>
                        _path =
                            pieces.join('/').isEmpty ? '/' : pieces.join('/'),
                  );
                },
                child: const Icon(CupertinoIcons.back),
              ),
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed:
            () => _nameDialog(
              '新建文件夹',
              (name) => _service.createSharedDirectory(_path, name),
            ),
        child: const Icon(CupertinoIcons.folder_badge_plus),
      ),
    ),
    child: SafeArea(
      child: Row(
        children: [
          SizedBox(
            width: 116,
            child: ListView(
              children:
                  ['/', '/图片', '/视频', '/文档', '/下载', '/聊天文件']
                      .map(
                        (folder) => CupertinoButton(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 12,
                          ),
                          alignment: Alignment.centerLeft,
                          onPressed: () => setState(() => _path = folder),
                          child: Text(
                            folder == '/' ? '全部文件' : folder.substring(1),
                          ),
                        ),
                      )
                      .toList(),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: FutureBuilder<List<SharedFile>>(
              future: _service.listSharedFiles(_path),
              builder: (context, snapshot) {
                if (!snapshot.hasData)
                  return const Center(child: CupertinoActivityIndicator());
                final files = snapshot.data!;
                return Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      color: CupertinoColors.systemGroupedBackground,
                      child: Text(
                        _path,
                        style: const TextStyle(
                          color: CupertinoColors.secondaryLabel,
                        ),
                      ),
                    ),
                    Expanded(
                      child:
                          files.isEmpty
                              ? const Center(child: Text('此文件夹为空'))
                              : ListView.separated(
                                itemCount: files.length,
                                separatorBuilder:
                                    (_, __) => const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final file = files[index];
                                  return CupertinoListTile(
                                    leading: Icon(
                                      file.isDirectory
                                          ? CupertinoIcons.folder_fill
                                          : CupertinoIcons.doc,
                                      color:
                                          file.isDirectory
                                              ? CupertinoColors.systemYellow
                                              : CupertinoColors.activeBlue,
                                    ),
                                    title: Text(file.name),
                                    subtitle: Text(
                                      file.isDirectory
                                          ? '文件夹'
                                          : _formatSize(file.size),
                                    ),
                                    trailing: CupertinoButton(
                                      padding: EdgeInsets.zero,
                                      onPressed: () => _entryMenu(file),
                                      child: const Icon(
                                        CupertinoIcons.ellipsis_circle,
                                      ),
                                    ),
                                    onTap: () {
                                      if (file.isDirectory)
                                        setState(() => _path = file.path);
                                      else
                                        _service.openSharedFile(file.path);
                                    },
                                  );
                                },
                              ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );

  String _formatSize(int value) =>
      value < 1024
          ? '$value B'
          : value < 1024 * 1024
          ? '${(value / 1024).toStringAsFixed(1)} KB'
          : '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
}
