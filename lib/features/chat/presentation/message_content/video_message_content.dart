import 'package:flutter/material.dart';

import '../../../../core/floating_window/floating_window.dart';
import '../../../../core/utils/api_url_resolver.dart';
import '../../../../core/media/media_preview.dart';
import '../../data/models/chat_message.dart';
import 'chat_message_presentation.dart';
import 'media_message_layout.dart';

/// Displays a video message preview and opens its player on demand.
class VideoMessageContent extends StatelessWidget {
  const VideoMessageContent({
    required this.message,
    required this.apiBaseUrl,
    required this.progress,
    required this.mediaItems,
    required this.initialIndex,
    this.presentation = ChatMessagePresentation.normal,
    super.key,
  });

  final ChatMessage message;
  final String apiBaseUrl;
  final double? progress;
  final List<MediaPreviewItem> mediaItems;
  final int initialIndex;
  final ChatMessagePresentation presentation;

  Uri? get _uri {
    final source = message.mediaUrl ?? message.localFilePath ?? '';
    if (source.isEmpty) return null;
    if (message.localFilePath != null) return Uri.file(source);
    return Uri.tryParse(resolveApiUrl(source, apiBaseUrl));
  }

  @override
  Widget build(BuildContext context) {
    final item = MediaPreviewItem(
      id: message.localId,
      messageId: message.localId,
      type: MediaPreviewType.video,
      source: _uri?.toString() ?? '',
      heroTag: buildMediaHeroTag(
        messageId: message.localId,
        mediaId: message.localId,
      ),
    );
    final resolvedInitialIndex = mediaItems.indexWhere(
      (candidate) => candidate.id == message.localId,
    );
    final previewItems =
        resolvedInitialIndex < 0
            ? <MediaPreviewItem>[item, ...mediaItems]
            : mediaItems;
    final compact = presentation == ChatMessagePresentation.quote;
    return InkWell(
      onTap:
          _uri == null
              ? null
              : () => _openOrRestore(
                context,
                previewItems,
                resolvedInitialIndex < 0 ? 0 : resolvedInitialIndex,
              ),
      child: HeroMode(
        enabled: presentation == ChatMessagePresentation.normal,
        child: Hero(
          tag: item.heroTag,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size =
                  compact
                      ? const Size(90, 56)
                      : MediaMessageLayout.sizeFor(
                        constraints: constraints,
                        aspectRatio: message.mediaAspectRatio,
                        fallbackAspectRatio: 16 / 9,
                      );
              return SizedBox(
                width: size.width,
                height: size.height,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      Icon(
                        Icons.play_circle_fill,
                        color: Colors.white,
                        size: compact ? 28 : 52,
                      ),
                      if (!compact)
                        Positioned(
                          left: 8,
                          right: 8,
                          bottom: 7,
                          child: Text(
                            message.fileName.isEmpty ? '视频' : message.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      if (progress != null && progress! < 1)
                        CircularProgressIndicator(
                          value: progress,
                          color: Colors.white,
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _openOrRestore(
    BuildContext context,
    List<MediaPreviewItem> items,
    int targetIndex,
  ) {
    final sessionId = 'video:${message.localId}:${message.localId}';
    if (FloatingWindowScope.of(context).restore(sessionId)) return;
    MediaPreview.open(context, items: items, initialIndex: targetIndex);
  }
}
