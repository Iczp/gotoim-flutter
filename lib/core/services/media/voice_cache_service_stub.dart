import '../../network/api_client.dart';
import 'voice_cache_service.dart';

VoiceCacheService createVoiceCacheService(ApiClient client) =>
    _WebVoiceCacheService();

class _WebVoiceCacheService implements VoiceCacheService {
  @override
  Future<String?> resolve({
    required String cacheKey,
    required String url,
    void Function(int received, int total)? onProgress,
  }) async => null;

  @override
  Future<void> cancel(String cacheKey) async {}
}
