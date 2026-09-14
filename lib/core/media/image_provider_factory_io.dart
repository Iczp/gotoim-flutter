import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

import 'app_image_cache_manager.dart';

ImageProvider createImageProvider(String source) {
  final uri = Uri.tryParse(source);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    return CachedNetworkImageProvider(
      source,
      cacheManager: AppImageCacheManager.instance,
    );
  }
  final path = uri?.scheme == 'file' ? uri!.toFilePath() : source;
  return FileImage(File(path));
}
