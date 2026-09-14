import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/media/app_image_cache_manager.dart';
import '../../../../core/media/media_preview.dart';
import '../../../../core/utils/api_url_resolver.dart';
import '../../data/models/chat_message.dart';
import '../widgets/chat_message_delivery_state.dart';
import 'chat_message_presentation.dart';
import 'media_message_layout.dart';

/// Displays an image message and its upload overlay.
class ImageMessageContent extends StatelessWidget {
  const ImageMessageContent({
    required this.message,
    required this.bytes,
    required this.apiBaseUrl,
    required this.progress,
    required this.mediaItems,
    required this.initialIndex,
    this.presentation = ChatMessagePresentation.normal,
    this.onRetry,
    super.key,
  });

  final ChatMessage message;
  final Uint8List? bytes;
  final String apiBaseUrl;
  final double? progress;
  final List<MediaPreviewItem> mediaItems;
  final int initialIndex;
  final ChatMessagePresentation presentation;
  final VoidCallback? onRetry;

  String get _url => resolveApiUrl(message.mediaUrl, apiBaseUrl);

  @override
  Widget build(BuildContext context) {
    final thumbRaw = message.thumbnailUrl;
    final existingLocalPath = (message.localFilePath != null &&
            !kIsWeb &&
            File(message.localFilePath!).existsSync())
        ? message.localFilePath
        : null;
    final resolvedLocalPath = mediaItems
            .where((it) => it.id == message.localId)
            .firstOrNull
            ?.localPath ??
        existingLocalPath;
    final hasValidLocalPath = resolvedLocalPath != null &&
        !kIsWeb &&
        File(resolvedLocalPath).existsSync();

    final Widget image;
    if (bytes != null) {
      image = Image.memory(bytes!, fit: BoxFit.contain);
    } else if (hasValidLocalPath) {
      image = Image.file(File(resolvedLocalPath), fit: BoxFit.contain);
    } else if (_url.isNotEmpty) {
      image = CachedNetworkImage(
        imageUrl: _url,
        cacheManager: AppImageCacheManager.instance,
        fit: BoxFit.contain,
        placeholder:
            (_, _) => const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        errorWidget:
            (_, _, _) =>
                const Icon(Icons.broken_image_outlined, size: 42),
      );
    } else {
      image = const Center(child: Icon(Icons.image_outlined, size: 42));
    }

    final item = MediaPreviewItem(
      id: message.localId,
      messageId: message.localId,
      type: MediaPreviewType.image,
      source: _url,
      thumbnail: thumbRaw != null ? resolveApiUrl(thumbRaw, apiBaseUrl) : _url,
      fileName: message.fileName.isNotEmpty
          ? message.fileName
          : '${message.localId}${message.fileSuffix.isNotEmpty ? message.fileSuffix : '.jpg'}',
      localPath: resolvedLocalPath,
      createdAt: message.createdAt,
      userId: message.ownerId.toString(),
      chatTarget: message.sessionUnitId,
      bytes: bytes,
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
    final inkWell = InkWell(
      onTap:
          () => MediaPreview.open(
            context,
            items: previewItems,
            initialIndex: resolvedInitialIndex < 0 ? 0 : resolvedInitialIndex,
          ),
      child: HeroMode(
        enabled: presentation == ChatMessagePresentation.normal,
        child: Hero(
          tag: item.heroTag,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = presentation == ChatMessagePresentation.quote;
              final size =
                  compact
                      ? const Size(56, 56)
                      : MediaMessageLayout.sizeFor(
                        constraints: constraints,
                        aspectRatio: message.mediaAspectRatio,
                        fallbackAspectRatio: 4 / 3,
                      );
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      image,
                      if (progress != null && progress! < 1)
                        ColoredBox(
                          color: Colors.black38,
                          child: Center(
                            child: SizedBox.square(
                              dimension: 46,
                              child: CircularProgressIndicator(
                                value: progress,
                                color: Colors.white,
                              ),
                            ),
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

    Widget body = inkWell;
    if (message.isMine &&
        presentation == ChatMessagePresentation.normal &&
        (message.state == 'sending' || message.state == 'failed')) {
      body = Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          ChatMessageDeliveryState(
            isMine: message.isMine,
            state: message.state,
            onRetry: onRetry,
          ),
          Flexible(child: inkWell),
        ],
      );
    }

    return Align(
      alignment: message.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: body,
    );
  }
}
