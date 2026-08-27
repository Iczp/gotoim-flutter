import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../network/api_client.dart';
import 'voice_cache_service.dart';

VoiceCacheService createVoiceCacheService(ApiClient client) =>
    _IoVoiceCacheService(client);

class _IoVoiceCacheService implements VoiceCacheService {
  _IoVoiceCacheService(this._client);
  final ApiClient _client;

  @override
  Future<String?> resolve({
    required String cacheKey,
    required String url,
    void Function(int received, int total)? onProgress,
  }) async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory('${root.path}${Platform.pathSeparator}voice');
    await directory.create(recursive: true);
    final safeKey = cacheKey.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final suffix = Uri.tryParse(url)?.pathSegments.last.split('.').last;
    final extension =
        suffix != null && suffix.length <= 5 ? '.$suffix' : '.m4a';
    final target = File(
      '${directory.path}${Platform.pathSeparator}$safeKey$extension',
    );
    if (await target.exists() && await target.length() > 0) return target.path;
    final bytes = await _client.getBytes(
      url,
      cancelTag: 'voice-$cacheKey',
      onProgress: onProgress,
    );
    final temporary = File('${target.path}.part');
    await temporary.writeAsBytes(bytes, flush: true);
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
    return target.path;
  }

  @override
  Future<void> cancel(String cacheKey) =>
      _client.cancelByTag('voice-$cacheKey');
}
