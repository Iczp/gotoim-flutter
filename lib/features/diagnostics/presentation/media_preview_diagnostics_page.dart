import 'package:flutter/material.dart';

import '../../../core/media/media_preview.dart';

class MediaPreviewDiagnosticsPage extends StatefulWidget {
  const MediaPreviewDiagnosticsPage({super.key});

  @override
  State<MediaPreviewDiagnosticsPage> createState() =>
      _MediaPreviewDiagnosticsPageState();
}

class _MediaPreviewDiagnosticsPageState
    extends State<MediaPreviewDiagnosticsPage> {
  static const _imageUrl = 'https://picsum.photos/id/1039/1440/2160';
  static const _videoUrl =
      'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4';

  String _status = '未执行';

  Future<void> _openPreview(int initialIndex) async {
    setState(() => _status = '预览已打开；请测试缩放、左右切换、下拉关闭和视频播放。');
    try {
      await MediaPreview.open(
        context,
        initialIndex: initialIndex,
        items: const [
          MediaPreviewItem(
            id: 'diagnostic-image',
            messageId: 'diagnostic',
            type: MediaPreviewType.image,
            source: _imageUrl,
            heroTag: 'diagnostic-media-image',
          ),
          MediaPreviewItem(
            id: 'diagnostic-video',
            messageId: 'diagnostic',
            type: MediaPreviewType.video,
            source: _videoUrl,
            heroTag: 'diagnostic-media-video',
          ),
        ],
      );
      if (mounted) setState(() => _status = '预览已关闭。');
    } catch (error) {
      if (mounted) setState(() => _status = '执行失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('统一媒体预览测试')),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('支持平台：Android、iOS、Windows、macOS、Linux、Web（视频能力取决于平台播放器）。'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _openPreview(0),
            icon: const Icon(Icons.image_outlined),
            label: const Text('从图片打开（含图片与视频）'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _openPreview(1),
            icon: const Icon(Icons.play_circle_outline),
            label: const Text('从视频打开'),
          ),
          const SizedBox(height: 24),
          Text('执行状态：$_status'),
          const SizedBox(height: 8),
          const Text('默认数据为公开的图片与视频 URL；请在联网环境下运行。'),
        ],
      ),
    ),
  );
}
