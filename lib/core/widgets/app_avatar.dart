import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_environment.dart';
import '../theme/app_theme_tokens.dart';
import '../utils/api_url_resolver.dart';

/// Shared avatar used for people, chat objects, and session identities.
class AppAvatar extends ConsumerWidget {
  const AppAvatar({
    required this.name,
    required this.imageUrl,
    this.radius = 24,
    super.key,
  });

  final String name;
  final String? imageUrl;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = resolveApiUrl(
      imageUrl,
      ref.watch(appEnvironmentProvider).apiBaseUrl,
    );
    if (url.isEmpty) return _fallback(context);
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        placeholder:
            (context, url) => SizedBox(
              width: radius * 2,
              height: radius * 2,
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        errorWidget: (context, url, error) => _fallback(context),
      ),
    );
  }

  Widget _fallback(BuildContext context) {
    final tokens = context.appTokens;
    final gradientColors = tokens.getAvatarGradient(name);
    final initial =
        name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
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
          fontSize: radius * 0.9,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    );
  }
}
