import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/floating_window/floating_window.dart';
import '../../../../core/media/app_image_cache_manager.dart';
import '../../../../core/services/file/attachment_transfer_service.dart';
import '../../../../core/utils/api_url_resolver.dart';
import '../../../../core/media/media_preview.dart';
import '../../data/models/chat_message.dart';
import '../widgets/chat_message_delivery_state.dart';
import 'authorized_private_attachment_gate.dart';
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
    this.rootMessageId,
    this.attachmentTransferService,
    this.presentation = ChatMessagePresentation.normal,
    this.onRetry,
    super.key,
  });

  final ChatMessage message;
  final String apiBaseUrl;
  final double? progress;
  final List<MediaPreviewItem> mediaItems;
  final int initialIndex;
  final int? rootMessageId;
  final AttachmentTransferService? attachmentTransferService;
  final ChatMessagePresentation presentation;
  final VoidCallback? onRetry;

  String? get _resolvedRemoteUrl {
    final remote = message.mediaUrl;
    if (remote == null || remote.isEmpty) return null;
    final resolved = resolveAttachmentUrl(
      remote,
      apiBaseUrl,
      sessionUnitId: message.sessionUnitId,
      messageId: message.serverId,
      rootMessageId: rootMessageId,
    );
    return resolved.isEmpty ? null : resolved;
  }

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
    final resolved = _resolvedRemoteUrl;
    if (resolved != null) {
      return Uri.tryParse(resolved);
    }
    if (localPath != null && localPath.isNotEmpty) {
      return Uri.file(localPath);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isBlockedLocally = message.isRollbacked || message.isDeleted;
    final coverUrl = message.videoCoverUrl ?? message.thumbnailUrl;
    final gifUrl = message.videoGifUrl;
    final resolvedCoverUrl =
        coverUrl != null && coverUrl.isNotEmpty
            ? resolveAttachmentUrl(
              coverUrl,
              apiBaseUrl,
              sessionUnitId: message.sessionUnitId,
              messageId: message.serverId,
              rootMessageId: rootMessageId,
            )
            : null;
    final resolvedGifUrl =
        gifUrl != null && gifUrl.isNotEmpty
            ? resolveAttachmentUrl(
              gifUrl,
              apiBaseUrl,
              sessionUnitId: message.sessionUnitId,
              messageId: message.serverId,
              rootMessageId: rootMessageId,
            )
            : null;
    final localThumbPath =
        (!isBlockedLocally &&
                !kIsWeb &&
                message.localThumbnailPath != null &&
                message.localThumbnailPath!.isNotEmpty &&
                File(message.localThumbnailPath!).existsSync())
            ? message.localThumbnailPath
            : null;
    final existingLocalPath =
        (!isBlockedLocally &&
                message.localFilePath != null &&
                !kIsWeb &&
                File(message.localFilePath!).existsSync())
            ? message.localFilePath
            : null;
    final item = MediaPreviewItem(
      id: message.localId,
      messageId: message.localId,
      type: MediaPreviewType.video,
      source: _uri?.toString() ?? '',
      thumbnail:
          resolvedCoverUrl ??
          (localThumbPath != null ? Uri.file(localThumbPath).toString() : null),
      fileName:
          message.fileName.isNotEmpty ? message.fileName : '${message.localId}.mp4',
      localPath:
          isBlockedLocally
              ? null
              : (mediaItems
                      .where((it) => it.id == message.localId)
                      .firstOrNull
                      ?.localPath ??
                  existingLocalPath),
      createdAt: message.createdAt,
      userId: message.ownerId.toString(),
      chatTarget: message.sessionUnitId,
      serverMessageId: message.serverId,
      rootMessageId: rootMessageId,
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

    Widget buildCardBox(
      BuildContext context, {
      required bool authorized,
    }) {
      final innerBox = HeroMode(
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
                      if (authorized) ...[
                        if (!compact && resolvedGifUrl != null)
                          CachedNetworkImage(
                            imageUrl: resolvedGifUrl,
                            cacheManager: AppImageCacheManager.instance,
                            fit: BoxFit.cover,
                            placeholder:
                                (_, _) =>
                                    resolvedCoverUrl != null
                                        ? CachedNetworkImage(
                                          imageUrl: resolvedCoverUrl,
                                          cacheManager:
                                              AppImageCacheManager.instance,
                                          fit: BoxFit.cover,
                                          errorWidget:
                                              (_, _, _) =>
                                                  const SizedBox.shrink(),
                                        )
                                        : const SizedBox.shrink(),
                            errorWidget:
                                (_, _, _) =>
                                    resolvedCoverUrl != null
                                        ? CachedNetworkImage(
                                          imageUrl: resolvedCoverUrl,
                                          cacheManager:
                                              AppImageCacheManager.instance,
                                          fit: BoxFit.cover,
                                          errorWidget:
                                              (_, _, _) =>
                                                  localThumbPath != null
                                                      ? Image.file(
                                                        File(localThumbPath),
                                                        fit: BoxFit.cover,
                                                        errorBuilder:
                                                            (_, _, _) =>
                                                                const SizedBox.shrink(),
                                                      )
                                                      : const SizedBox.shrink(),
                                        )
                                        : (localThumbPath != null
                                            ? Image.file(
                                              File(localThumbPath),
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (_, _, _) =>
                                                      const SizedBox.shrink(),
                                            )
                                            : const SizedBox.shrink()),
                          )
                        else if (resolvedCoverUrl != null)
                          CachedNetworkImage(
                            imageUrl: resolvedCoverUrl,
                            cacheManager: AppImageCacheManager.instance,
                            fit: BoxFit.cover,
                            errorWidget:
                                (_, _, _) =>
                                    localThumbPath != null
                                        ? Image.file(
                                          File(localThumbPath),
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (_, _, _) =>
                                                  const SizedBox.shrink(),
                                        )
                                        : const SizedBox.shrink(),
                          )
                        else if (localThumbPath != null)
                          Image.file(
                            File(localThumbPath),
                            fit: BoxFit.cover,
                            errorBuilder:
                                (_, _, _) => const SizedBox.shrink(),
                          ),
                      ],
                      if (authorized &&
                          !compact &&
                          gifUrl != null &&
                          gifUrl.isNotEmpty)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'GIF',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      Center(
                        child: Icon(
                          authorized
                              ? Icons.play_circle_fill
                              : Icons.lock_outline,
                          color: Colors.white.withValues(alpha: 0.9),
                          size: compact ? 28 : (authorized ? 50 : 32),
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
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.68),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    value: progress,
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${(progress! * 100).clamp(0, 100).round()}%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
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
      if (!authorized || _uri == null) return innerBox;
      return InkWell(
        onTap:
            () => _openOrRestore(
              context,
              previewItems,
              resolvedInitialIndex < 0 ? 0 : resolvedInitialIndex,
            ),
        child: innerBox,
      );
    }

    final probeUrl =
        _resolvedRemoteUrl ?? resolvedCoverUrl ?? resolvedGifUrl ?? '';
    final bubble = AuthorizedPrivateAttachmentGate(
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
      builder: (ctx) => buildCardBox(ctx, authorized: true),
      deniedBuilder: (ctx) => buildCardBox(ctx, authorized: false),
      loadingBuilder: (ctx) => buildCardBox(ctx, authorized: false),
    );

    if (presentation == ChatMessagePresentation.normal &&
        message.isMine &&
        (message.state == 'sending' || message.state == 'failed')) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          ChatMessageDeliveryState(
            isMine: message.isMine,
            state: message.state,
            errorMessage: message.errorMessage,
            onRetry: onRetry,
          ),
          Flexible(child: bubble),
        ],
      );
    }

    return bubble;
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
