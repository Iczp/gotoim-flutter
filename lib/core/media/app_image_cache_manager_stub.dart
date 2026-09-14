import 'package:flutter_cache_manager/flutter_cache_manager.dart';

BaseCacheManager getAppImageCacheManager() => DefaultCacheManager();

Future<String?> getAppImageCachedPath(String url) async => null;

Future<void> clearAppImageCache() async {}

Future<Map<String, dynamic>> getAppImageCacheStats() async => <String, dynamic>{
      'directory': 'web-indexed-db',
      'fileCount': 0,
      'totalBytes': 0,
      'platform': 'web/stub',
    };
