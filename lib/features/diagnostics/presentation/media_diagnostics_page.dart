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
  SelectedFile? _selected;
  String _result = '尚未调用。';
  bool _working = false;
  bool _recording = false;
  bool _paused = false;

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

  Future<void> _select(Future<SelectedFile?> Function() action) =>
      _run(() async {
        final file = await action();
        if (file != null) _selected = file;
        return <String, Object?>{'file': file?.toJson()};
      });

  Future<void> _selectImages({required bool preserveOriginal}) =>
      _run(() async {
        final files = await ref
            .read(clientCapabilityServiceProvider)
            .chooseImage(
              MediaPickRequest(
                allowMultiple: true,
                preserveOriginal: preserveOriginal,
                imageQuality: 80,
                maxWidth: 1920,
                maxHeight: 1920,
              ),
            );
        if (files.isNotEmpty) _selected = files.first;
        return <String, Object>{
          'files': files.map((file) => file.toJson()).toList(),
        };
      });

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(body: Center(child: Text('开发诊断仅在 Debug 模式可用。')));
    }
    final capabilities = ref.read(clientCapabilityServiceProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('媒体与文件测试')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(
            title: '图片：相册、拍照、压缩与识码',
            children: [
              _button(
                'chooseImage（多选原图）',
                () => _selectImages(preserveOriginal: true),
              ),
              _button(
                'chooseImage（多选，压缩选取）',
                () => _selectImages(preserveOriginal: false),
              ),
              _button(
                'takePhoto（拍照）',
                () => _select(
                  () => capabilities.takePhoto(const MediaPickRequest()),
                ),
              ),
              _button(
                'compressImage（当前文件）',
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
          _Section(
            title: '视频：相册、拍摄、信息、缩略图与压缩',
            children: [
              _button(
                'chooseVideo（原视频）',
                () => _select(
                  () => capabilities.chooseVideo(const MediaPickRequest()),
                ),
              ),
              _button(
                'recordVideo（相机录像）',
                () => _select(
                  () => capabilities.recordVideo(
                    const MediaPickRequest(maxDuration: Duration(seconds: 60)),
                  ),
                ),
              ),
              _button(
                'getVideoInfo（当前文件）',
                _selected == null
                    ? null
                    : () => _run(
                      () async =>
                          (await capabilities.getVideoMetadata(
                            _selected!,
                          )).toJson(),
                    ),
              ),
              _button(
                'getVideoThumbnail（当前文件）',
                _selected == null
                    ? null
                    : () => _run(() async {
                      final bytes = await capabilities.createVideoThumbnail(
                        _selected!,
                      );
                      return <String, Object>{
                        'mimeType': 'image/jpeg',
                        'size': bytes.lengthInBytes,
                        'base64Preview': base64Encode(bytes.take(48).toList()),
                      };
                    }),
              ),
              _button(
                'compressVideo（当前文件）',
                _selected == null
                    ? null
                    : () => _select(
                      () => capabilities.compressVideo(
                        _selected!,
                        quality: VideoCompressionQuality.medium,
                      ),
                    ),
              ),
            ],
          ),
          _Section(
            title: '录音：开始、暂停、恢复、停止与取消',
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
                '停止并保留录音',
                !_recording
                    ? null
                    : () => _run(() async {
                      final file = await capabilities.stopAudioRecording();
                      _recording = false;
                      _paused = false;
                      if (file != null) _selected = file;
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
          _Section(
            title: '文件：另存为与清理临时引用',
            children: [
              _button(
                '另存为文本示例',
                () => _run(() async {
                  final file = await capabilities.saveFile(
                    FileSaveRequest(
                      fileName: 'gotoim-media-test.txt',
                      bytes: Uint8List.fromList(
                        utf8.encode('Goto IM media capability test'),
                      ),
                      mimeType: 'text/plain',
                      dialogTitle: '另存为测试文件',
                    ),
                  );
                  return <String, Object?>{'file': file?.toJson()};
                }),
              ),
              _button(
                '清理文件选择器临时文件',
                () => _run(
                  () async => <String, bool>{
                    'cleared': await capabilities.clearTemporaryFiles(),
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('当前文件', style: Theme.of(context).textTheme.titleMedium),
          SelectableText(
            _selected == null ? '无' : _pretty(_selected!.toJson()),
          ),
          const SizedBox(height: 16),
          Text('调用返回', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _Panel(value: _result),
        ],
      ),
    );
  }

  Widget _button(String label, VoidCallback? onPressed) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: FilledButton.tonal(
      onPressed: _working ? null : onPressed,
      child: Text(label),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          ...children,
        ],
      ),
    ),
  );
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
      style: const TextStyle(fontFamily: 'monospace'),
    ),
  );
}

String _pretty(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(value);
