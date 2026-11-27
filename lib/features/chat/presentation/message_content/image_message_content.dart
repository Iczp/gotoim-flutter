import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/media/app_image_cache_manager.dart';
import '../../../../core/media/media_preview.dart';
import '../../../../core/services/file/attachment_transfer_service.dart';
import '../../../../core/utils/api_url_resolver.dart';
import '../../data/models/chat_message.dart';
import '../widgets/chat_message_delivery_state.dart';
import 'authorized_private_attachment_gate.dart';
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
    this.rootMessageId,
    this.attachmentTransferService,
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
  final int? rootMessageId;
  final AttachmentTransferService? attachmentTransferService;
  final ChatMessagePresentation presentation;
  final VoidCallback? onRetry;

  String get _url => resolveAttachmentUrl(
    message.mediaUrl,
    apiBaseUrl,
    sessionUnitId: message.sessionUnitId,
    messageId: message.serverId,
    rootMessageId: rootMessageId,
  );

  @override
  Widget build(BuildContext context) {
    final thumbRaw = message.thumbnailUrl;
    final resolvedThumbUrl =
        thumbRaw != null
            ? resolveAttachmentUrl(
              thumbRaw,
              apiBaseUrl,
              sessionUnitId: message.sessionUnitId,
              messageId: message.serverId,
              rootMessageId: rootMessageId,
            )
            : _url;
    final isBlockedLocally = message.isRollbacked || message.isDeleted;
    final existingLocalPath =
        (!isBlockedLocally &&
                message.localFilePath != null &&
                !kIsWeb &&
                File(message.localFilePath!).existsSync())
            ? message.localFilePath
            : null;
    final resolvedLocalPath =
        isBlockedLocally
            ? null
            : (mediaItems
                    .where((it) => it.id == message.localId)
                    .firstOrNull
                    ?.localPath ??
                existingLocalPath);
    final hasValidLocalPath =
        resolvedLocalPath != null &&
        !kIsWeb &&
        File(resolvedLocalPath).existsSync();

    final item = MediaPreviewItem(
      id: message.localId,
      messageId: message.localId,
      type: MediaPreviewType.image,
      source: _url,
      thumbnail: resolvedThumbUrl,
      fileName:
          message.fileName.isNotEmpty
              ? message.fileName
              : '${message.localId}${message.fileSuffix.isNotEmpty ? message.fileSuffix : '.jpg'}',
      localPath: resolvedLocalPath,
      createdAt: message.createdAt,
      userId: message.ownerId.toString(),
      chatTarget: message.sessionUnitId,
      serverMessageId: message.serverId,
      rootMessageId: rootMessageId,
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
    final targetPreviewIndex =
        resolvedInitialIndex < 0 ? 0 : resolvedInitialIndex;

    Widget buildInnerMedia(BuildContext context) {
      if (bytes != null && !isBlockedLocally) {
        return Image.memory(bytes!, fit: BoxFit.contain);
      }
      if (hasValidLocalPath) {
        return Image.file(File(resolvedLocalPath), fit: BoxFit.contain);
      }
      if (_url.isNotEmpty) {
        return CachedNetworkImage(
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
      }
      return const Center(child: Icon(Icons.image_outlined, size: 42));
    }

    Widget wrapInteractiveBox(
      BuildContext context, {
      required Widget child,
      required bool allowTap,
    }) {
      final sizedBox = HeroMode(
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
                      child,
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
      );
      if (!allowTap) return sizedBox;
      return InkWell(
        onTap:
            () => MediaPreview.open(
              context,
              items: previewItems,
              initialIndex: targetPreviewIndex,
            ),
        child: sizedBox,
      );
    }

    final Widget inkWell;
    if (bytes != null && !isBlockedLocally) {
      inkWell = wrapInteractiveBox(
        context,
        child: buildInnerMedia(context),
        allowTap: true,
      );
    } else {
      final probeUrl = _url.isNotEmpty ? _url : resolvedThumbUrl;
      inkWell = AuthorizedPrivateAttachmentGate(
        url: probeUrl,
        apiBaseUrl: apiBaseUrl,
        accessContext: AttachmentAccessContext(
          sessionUnitId: message.sessionUnitId,
          messageId: message.serverId,
          rootMessageId: rootMessageId,
        ),
        userId: message.ownerId.toString(),
        isBlockedLocally: isBlockedLocally,
        transferService: attachmentTransferService,
        builder:
            (ctx) => wrapInteractiveBox(
              ctx,
              child: buildInnerMedia(ctx),
              allowTap: true,
            ),
        deniedBuilder:
            (ctx) => wrapInteractiveBox(
              ctx,
              child: const ColoredBox(
                color: Color(0x1F000000),
                child: Center(child: Icon(Icons.lock_outline, size: 28)),
              ),
              allowTap: false,
            ),
        loadingBuilder:
            (ctx) => wrapInteractiveBox(
              ctx,
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              allowTap: false,
            ),
      );
    }

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
