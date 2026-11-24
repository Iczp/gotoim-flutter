import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/media/media_preview.dart';
import '../../../core/services/window_service.dart';
import '../data/attachment_browser_api.dart';
import '../domain/attachment_browser_models.dart';

abstract final class AttachmentBrowser {
  static Future<AttachmentBrowserResult?> open(
    BuildContext context, {
    AttachmentBrowserOptions options = const AttachmentBrowserOptions(),
  }) {
    final isDesktop =
        !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    if (isDesktop) {
      return showDialog<AttachmentBrowserResult>(
        context: context,
        barrierDismissible: options.mode == AttachmentBrowserMode.viewer,
        builder: (_) => Dialog(
          clipBehavior: Clip.antiAlias,
          insetPadding: const EdgeInsets.all(24),
          child: SizedBox(
            width: 980,
            height: 680,
            child: AttachmentBrowserPage(options: options),
          ),
        ),
      );
    }
    return Navigator.of(context).push<AttachmentBrowserResult>(
      MaterialPageRoute<AttachmentBrowserResult>(
        builder: (_) => AttachmentBrowserPage(options: options),
      ),
    );
  }
}

class AttachmentBrowserPage extends ConsumerStatefulWidget {
  const AttachmentBrowserPage({
    required this.options,
    super.key,
  });

  final AttachmentBrowserOptions options;

  @override
  ConsumerState<AttachmentBrowserPage> createState() =>
      _AttachmentBrowserPageState();
}

class _AttachmentBrowserPageState extends ConsumerState<AttachmentBrowserPage> {
  late AttachmentSource _activeSource;
  late Set<AttachmentMediaType> _selectedTypes;
  late AttachmentDatePreset _datePreset;
  DateTime? _customStart;
  DateTime? _customEnd;
  late AttachmentSortBy _sortBy;
  late AttachmentLayout _layout;
  late final TextEditingController _keywordController;
  late final TextEditingController _extensionsController;
  late final TextEditingController _senderIdController;
  late final TextEditingController _tagsController;
  String _sizePreset = 'all';
  bool _showAdvanced = false;

  final List<AttachmentAsset> _items = <AttachmentAsset>[];
  final Map<String, AttachmentAsset> _selectedMap = <String, AttachmentAsset>{};
  int _totalCount = 0;
  bool _loading = false;
  bool _loadingMore = false;
  bool _uploading = false;

  bool get _isSelectMode =>
      widget.options.mode != AttachmentBrowserMode.viewer;

  List<AttachmentSource> get _availableSources {
    final list = List<AttachmentSource>.from(widget.options.sources);
    if (widget.options.customItems.isNotEmpty &&
        !list.contains(AttachmentSource.custom)) {
      list.insert(0, AttachmentSource.custom);
    }
    return list;
  }

  List<AttachmentMediaType> get _visibleTypes =>
      widget.options.allowedTypes != null &&
              widget.options.allowedTypes!.isNotEmpty
          ? widget.options.allowedTypes!
          : AttachmentMediaType.values;

  @override
  void initState() {
    super.initState();
    _activeSource = widget.options.defaultSource;
    _selectedTypes = Set<AttachmentMediaType>.from(widget.options.defaultTypes);
    _datePreset = widget.options.datePreset;
    _customStart = widget.options.startTime;
    _customEnd = widget.options.endTime;
    _sortBy = widget.options.sortBy;
    _layout = widget.options.defaultLayout;
    _keywordController = TextEditingController(text: widget.options.keyword ?? '');
    _extensionsController = TextEditingController(
      text: widget.options.extensions.join(','),
    );
    _senderIdController = TextEditingController(
      text: widget.options.senderId ?? '',
    );
    _tagsController = TextEditingController(text: widget.options.tags.join(','));
    _reload();
  }

  @override
  void dispose() {
    _keywordController.dispose();
    _extensionsController.dispose();
    _senderIdController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  (DateTime?, DateTime?) _resolveDateRange() {
    final now = DateTime.now();
    switch (_datePreset) {
      case AttachmentDatePreset.all:
        return (null, null);
      case AttachmentDatePreset.custom:
        return (_customStart, _customEnd);
      case AttachmentDatePreset.today:
        return (DateTime(now.year, now.month, now.day), now);
      case AttachmentDatePreset.days7:
        return (now.subtract(const Duration(days: 7)), now);
      case AttachmentDatePreset.days30:
        return (now.subtract(const Duration(days: 30)), now);
      case AttachmentDatePreset.days90:
        return (now.subtract(const Duration(days: 90)), now);
      case AttachmentDatePreset.year:
        return (DateTime(now.year, 1, 1), now);
    }
  }

  (int?, int?) _resolveSizeRange() {
    const mb = 1024 * 1024;
    return switch (_sizePreset) {
      'lt1m' => (null, mb),
      '1to10m' => (mb, 10 * mb),
      '10to100m' => (10 * mb, 100 * mb),
      'gt100m' => (100 * mb, null),
      _ => (widget.options.minSizeBytes, widget.options.maxSizeBytes),
    };
  }

  List<String>? _parseExtensions() {
    final list = _extensionsController.text
        .split(RegExp(r'[,，\s]+'))
        .map((e) => e.trim().replaceFirst(RegExp(r'^\.'), '').toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList();
    if (list.isNotEmpty) return list;
    return widget.options.extensions.isNotEmpty
        ? widget.options.extensions
        : null;
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      await _fetchPage(skipCount: 0, append: false);
      if (widget.options.initialSelectedIds.isNotEmpty && _selectedMap.isEmpty) {
        for (final item in _items) {
          if (widget.options.initialSelectedIds.contains(item.id)) {
            _selectedMap[item.id] = item;
          }
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _items.length >= _totalCount) return;
    if (_activeSource == AttachmentSource.custom ||
        _activeSource == AttachmentSource.local) {
      return;
    }
    setState(() => _loadingMore = true);
    try {
      await _fetchPage(skipCount: _items.length, append: true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _fetchPage({
    required int skipCount,
    required bool append,
  }) async {
    if (_activeSource == AttachmentSource.custom) {
      setState(() {
        _items
          ..clear()
          ..addAll(widget.options.customItems);
        _totalCount = _items.length;
      });
      return;
    }
    if (_activeSource == AttachmentSource.local) {
      return;
    }

    final api = ref.read(attachmentBrowserApiProvider);
    final (startTime, endTime) = _resolveDateRange();
    final (minSize, maxSize) = _resolveSizeRange();
    final types = _selectedTypes.isNotEmpty
        ? _selectedTypes.toList(growable: false)
        : (widget.options.allowedTypes?.isNotEmpty == true
            ? widget.options.allowedTypes
            : null);

    final res = await api.queryLibrary(
      source: _activeSource,
      ownerId: widget.options.ownerId,
      sessionUnitId: widget.options.sessionUnitId,
      sessionId: widget.options.sessionId,
      senderId: _senderIdController.text.trim(),
      mediaTypes: types,
      startTime: startTime,
      endTime: endTime,
      minSizeBytes: minSize,
      maxSizeBytes: maxSize,
      extensions: _parseExtensions(),
      keyword: _keywordController.text,
      sortBy: _sortBy,
      skipCount: skipCount,
      maxResultCount: 40,
    );
    if (!mounted) return;
    setState(() {
      if (!append) {
        _items
          ..clear()
          ..addAll(res.items);
      } else {
        final existing = _items.map((e) => e.id).toSet();
        _items.addAll(res.items.where((e) => !existing.contains(e.id)));
      }
      _totalCount = res.totalCount;
    });
  }

  String? _disabledReason(AttachmentAsset asset) {
    if (widget.options.disabledIds.contains(asset.id)) return '当前不可选';
    if (widget.options.maxFileSize != null &&
        (asset.sizeBytes ?? 0) > widget.options.maxFileSize!) {
      return '超过大小限制 (${_formatBytes(widget.options.maxFileSize)})';
    }
    if (widget.options.allowedExtensions != null &&
        widget.options.allowedExtensions!.isNotEmpty) {
      final ext = (asset.extension ?? '')
          .replaceFirst(RegExp(r'^\.'), '')
          .toLowerCase();
      final allowed = widget.options.allowedExtensions!
          .map((e) => e.replaceFirst(RegExp(r'^\.'), '').toLowerCase())
          .toSet();
      if (!allowed.contains(ext)) {
        return '不支持扩展名 .$ext';
      }
    }
    return null;
  }

  void _toggleSelect(AttachmentAsset asset) {
    if (!_isSelectMode) return;
    if (widget.options.lockedIds.contains(asset.id)) return;
    final reason = _disabledReason(asset);
    if (reason != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(reason)));
      return;
    }
    setState(() {
      if (_selectedMap.containsKey(asset.id)) {
        _selectedMap.remove(asset.id);
      } else {
        if (widget.options.mode == AttachmentBrowserMode.singleSelect) {
          _selectedMap.clear();
        } else if (widget.options.maxCount != null &&
            _selectedMap.length >= widget.options.maxCount!) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('最多只能选择 ${widget.options.maxCount} 项')),
          );
          return;
        }
        _selectedMap[asset.id] = asset;
      }
    });
  }

  Future<void> _previewAsset(AttachmentAsset asset) async {
    if (asset.url.isEmpty) return;
    if (asset.mediaType == AttachmentMediaType.image ||
        asset.mediaType == AttachmentMediaType.video) {
      final mediaItems = _items
          .where((e) =>
              (e.mediaType == AttachmentMediaType.image ||
                  e.mediaType == AttachmentMediaType.video) &&
              e.url.isNotEmpty)
          .map(
            (e) => MediaPreviewItem(
              id: e.id,
              messageId: e.messageId ?? e.id,
              type: e.mediaType == AttachmentMediaType.video
                  ? MediaPreviewType.video
                  : MediaPreviewType.image,
              source: e.url,
              heroTag: 'ab-${e.id}',
              fileName: e.fileName,
              thumbnail: e.thumbnailUrl,
            ),
          )
          .toList(growable: false);
      final idx = mediaItems.indexWhere((m) => m.source == asset.url);
      await ref.read(windowServiceProvider).openMediaViewer(
            mediaUrl: asset.url,
            title: asset.fileName,
            items: mediaItems,
            initialIndex: idx >= 0 ? idx : 0,
          );
      return;
    }
    await Clipboard.setData(ClipboardData(text: asset.url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已复制附件链接: ${asset.fileName}')),
      );
    }
  }

  Future<void> _pickAndUploadLocalFiles() async {
    final unitId = widget.options.sessionUnitId;
    if (unitId == null || unitId.isEmpty) return;
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty) return;

    setState(() => _uploading = true);
    try {
      final api = ref.read(attachmentBrowserApiProvider);
      for (final f in picked) {
        if (f.path == null) continue;
        final uploaded =
            await api.uploadLocalFile(sessionUnitId: unitId, file: File(f.path!));
        if (uploaded != null && mounted) {
          setState(() {
            _items.insert(0, uploaded);
            _totalCount++;
          });
          if (_isSelectMode) _toggleSelect(uploaded);
        }
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  bool get _canConfirm {
    final count = _selectedMap.length;
    if (count < widget.options.minCount) return false;
    if (widget.options.mode == AttachmentBrowserMode.singleSelect &&
        count != 1) {
      return false;
    }
    if (widget.options.maxCount != null && count > widget.options.maxCount!) {
      return false;
    }
    return count > 0 || widget.options.minCount == 0;
  }

  String _formatBytes(int? bytes) {
    if (bytes == null || bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var val = bytes.toDouble();
    var idx = 0;
    while (val >= 1024 && idx < units.length - 1) {
      val /= 1024;
      idx++;
    }
    return '${val.toStringAsFixed(idx == 0 ? 0 : 1)} ${units[idx]}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final totalSelectedBytes = _selectedMap.values.fold<int>(
      0,
      (sum, e) => sum + (e.sizeBytes ?? 0),
    );

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.options.title ?? '附件查看器与选择器'),
            if (widget.options.subtitle != null)
              Text(
                widget.options.subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
              ),
          ],
        ),
        actions: [
          if (widget.options.allowLocalUpload &&
              widget.options.sessionUnitId != null)
            TextButton.icon(
              onPressed: _uploading ? null : _pickAndUploadLocalFiles,
              icon: const Icon(Icons.upload_file_rounded, size: 18),
              label: Text(_uploading ? '上传中...' : '本地上传'),
            ),
          IconButton(
            tooltip: _layout == AttachmentLayout.grid ? '切换列表视图' : '切换网格视图',
            icon: Icon(
              _layout == AttachmentLayout.grid
                  ? Icons.view_list_rounded
                  : Icons.grid_view_rounded,
            ),
            onPressed: () {
              setState(() {
                _layout = _layout == AttachmentLayout.grid
                    ? AttachmentLayout.list
                    : AttachmentLayout.grid;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 数据源与主筛选栏
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final src in _availableSources)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(src.label),
                            selected: _activeSource == src,
                            onSelected: (_) {
                              setState(() => _activeSource = src);
                              _reload();
                            },
                          ),
                        ),
                      const SizedBox(width: 8),
                      DropdownButton<AttachmentDatePreset>(
                        value: _datePreset,
                        underline: const SizedBox.shrink(),
                        items: AttachmentDatePreset.values
                            .map((p) => DropdownMenuItem(
                                  value: p,
                                  child: Text(p.label),
                                ))
                            .toList(),
                        onChanged: (val) async {
                          if (val == null) return;
                          if (val == AttachmentDatePreset.custom) {
                            final range = await showDateRangePicker(
                              context: context,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now().add(const Duration(days: 1)),
                            );
                            if (range != null) {
                              setState(() {
                                _datePreset = val;
                                _customStart = range.start;
                                _customEnd = range.end.add(const Duration(days: 1));
                              });
                              _reload();
                            }
                          } else {
                            setState(() => _datePreset = val);
                            _reload();
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<AttachmentSortBy>(
                        value: _sortBy,
                        underline: const SizedBox.shrink(),
                        items: AttachmentSortBy.values
                            .map((s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(s.label),
                                ))
                            .toList(),
                        onChanged: (val) {
                          if (val == null) return;
                          setState(() => _sortBy = val);
                          _reload();
                        },
                      ),
                      TextButton.icon(
                        onPressed: () =>
                            setState(() => _showAdvanced = !_showAdvanced),
                        icon: const Icon(Icons.tune_rounded, size: 16),
                        label: Text(_showAdvanced ? '收起' : '高级筛选'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _keywordController,
                        decoration: const InputDecoration(
                          hintText: '搜索文件名或关键词...',
                          prefixIcon: Icon(Icons.search_rounded, size: 18),
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _reload(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: _reload,
                      child: const Text('搜索'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: _visibleTypes.map((t) {
                    final selected = _selectedTypes.contains(t);
                    return FilterChip(
                      label: Text(t.label),
                      selected: selected,
                      onSelected: (v) {
                        setState(() {
                          if (v) {
                            _selectedTypes.add(t);
                          } else {
                            _selectedTypes.remove(t);
                          }
                        });
                        _reload();
                      },
                    );
                  }).toList(),
                ),
                if (_showAdvanced)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        DropdownButton<String>(
                          value: _sizePreset,
                          items: const [
                            DropdownMenuItem(value: 'all', child: Text('不限大小')),
                            DropdownMenuItem(value: 'lt1m', child: Text('< 1MB')),
                            DropdownMenuItem(
                                value: '1to10m', child: Text('1MB - 10MB')),
                            DropdownMenuItem(
                                value: '10to100m', child: Text('10MB - 100MB')),
                            DropdownMenuItem(
                                value: 'gt100m', child: Text('> 100MB')),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _sizePreset = v);
                            _reload();
                          },
                        ),
                        SizedBox(
                          width: 150,
                          child: TextField(
                            controller: _extensionsController,
                            decoration: const InputDecoration(
                              hintText: '扩展名如 jpg,pdf',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (_) => _reload(),
                          ),
                        ),
                        SizedBox(
                          width: 130,
                          child: TextField(
                            controller: _senderIdController,
                            decoration: const InputDecoration(
                              hintText: '发送人 ID',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (_) => _reload(),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 内容列表/网格
          Expanded(
            child: _loading && _items.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? Center(
                        child: Text(
                          widget.options.emptyText ?? '暂无匹配的附件或媒体',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: cs.outline),
                        ),
                      )
                    : NotificationListener<ScrollNotification>(
                        onNotification: (n) {
                          if (n.metrics.pixels >=
                              n.metrics.maxScrollExtent - 120) {
                            _loadMore();
                          }
                          return false;
                        },
                        child: _layout == AttachmentLayout.grid
                            ? GridView.builder(
                                padding: const EdgeInsets.all(12),
                                gridDelegate:
                                    const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 200,
                                  mainAxisSpacing: 10,
                                  crossAxisSpacing: 10,
                                  childAspectRatio: 0.92,
                                ),
                                itemCount: _items.length,
                                itemBuilder: (_, i) => _buildGridCard(_items[i]),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.all(12),
                                itemCount: _items.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 6),
                                itemBuilder: (_, i) => _buildListTile(_items[i]),
                              ),
                      ),
          ),
          const Divider(height: 1),
          // 底部确认栏
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                if (_isSelectMode)
                  Text(
                    '已选 ${_selectedMap.length}'
                    '${widget.options.maxCount != null ? ' / ${widget.options.maxCount}' : ''}'
                    ' 项（${_formatBytes(totalSelectedBytes)}）',
                  )
                else
                  Text('共 $_totalCount 项'),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: Text(_isSelectMode ? '取消' : '关闭'),
                ),
                if (_isSelectMode) ...[
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _canConfirm
                        ? () => Navigator.of(context).pop(
                              AttachmentBrowserResult(
                                confirmed: true,
                                selectedItems: _selectedMap.values.toList(),
                              ),
                            )
                        : null,
                    child: Text(
                      widget.options.confirmButtonText ??
                          '确认选择 (${_selectedMap.length})',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridCard(AttachmentAsset asset) {
    final cs = Theme.of(context).colorScheme;
    final selected = _selectedMap.containsKey(asset.id);
    final disabledReason = _disabledReason(asset);
    return InkWell(
      onTap: () => _isSelectMode
          ? _toggleSelect(asset)
          : (widget.options.enablePreview ? _previewAsset(asset) : null),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(7)),
                    child: (asset.mediaType == AttachmentMediaType.image ||
                                asset.thumbnailUrl != null) &&
                            (asset.thumbnailUrl ?? asset.url).isNotEmpty
                        ? Image.network(
                            asset.thumbnailUrl ?? asset.url,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Center(
                              child: Icon(Icons.broken_image_outlined),
                            ),
                          )
                        : Container(
                            color: cs.surfaceContainerHighest,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    asset.mediaType == AttachmentMediaType.video
                                        ? Icons.videocam_outlined
                                        : Icons.insert_drive_file_outlined,
                                    size: 32,
                                  ),
                                  if (asset.extension != null)
                                    Text(
                                      asset.extension!.toUpperCase(),
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                ],
                              ),
                            ),
                          ),
                  ),
                  if (_isSelectMode)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Checkbox(
                        value: selected,
                        onChanged: disabledReason != null
                            ? null
                            : (_) => _toggleSelect(asset),
                      ),
                    ),
                  if (widget.options.enablePreview)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: IconButton.filledTonal(
                        iconSize: 16,
                        constraints:
                            const BoxConstraints(minWidth: 28, minHeight: 28),
                        padding: EdgeInsets.zero,
                        onPressed: () => _previewAsset(asset),
                        icon: const Icon(Icons.visibility_outlined),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    asset.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    disabledReason ??
                        '${_formatBytes(asset.sizeBytes)} · ${asset.creationTime.length >= 10 ? asset.creationTime.substring(0, 10) : asset.creationTime}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: disabledReason != null ? cs.error : cs.outline,
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

  Widget _buildListTile(AttachmentAsset asset) {
    final cs = Theme.of(context).colorScheme;
    final selected = _selectedMap.containsKey(asset.id);
    return ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected ? cs.primary : cs.outlineVariant,
        ),
      ),
      leading: _isSelectMode
          ? Checkbox(value: selected, onChanged: (_) => _toggleSelect(asset))
          : Icon(
              asset.mediaType == AttachmentMediaType.image
                  ? Icons.image_outlined
                  : asset.mediaType == AttachmentMediaType.video
                      ? Icons.videocam_outlined
                      : Icons.insert_drive_file_outlined,
            ),
      title: Text(asset.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${asset.mediaType.label} · ${_formatBytes(asset.sizeBytes)} · ${asset.creationTime.length >= 10 ? asset.creationTime.substring(0, 10) : asset.creationTime}',
      ),
      trailing: widget.options.enablePreview
          ? IconButton(
              icon: const Icon(Icons.visibility_outlined),
              onPressed: () => _previewAsset(asset),
            )
          : null,
      onTap: () => _isSelectMode
          ? _toggleSelect(asset)
          : (widget.options.enablePreview ? _previewAsset(asset) : null),
    );
  }
}
