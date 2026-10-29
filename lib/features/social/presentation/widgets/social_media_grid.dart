import 'package:flutter/material.dart';

import '../../data/social_repository.dart';
import 'social_media_image.dart';

/// Renders 1 to 4 media items in authentic X.com adaptive grid layout.
class SocialMediaGrid extends StatelessWidget {
  const SocialMediaGrid({
    super.key,
    required this.medias,
    this.onMediaTap,
    this.borderRadius = 14.0,
  });

  final List<SocialPostMedia> medias;
  final void Function(int index, List<SocialPostMedia> allMedias)? onMediaTap;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    if (medias.isEmpty) return const SizedBox.shrink();

    final borderColor = Theme.of(context).dividerColor.withValues(alpha: 0.35);

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderColor, width: 0.8),
      ),
      clipBehavior: Clip.antiAlias,
      child: _buildGrid(context),
    );
  }

  Widget _buildGrid(BuildContext context) {
    final count = medias.length;

    if (count == 1) {
      final media = medias.first;
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: _buildSingleItem(context, media, 0),
      );
    }

    if (count == 2) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _buildSingleItem(context, medias[0], 0)),
            const SizedBox(width: 2),
            Expanded(child: _buildSingleItem(context, medias[1], 1)),
          ],
        ),
      );
    }

    if (count == 3) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 1,
              child: _buildSingleItem(context, medias[0], 0),
            ),
            const SizedBox(width: 2),
            Expanded(
              flex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _buildSingleItem(context, medias[1], 1)),
                  const SizedBox(height: 2),
                  Expanded(child: _buildSingleItem(context, medias[2], 2)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 4 or more: 2x2 grid
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _buildSingleItem(context, medias[0], 0)),
                const SizedBox(width: 2),
                Expanded(child: _buildSingleItem(context, medias[1], 1)),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _buildSingleItem(context, medias[2], 2)),
                const SizedBox(width: 2),
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildSingleItem(context, medias[3], 3),
                      if (count > 4)
                        Container(
                          color: Colors.black54,
                          alignment: Alignment.center,
                          child: Text(
                            '+${count - 4}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleItem(
    BuildContext context,
    SocialPostMedia media,
    int index,
  ) {
    return GestureDetector(
      onTap: () => onMediaTap?.call(index, medias),
      child: Stack(
        fit: StackFit.expand,
        children: [
          SocialMediaImage(
            url: media.thumbnailUrl?.isNotEmpty == true ? media.thumbnailUrl! : media.url,
            fit: BoxFit.cover,
          ),
          if (media.isVideo)
            Center(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
