import 'dart:io';
import 'package:flutter/foundation.dart';
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
    final localPath = message.localFilePath;
    if (localPath != null && localPath.isNotEmpty && !kIsWeb) {
      try {
        final file = File(localPath);
        if (file.existsSync()) {
          return Uri.file(localPath);
        }
      } catch (_) {}
    }
    final remote = message.mediaUrl;
    if (remote != null && remote.isNotEmpty) {
      return Uri.tryParse(resolveApiUrl(remote, apiBaseUrl));
    }
    if (localPath != null && localPath.isNotEmpty) {
      return Uri.file(localPath);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final coverUrl = message.videoCoverUrl ?? message.thumbnailUrl;
    final existingLocalPath = (message.localFilePath != null &&
            !kIsWeb &&
            File(message.localFilePath!).existsSync())
        ? message.localFilePath
        : null;
    final item = MediaPreviewItem(
      id: message.localId,
      messageId: message.localId,
      type: MediaPreviewType.video,
      source: _uri?.toString() ?? '',
      thumbnail: coverUrl != null ? resolveApiUrl(coverUrl, apiBaseUrl) : null,
      fileName: message.fileName.isNotEmpty ? message.fileName : '${message.localId}.mp4',
      localPath: mediaItems
              .where((it) => it.id == message.localId)
              .firstOrNull
              ?.localPath ??
          existingLocalPath,
      createdAt: message.createdAt,
      userId: message.ownerId.toString(),
      chatTarget: message.sessionUnitId,
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
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    alignment: Alignment.center,
                    fit: StackFit.expand,
                    children: <Widget>[
                      Container(color: Colors.black87),
                      if (item.thumbnail != null && item.thumbnail!.isNotEmpty)
                        Image.network(
                          item.thumbnail!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      Center(
                        child: Icon(
                          Icons.play_circle_fill,
                          color: Colors.white.withValues(alpha: 0.9),
                          size: compact ? 28 : 50,
                        ),
                      ),
                      if (!compact) ...[
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 28,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.65),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 8,
                          right: 8,
                          bottom: 5,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatFileSize(message.fileSize),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  shadows: [
                                    Shadow(color: Colors.black87, blurRadius: 4),
                                  ],
                                ),
                              ),
                              Text(
                                _formatDuration(message.videoDuration),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  shadows: [
                                    Shadow(color: Colors.black87, blurRadius: 4),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (progress != null && progress! < 1)
                        Center(
                          child: CircularProgressIndicator(
                            value: progress,
                            color: Colors.white,
                          ),
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

  String _formatDuration(Duration? duration) {
    if (duration == null || duration.inSeconds <= 0) return '';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
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
