import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme_tokens.dart';

/// 朋友圈缩略图/视频预览微标小组件
class ProfileMomentThumbnail extends StatelessWidget {
  const ProfileMomentThumbnail({
    required this.color,
    required this.icon,
    required this.tokens,
    this.isVideo = false,
    super.key,
  });

  final Color color;
  final IconData icon;
  final AppThemeTokens tokens;
  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(tokens.cardRadius * 0.35),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Icon(
            icon,
            size: 19,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
          if (isVideo)
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                padding: const EdgeInsets.all(1),
                decoration: const BoxDecoration(
                  color: Colors.black45,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow,
                  size: 8,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 视频号封面缩略图小组件
class ProfileVideoThumbnail extends StatelessWidget {
  const ProfileVideoThumbnail({
    required this.color,
    required this.tokens,
    super.key,
  });

  final Color color;
  final AppThemeTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 52,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(tokens.cardRadius * 0.35),
      ),
      child: Center(
        child: Icon(
          Icons.play_circle_outline_rounded,
          size: 18,
          color: Theme.of(
            context,
          ).colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
        ),
      ),
    );
  }
}
