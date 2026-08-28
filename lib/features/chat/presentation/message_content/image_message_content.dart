import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../data/models/chat_message.dart';

/// Displays an image message and its upload overlay.
class ImageMessageContent extends StatelessWidget {
  const ImageMessageContent({
    required this.message,
    required this.bytes,
    required this.apiBaseUrl,
    required this.progress,
    super.key,
  });

  final ChatMessage message;
  final Uint8List? bytes;
  final String apiBaseUrl;
  final double? progress;

  String get _url {
    final source = message.mediaUrl ?? '';
    final uri = Uri.tryParse(source);
    if (uri?.hasScheme == true || source.isEmpty) return source;
    return Uri.parse(apiBaseUrl).resolve(source).toString();
  }

  @override
  Widget build(BuildContext context) {
    final image =
        bytes != null
            ? Image.memory(bytes!, fit: BoxFit.cover)
            : _url.isNotEmpty
            ? CachedNetworkImage(
              imageUrl: _url,
              fit: BoxFit.cover,
              placeholder:
                  (_, _) => const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              errorWidget:
                  (_, _, _) =>
                      const Icon(Icons.broken_image_outlined, size: 42),
            )
            : const Center(child: Icon(Icons.image_outlined, size: 42));
    return InkWell(
      onTap:
          () => showDialog<void>(
            context: context,
            barrierColor: Colors.black87,
            builder:
                (_) => Dialog.fullscreen(
                  backgroundColor: Colors.black,
                  child: Stack(
                    children: <Widget>[
                      Center(
                        child: InteractiveViewer(
                          minScale: .5,
                          maxScale: 5,
                          child: image,
                        ),
                      ),
                      SafeArea(
                        child: IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
          ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 190,
          height: 190,
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
      ),
    );
  }
}
