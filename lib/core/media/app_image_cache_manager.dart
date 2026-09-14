import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'app_image_cache_manager_stub.dart'
    if (dart.library.io) 'app_image_cache_manager_io.dart'
    as platform;

/// 全局统一的应用图片离线持久缓存管理器
abstract class AppImageCacheManager {
  /// 全局单例 CacheManager，供 [CachedNetworkImage] 及 [CachedNetworkImageProvider] 使用
  static BaseCacheManager get instance => platform.getAppImageCacheManager();

  /// 检查某远程 URL 在本地是否已有缓存并返回本地物理绝对路径（若无则返回 null）
  static Future<String?> getCachedPath(String url) =>
      platform.getAppImageCachedPath(url);

  /// 清理图片持久缓存
  static Future<void> clearAll() => platform.clearAppImageCache();

  /// 获取缓存统计信息（目录、文件数、占用大小等）
  static Future<Map<String, dynamic>> getStats() =>
      platform.getAppImageCacheStats();
}
