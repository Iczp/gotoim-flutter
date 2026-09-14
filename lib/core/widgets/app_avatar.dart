import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_environment.dart';
import '../media/app_image_cache_manager.dart';
import '../theme/app_theme_tokens.dart';
import '../utils/api_url_resolver.dart';
import 'avatar_preferences.dart';

/// Shared avatar used for people, chat objects, and session identities.
class AppAvatar extends ConsumerWidget {
  const AppAvatar({
    required this.name,
    required this.imageUrl,
    this.size,
    this.radius = 24,
    this.shape,
    this.onTap,
    this.heroTag,
    super.key,
  });

  final String name;
  final String? imageUrl;
  final double? size;
  final double radius;
  final AvatarShape? shape;
  final VoidCallback? onTap;
  final Object? heroTag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effectiveSize = size ?? radius * 2;
    final selectedShape =
        shape ??
        ref.watch(avatarPreferencesProvider.select((value) => value.shape)) ??
        AvatarShape.circle;
    final url = resolveApiUrl(
      imageUrl,
      ref.watch(appEnvironmentProvider).apiBaseUrl,
    );
    final child =
        url.isEmpty
            ? _fallback(context, effectiveSize, selectedShape)
            : ClipRRect(
              borderRadius: BorderRadius.circular(
                selectedShape == AvatarShape.circle ? effectiveSize / 2 : 10,
              ),
              child: CachedNetworkImage(
                imageUrl: url,
                cacheManager: AppImageCacheManager.instance,
                width: effectiveSize,
                height: effectiveSize,
                memCacheWidth:
                    (effectiveSize * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                memCacheHeight:
                    (effectiveSize * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 150),
                fadeOutDuration: const Duration(milliseconds: 150),
                placeholder:
                    (context, url) =>
                        _fallback(context, effectiveSize, selectedShape),
                errorWidget:
                    (context, url, error) =>
                        _fallback(context, effectiveSize, selectedShape),
              ),
            );
    final tappable =
        onTap == null ? child : InkWell(onTap: onTap, child: child);
    return heroTag == null ? tappable : Hero(tag: heroTag!, child: tappable);
  }

  Widget _fallback(BuildContext context, double size, AvatarShape shape) {
    final tokens = context.appTokens;
    final gradientColors = tokens.getAvatarGradient(name);
    final initial =
        name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape:
            shape == AvatarShape.circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius:
            shape == AvatarShape.circle ? null : BorderRadius.circular(10),
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: gradientColors.first.withValues(alpha: 0.25),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.45,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    );
  }
}
