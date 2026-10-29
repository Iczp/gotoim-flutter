import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_environment.dart';
import '../../application/social_identity_controller.dart';
import '../../data/social_repository.dart';

class SocialMediaImage extends ConsumerWidget {
  const SocialMediaImage({super.key, required this.url, required this.fit});
  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final raw = Uri.tryParse(url.trim());
    final base = Uri.tryParse(
      ref.watch(appEnvironmentProvider).socialApiBaseUrl,
    );
    final resolved = raw == null || base == null ? null : base.resolveUri(raw);
    final valid =
        resolved != null &&
        (resolved.scheme == 'http' || resolved.scheme == 'https') &&
        resolved.host.isNotEmpty;
    if (!valid) return _error(context);
    final socialDownload =
        resolved.origin == base!.origin &&
        resolved.path.startsWith('/api/social/media-assets/download/');
    if (socialDownload) {
      final actor = ref.watch(
        socialIdentityProvider.select((state) => state.actor?.id),
      );
      final path = Uri(
        path: resolved.path,
        query: resolved.hasQuery ? resolved.query : null,
      ).toString();
      final bytes = ref.watch(
        socialMediaBytesProvider((path: path, actorId: actor)),
      );
      return bytes.when(
        data:
            (data) => Image.memory(
              data,
              fit: fit,
              errorBuilder: (_, __, ___) => _error(context),
            ),
        loading: () => _loading(context),
        error: (_, __) => _error(context),
      );
    }
    return CachedNetworkImage(
      imageUrl: resolved.toString(),
      fit: fit,
      placeholder: (context, _) => _loading(context),
      errorWidget: (context, _, __) => _error(context),
    );
  }

  Widget _loading(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: const Center(
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );

  Widget _error(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: const Center(
      child: Icon(Icons.broken_image_outlined, color: Colors.grey),
    ),
  );
}
