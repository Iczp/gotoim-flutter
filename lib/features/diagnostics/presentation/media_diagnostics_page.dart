import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/application_providers.dart';
import '../../../core/services/file/file_picker_service.dart';
import '../../../core/services/media/media_service.dart';
import '../../../core/services/media/video_processing_models.dart';

class MediaDiagnosticsPage extends ConsumerStatefulWidget {
  const MediaDiagnosticsPage({super.key});

  @override
  ConsumerState<MediaDiagnosticsPage> createState() =>
      _MediaDiagnosticsPageState();
}

class _MediaDiagnosticsPageState extends ConsumerState<MediaDiagnosticsPage> {
  // Picker Configuration State
  bool _allowMultiple = true;
  int _maxCount = 9;
  String _selectedFileType = 'any';
  final TextEditingController _customExtController = TextEditingController(
    text: 'pdf,docx,xlsx,txt',
  );

  List<SelectedFile> _selectedFiles = [];
  SelectedFile? _selected;
  String _result = '尚未调用。';
  bool _working = false;
  bool _recording = false;
  bool _paused = false;

  @override
  void dispose() {
    _customExtController.dispose();
    super.dispose();
  }

  List<String> _parseExtensions() {
    if (_selectedFileType == 'any') return const [];
    if (_selectedFileType == 'images')
      return const ['jpg', 'jpeg', 'png', 'webp', 'gif', 'heic'];
    if (_selectedFileType == 'videos')
      return const ['mp4', 'mov', 'avi', 'mkv'];
    if (_selectedFileType == 'docs')
      return const ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt'];
    return _customExtController.text
        .split(',')
        .map((e) => e.trim().replaceAll('.', ''))
        .where((e) => e.isNotEmpty)
        .toList();
  }

  FileTypeCategory _resolveCategory() {
    return switch (_selectedFileType) {
      'images' => FileTypeCategory.image,
      'videos' => FileTypeCategory.video,
      'docs' || 'custom' => FileTypeCategory.custom,
      _ => FileTypeCategory.any,
    };
  }

  Future<void> _run(Future<Object?> Function() action) async {
    setState(() => _working = true);
    try {
      final result = await action();
      if (mounted) setState(() => _result = _pretty(result));
    } catch (error) {
      if (mounted) setState(() => _result = '调用失败：$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _pickFiles() async {
    await _run(() async {
      final extensions = _parseExtensions();
      final files = await ref
          .read(clientCapabilityServiceProvider)
          .chooseFile(
            FilePickerRequest(
              allowMultiple: _allowMultiple,
              maxCount: _allowMultiple ? _maxCount : 1,
              allowedExtensions: extensions,
              fileType: _resolveCategory(),
              dialogTitle: _allowMultiple ? '选择文件（最多 $_maxCount 个）' : '选择单个文件',
            ),
          );
      if (mounted) {
        setState(() {
          _selectedFiles = files;
          if (files.isNotEmpty) _selected = files.first;
        });
      }
      return <String, Object>{
        'count': files.length,
        'maxCount': _allowMultiple ? _maxCount : 1,
        'allowMultiple': _allowMultiple,
        'files': files.map((f) => f.toJson()).toList(),
      };
    });
  }

  Future<void> _pickImages({required bool preserveOriginal}) async {
    await _run(() async {
      final files = await ref
          .read(clientCapabilityServiceProvider)
          .chooseImage(
            MediaPickRequest(
              allowMultiple: _allowMultiple,
              maxCount: _allowMultiple ? _maxCount : 1,
              preserveOriginal: preserveOriginal,
              imageQuality: 85,
              maxWidth: 1920,
              maxHeight: 1920,
            ),
          );
      if (mounted) {
        setState(() {
          _selectedFiles = files;
          if (files.isNotEmpty) _selected = files.first;
        });
      }
      return <String, Object>{
        'count': files.length,
        'maxCount': _allowMultiple ? _maxCount : 1,
        'allowMultiple': _allowMultiple,
        'preserveOriginal': preserveOriginal,
        'files': files.map((f) => f.toJson()).toList(),
      };
    });
  }

  Future<void> _selectSingle(Future<SelectedFile?> Function() action) =>
      _run(() async {
        final file = await action();
        if (mounted && file != null) {
          setState(() {
            _selected = file;
            _selectedFiles = [file];
          });
        }
        return <String, Object?>{'file': file?.toJson()};
      });

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(body: Center(child: Text('开发诊断仅在 Debug 模式可用。')));
    }
    final capabilities = ref.read(clientCapabilityServiceProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('媒体与文件选择器测试')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Selector Config Card
          _buildPickerConfigCard(),
          const SizedBox(height: 16),

          // 2. Selected Files Preview Card
          _buildSelectedFilesCard(),
          const SizedBox(height: 16),

          // 3. Media & File Actions Section
          _Section(
            title: '媒体与拍照功能',
            children: [
              _button(
                '拍照 (takePhoto)',
                () => _selectSingle(
                  () => capabilities.takePhoto(const MediaPickRequest()),
                ),
              ),
              _button(
                '相册视频 (chooseVideo)',
                () => _selectSingle(
                  () => capabilities.chooseVideo(const MediaPickRequest()),
                ),
              ),
              _button(
                '相机录像 (recordVideo)',
                () => _selectSingle(
                  () => capabilities.recordVideo(
                    const MediaPickRequest(maxDuration: Duration(seconds: 60)),
                  ),
                ),
              ),
              _button(
                '图片压缩（当前文件）',
                _selected == null
                    ? null
                    : () => _run(() async {
                      final image = await capabilities.compressImage(
                        _selected!,
                        const ImageCompressionRequest(
                          quality: 80,
                          maxWidth: 1920,
                          maxHeight: 1920,
                        ),
                      );
                      return image.toJson();
                    }),
              ),
              _button(
                '图片识码（当前文件）',
                _selected == null
                    ? null
                    : () => _run(() async {
                      final result = await capabilities.decodeImageFile(
                        _selected!,
                      );
                      return <String, Object?>{
                        'result':
                            result == null
                                ? null
                                : <String, Object?>{
                                  'content': result.content,
                                  'format': result.format?.name,
                                  'source': result.source.name,
                                },
                      };
                    }),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 4. Audio Section
          _Section(
            title: '音频录制功能',
            children: [
              _button(
                '开始录音',
                _recording
                    ? null
                    : () => _run(() async {
                      await capabilities.startAudioRecording(
                        const AudioRecordingRequest(),
                      );
                      _recording = true;
                      _paused = false;
                      return const <String, bool>{'started': true};
                    }),
              ),
              _button(
                '暂停录音',
                !_recording || _paused
                    ? null
                    : () => _run(() async {
                      await capabilities.pauseAudioRecording();
                      _paused = true;
                      return const <String, bool>{'paused': true};
                    }),
              ),
              _button(
                '继续录音',
                !_recording || !_paused
                    ? null
                    : () => _run(() async {
                      await capabilities.resumeAudioRecording();
                      _paused = false;
                      return const <String, bool>{'resumed': true};
                    }),
              ),
              _button(
                '停止录音',
                !_recording
                    ? null
                    : () => _run(() async {
                      final file = await capabilities.stopAudioRecording();
                      _recording = false;
                      _paused = false;
                      if (file != null) {
                        _selected = file;
                        _selectedFiles = [file];
                      }
                      return <String, Object?>{'file': file?.toJson()};
                    }),
              ),
              _button(
                '取消录音',
                !_recording
                    ? null
                    : () => _run(() async {
                      await capabilities.cancelAudioRecording();
                      _recording = false;
                      _paused = false;
                      return const <String, bool>{'cancelled': true};
                    }),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 5. Result Output Panel
          Text('调用结果 (JSON)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _Panel(value: _result),
        ],
      ),
    );
  }

  Widget _buildPickerConfigCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '选择器配置 (单选/多选/文件类型/数量限制)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const Divider(height: 20),

            // 1. Single vs Multi-select Switch
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '多选模式 (allowMultiple)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      _allowMultiple ? '已开启多选（带复选框/限额）' : '单选模式（仅选择 1 个）',
                      style: TextStyle(
                        fontSize: 11,
                        color:
                            _allowMultiple
                                ? Colors.green.shade700
                                : Colors.grey,
                      ),
                    ),
                  ],
                ),
                Switch(
                  value: _allowMultiple,
                  onChanged: (val) => setState(() => _allowMultiple = val),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 2. Max Count Selector (When multi-select is enabled)
            if (_allowMultiple) ...[
              Row(
                children: [
                  const Text(
                    '最大选择数 (maxCount): ',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  Text(
                    '$_maxCount 个',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _maxCount.toDouble(),
                min: 1,
                max: 20,
                divisions: 19,
                label: '$_maxCount',
                onChanged: (val) => setState(() => _maxCount = val.toInt()),
              ),
              const SizedBox(height: 8),
            ],

            // 3. File Type Category Selector
            const Text(
              '支持的文件类型 (File Type & Extensions):',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  label: const Text('全部文件'),
                  selected: _selectedFileType == 'any',
                  onSelected: (sel) {
                    if (sel) setState(() => _selectedFileType = 'any');
                  },
                ),
                ChoiceChip(
                  label: const Text('仅图片 (Images)'),
                  selected: _selectedFileType == 'images',
                  onSelected: (sel) {
                    if (sel) setState(() => _selectedFileType = 'images');
                  },
                ),
                ChoiceChip(
                  label: const Text('办公文档 (Docs)'),
                  selected: _selectedFileType == 'docs',
                  onSelected: (sel) {
                    if (sel) setState(() => _selectedFileType = 'docs');
                  },
                ),
                ChoiceChip(
                  label: const Text('仅视频 (Videos)'),
                  selected: _selectedFileType == 'videos',
                  onSelected: (sel) {
                    if (sel) setState(() => _selectedFileType = 'videos');
                  },
                ),
                ChoiceChip(
                  label: const Text('自定义扩展名'),
                  selected: _selectedFileType == 'custom',
                  onSelected: (sel) {
                    if (sel) setState(() => _selectedFileType = 'custom');
                  },
                ),
              ],
            ),
            if (_selectedFileType == 'custom') ...[
              const SizedBox(height: 10),
              TextField(
                controller: _customExtController,
                decoration: const InputDecoration(
                  labelText: '允许的扩展名列表 (逗号分隔)',
                  hintText: 'pdf,docx,xlsx,txt,json',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 16),

            // Action Buttons
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _working ? null : _pickFiles,
                  icon: const Icon(Icons.folder_open),
                  label: Text(
                    _allowMultiple ? '选择文件 (多选限 $_maxCount 个)' : '选择文件 (单选)',
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed:
                      _working
                          ? null
                          : () => _pickImages(preserveOriginal: true),
                  icon: const Icon(Icons.photo_library),
                  label: Text(
                    _allowMultiple ? '相册选图 (多选限 $_maxCount 张)' : '相册选图 (单选)',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed:
                      _working
                          ? null
                          : () => _pickImages(preserveOriginal: false),
                  icon: const Icon(Icons.compress),
                  label: const Text('相册选图 (压缩)'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedFilesCard() {
    if (_selectedFiles.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                '暂未选择任何文件或图片。',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 8),
                    Text(
                      '已选择 ${_selectedFiles.length} 个文件 ${_allowMultiple ? '(上限 $_maxCount)' : ''}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                TextButton(
                  onPressed:
                      () => setState(() {
                        _selectedFiles = [];
                        _selected = null;
                      }),
                  child: const Text('清空'),
                ),
              ],
            ),
            const Divider(),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _selectedFiles.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final file = _selectedFiles[index];
                final isCurrent = _selected?.id == file.id;
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    backgroundColor:
                        isCurrent
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color:
                            isCurrent
                                ? Theme.of(context).colorScheme.primary
                                : null,
                      ),
                    ),
                  ),
                  title: Text(
                    file.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  subtitle: Text(
                    '大小: ${_formatSize(file.size)} · 格式: ${file.extension ?? file.mimeType ?? 'unknown'}\n'
                    '路径: ${file.originalPath ?? file.originalUri.toString()}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing:
                      isCurrent
                          ? const Chip(
                            label: Text('当前选中', style: TextStyle(fontSize: 10)),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          )
                          : null,
                  onTap: () => setState(() => _selected = file),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Widget _button(String title, VoidCallback? onPressed) => OutlinedButton(
    onPressed: _working ? null : onPressed,
    child: Text(title),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: children),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    child: SelectableText(
      value,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
    ),
  );
}

String _pretty(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(value);
