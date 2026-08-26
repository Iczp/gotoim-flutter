import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class ChatObjectAvatar extends StatelessWidget {
  const ChatObjectAvatar({required this.name, required this.imageUrl, super.key});
  final String name;
  final String? imageUrl;
  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim() ?? '';
    if (url.isEmpty) return _fallback();
    return ClipOval(child: CachedNetworkImage(imageUrl: url, width: 48, height: 48, fit: BoxFit.cover, placeholder: (_, __) => const SizedBox(width: 48, height: 48, child: Center(child: CircularProgressIndicator(strokeWidth: 2))), errorWidget: (_, __, ___) => _fallback()));
  }
  Widget _fallback() => CircleAvatar(radius: 24, child: Text(name.isEmpty ? '?' : name.characters.first));
}
