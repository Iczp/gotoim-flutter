import '../../network/api_client.dart';
import 'voice_cache_service_stub.dart'
    if (dart.library.io) 'voice_cache_service_io.dart'
    as platform;

abstract class VoiceCacheService {
  Future<String?> resolve({
    required String cacheKey,
    required String url,
    void Function(int received, int total)? onProgress,
  });

  Future<void> cancel(String cacheKey);
}

VoiceCacheService createVoiceCacheService(ApiClient client) =>
    platform.createVoiceCacheService(client);
