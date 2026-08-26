import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_environment.dart';

class ChatObjectAvatar extends ConsumerWidget {
  const ChatObjectAvatar({
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
    final url = _resolveUrl(
      imageUrl?.trim() ?? '',
      ref.watch(appEnvironmentProvider).apiBaseUrl,
    );
    if (url.isEmpty) return _fallback();
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
        errorWidget: (context, url, error) => _fallback(),
      ),
    );
  }

  Widget _fallback() => CircleAvatar(
    radius: radius,
    child: Text(name.isEmpty ? '?' : name.characters.first),
  );
}

String _resolveUrl(String source, String baseUrl) {
  if (source.isEmpty) return '';
  final uri = Uri.tryParse(source);
  if (uri?.hasScheme == true) return source;
  if (!source.startsWith('/') || baseUrl.isEmpty) return source;
  return Uri.parse(baseUrl).resolve(source).toString();
}
