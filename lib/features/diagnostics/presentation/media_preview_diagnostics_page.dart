import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/media/media_preview.dart';

/// 诊断中心：统一媒体预览与下载缓存诊断页面
class MediaPreviewDiagnosticsPage extends StatefulWidget {
  const MediaPreviewDiagnosticsPage({super.key});

  @override
  State<MediaPreviewDiagnosticsPage> createState() =>
      _MediaPreviewDiagnosticsPageState();
}

class _MediaPreviewDiagnosticsPageState
    extends State<MediaPreviewDiagnosticsPage> {
  static const _defaultImageUrl = 'https://picsum.photos/id/1039/1440/2160';
  static const _defaultImageThumb = 'https://picsum.photos/id/1039/200/300';
  static const _defaultVideoUrl =
      'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4';
  static const _defaultVideoThumb =
      'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly-thumbnail.png';

  late final TextEditingController _imageCtrl =
      TextEditingController(text: _defaultImageUrl);
  late final TextEditingController _imageThumbCtrl =
      TextEditingController(text: _defaultImageThumb);
  late final TextEditingController _videoCtrl =
      TextEditingController(text: _defaultVideoUrl);
  late final TextEditingController _videoThumbCtrl =
      TextEditingController(text: _defaultVideoThumb);

  String _status = '未执行';
  String _detail = '';
  int _elapsedMs = 0;

  @override
  void dispose() {
    _imageCtrl.dispose();
    _imageThumbCtrl.dispose();
    _videoCtrl.dispose();
    _videoThumbCtrl.dispose();
    super.dispose();
  }

  void _restoreDefaults() {
    setState(() {
      _imageCtrl.text = _defaultImageUrl;
      _imageThumbCtrl.text = _defaultImageThumb;
      _videoCtrl.text = _defaultVideoUrl;
      _videoThumbCtrl.text = _defaultVideoThumb;
      _status = '已恢复默认参数';
      _detail = '';
    });
  }

  Future<void> _clearCache() async {
    final sw = Stopwatch()..start();
    try {
      if (kIsWeb) {
        setState(() {
          _status = 'Web 平台无需清理本地磁盘缓存';
          _elapsedMs = sw.elapsedMilliseconds;
        });
        return;
      }
      final root = await getApplicationSupportDirectory();
      final dir = Directory('${root.path}${Platform.pathSeparator}attachments');
      int count = 0;
      if (await dir.exists()) {
        final files = dir.listSync();
        for (final f in files) {
          if (f is File && f.path.contains('diagnostic_')) {
            await f.delete();
            count++;
          }
        }
      }
      sw.stop();
      setState(() {
        _status = '成功清理了 $count 个诊断媒体缓存文件';
        _detail = '缓存目录：${dir.path}';
        _elapsedMs = sw.elapsedMilliseconds;
      });
    } catch (e) {
      sw.stop();
      setState(() {
        _status = '清理缓存失败：$e';
        _elapsedMs = sw.elapsedMilliseconds;
      });
    }
  }

  Future<void> _openPreview(int initialIndex) async {
    final sw = Stopwatch()..start();
    setState(() {
      _status = '正在启动预览...';
      _detail = 'Hero 动画过渡中，未缓存文件将展示缩略图及下载百分比进度环';
    });

    final items = [
      MediaPreviewItem(
        id: 'diagnostic_image_test',
        messageId: 'diag_msg_1',
        type: MediaPreviewType.image,
        source: _imageCtrl.text.trim(),
        thumbnail: _imageThumbCtrl.text.trim(),
        fileName: 'diagnostic_image.jpg',
        heroTag: 'diag-hero-image',
      ),
      MediaPreviewItem(
        id: 'diagnostic_video_test',
        messageId: 'diag_msg_2',
        type: MediaPreviewType.video,
        source: _videoCtrl.text.trim(),
        thumbnail: _videoThumbCtrl.text.trim(),
        fileName: 'diagnostic_bee.mp4',
        heroTag: 'diag-hero-video',
      ),
    ];

    try {
      await MediaPreview.open(
        context,
        initialIndex: initialIndex,
        items: items,
      );
      sw.stop();
      if (mounted) {
        setState(() {
          _status = '预览已正常关闭';
          _elapsedMs = sw.elapsedMilliseconds;
          _detail = '测试完成。左右滑动切换图片与视频，下拉手势可平滑返回。';
        });
      }
    } catch (error, stack) {
      sw.stop();
      if (mounted) {
        setState(() {
          _status = '预览异常：$error';
          _elapsedMs = sw.elapsedMilliseconds;
          _detail = '$stack';
        });
      }
    }
  }

  void _copyLog() {
    final log = '''
状态: $_status
耗时: ${_elapsedMs}ms
详情: $_detail
图片: ${_imageCtrl.text}
缩略图: ${_imageThumbCtrl.text}
视频: ${_videoCtrl.text}
视频封面: ${_videoThumbCtrl.text}
''';
    Clipboard.setData(ClipboardData(text: log));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制诊断信息到剪贴板')),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('媒体预览与下载缓存诊断中心'),
          actions: [
            IconButton(
              tooltip: '恢复默认参数',
              icon: const Icon(Icons.restore),
              onPressed: _restoreDefaults,
            ),
            IconButton(
              tooltip: '复制诊断信息',
              icon: const Icon(Icons.copy),
              onPressed: _copyLog,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '功能说明',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '测试图片与视频全屏预览能力：首帧通过 Hero 展示缩略图，若原图/原视频尚未下载，居中浮动呈现下载百分比进度环；下载完成后平滑转换为大图手势交互组件或视频播放器。',
                      style: TextStyle(fontSize: 12, height: 1.4),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: const [
                        Chip(label: Text('Android ✓'), visualDensity: VisualDensity.compact),
                        Chip(label: Text('iOS ✓'), visualDensity: VisualDensity.compact),
                        Chip(label: Text('Windows ✓'), visualDensity: VisualDensity.compact),
                        Chip(label: Text('macOS ✓'), visualDensity: VisualDensity.compact),
                        Chip(label: Text('Linux ✓'), visualDensity: VisualDensity.compact),
                        Chip(label: Text('Web ✓'), visualDensity: VisualDensity.compact),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _imageCtrl,
              decoration: const InputDecoration(
                labelText: '测试大图 URL',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _imageThumbCtrl,
              decoration: const InputDecoration(
                labelText: '大图缩略图 URL',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _videoCtrl,
              decoration: const InputDecoration(
                labelText: '测试视频 URL',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _videoThumbCtrl,
              decoration: const InputDecoration(
                labelText: '视频封面缩略图 URL',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Hero(
                    tag: 'diag-hero-image',
                    child: GestureDetector(
                      onTap: () => _openPreview(0),
                      child: Container(
                        height: 90,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade300),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.network(
                              _imageThumbCtrl.text.trim(),
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const Icon(Icons.image),
                            ),
                            const Center(
                              child: Text(
                                '点击预览大图\n(Hero 锚点)',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Hero(
                    tag: 'diag-hero-video',
                    child: GestureDetector(
                      onTap: () => _openPreview(1),
                      child: Container(
                        height: 90,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade900,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.purple.shade300),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.network(
                              _videoThumbCtrl.text.trim(),
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const Icon(Icons.video_collection),
                            ),
                            const Center(
                              child: Icon(
                                Icons.play_circle_fill,
                                color: Colors.white,
                                size: 36,
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
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _clearCache,
              icon: const Icon(Icons.cleaning_services_rounded),
              label: const Text('清理诊断媒体本地缓存（便于复测下载百分比）'),
            ),
            const SizedBox(height: 16),
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          '执行状态：',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Expanded(child: Text(_status)),
                        if (_elapsedMs > 0)
                          Text(
                            '耗时: ${_elapsedMs}ms',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                      ],
                    ),
                    if (_detail.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        _detail,
                        style: const TextStyle(fontSize: 12, color: Colors.black87),
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
