import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

import 'app_image_cache_manager.dart';

ImageProvider createImageProvider(String source) {
  final trimmed = source.trim();
  if (trimmed.startsWith('data:image/')) {
    final commaIndex = trimmed.indexOf(',');
    if (commaIndex != -1) {
      try {
        final bytes = base64Decode(trimmed.substring(commaIndex + 1));
        return MemoryImage(bytes);
      } catch (_) {}
    }
  }
  if (trimmed.startsWith('assets/') || trimmed.startsWith('packages/')) {
    return AssetImage(trimmed);
  }
  final uri = Uri.tryParse(trimmed);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    return CachedNetworkImageProvider(
      trimmed,
      cacheManager: AppImageCacheManager.instance,
    );
  }
  final path = uri?.scheme == 'file' ? uri!.toFilePath() : trimmed;
  return FileImage(File(path));
}
