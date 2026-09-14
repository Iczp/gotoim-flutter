import 'dart:io';

import 'package:file/file.dart' as f;
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

BaseCacheManager getAppImageCacheManager() => AppImageCacheManagerImpl.instance;

Future<String?> getAppImageCachedPath(String url) =>
    AppImageCacheManagerImpl.getCachedPath(url);

Future<void> clearAppImageCache() => AppImageCacheManagerImpl.clearAll();

Future<Map<String, dynamic>> getAppImageCacheStats() =>
    AppImageCacheManagerImpl.getCacheStats();

/// 自定义持久化响应，保障离线状态下即便服务端返回了 no-cache 也至少缓存 30 天
class _PersistentFileServiceResponse implements FileServiceResponse {
  _PersistentFileServiceResponse(this._inner);

  final FileServiceResponse _inner;
  static const Duration _minDuration = Duration(days: 30);

  @override
  int get statusCode => _inner.statusCode;

  @override
  Stream<List<int>> get content => _inner.content;

  @override
  int? get contentLength => _inner.contentLength;

  @override
  DateTime get validTill {
    final now = DateTime.now();
    final candidate = _inner.validTill;
    final minValid = now.add(_minDuration);
    if (candidate.isBefore(minValid)) {
      return minValid;
    }
    return candidate;
  }

  @override
  String? get eTag => _inner.eTag;

  @override
  String get fileExtension => _inner.fileExtension;
}

/// 支持短超时（默认 4 秒）的 HTTP 文件下载器，避免断网时长时间挂起
class _TimeoutHttpFileService extends FileService {
  _TimeoutHttpFileService({
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 4),
  })  : _httpClient = httpClient ?? http.Client(),
        super();

  final http.Client _httpClient;
  final Duration timeout;

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final req = http.Request('GET', Uri.parse(url));
    if (headers != null) {
      req.headers.addAll(headers);
    }
    final streamed = await _httpClient.send(req).timeout(timeout);
    return _PersistentFileServiceResponse(HttpGetResponse(streamed));
  }
}

/// 存放在持久应用数据目录（ApplicationSupportDirectory），避免被系统清理临时目录误删
class _PersistentFileSystem implements FileSystem {
  _PersistentFileSystem(this._key) : _dir = _createDir(_key);

  final String _key;
  final Future<f.Directory> _dir;

  static Future<f.Directory> _createDir(String key) async {
    final base = await getApplicationSupportDirectory();
    final dirPath = p.join(base.path, key);
    const fs = LocalFileSystem();
    final directory = fs.directory(dirPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  @override
  Future<f.File> createFile(String name) async {
    final directory = await _dir;
    if (!await directory.exists()) {
      await _createDir(_key);
    }
    return directory.childFile(name);
  }
}

/// 全局独立配置的图片离线缓存管理器（IO 平台实现）
class AppImageCacheManagerImpl extends CacheManager {
  static const key = 'app_image_cache';

  static final AppImageCacheManagerImpl instance = AppImageCacheManagerImpl._();

  AppImageCacheManagerImpl._()
      : super(
          Config(
            key,
            stalePeriod: const Duration(days: 365),
            maxNrOfCacheObjects: 1000,
            repo: _createRepo(key),
            fileSystem: _PersistentFileSystem(key),
            fileService: _TimeoutHttpFileService(
              timeout: const Duration(seconds: 4),
            ),
          ),
        );

  static CacheInfoRepository _createRepo(String key) {
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      return CacheObjectProvider(databaseName: key);
    }
    return JsonCacheInfoRepository(databaseName: key);
  }

  static Future<String?> getCachedPath(String url) async {
    try {
      final fileInfo = await instance.getFileFromCache(url);
      if (fileInfo != null && await fileInfo.file.exists()) {
        return fileInfo.file.path;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> clearAll() async {
    try {
      await instance.emptyCache();
    } catch (_) {}
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory(p.join(base.path, key));
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> getCacheStats() async {
    try {
      final base = await getApplicationSupportDirectory();
      final dirPath = p.join(base.path, key);
      final dir = Directory(dirPath);
      int count = 0;
      int totalBytes = 0;
      if (await dir.exists()) {
        final entries = dir.listSync(recursive: true);
        for (final entry in entries) {
          if (entry is File) {
            count++;
            totalBytes += entry.lengthSync();
          }
        }
      }
      return <String, dynamic>{
        'directory': dirPath,
        'fileCount': count,
        'totalBytes': totalBytes,
        'platform': Platform.operatingSystem,
      };
    } catch (e) {
      return <String, dynamic>{
        'error': e.toString(),
        'platform': Platform.operatingSystem,
      };
    }
  }
}
