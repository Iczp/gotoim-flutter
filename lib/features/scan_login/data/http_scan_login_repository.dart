import '../../../core/network/api_client.dart';
import '../domain/scan_login_models.dart';
import '../domain/scan_login_repository.dart';

class HttpScanLoginRepository implements ScanLoginRepository {
  HttpScanLoginRepository(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<ScanLoginRequest> inspect(String scanText) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/api/chat/scan-login/scan',
      query: <String, Object?>{'scanText': scanText},
    );
    return ScanLoginRequest.fromJson(response);
  }

  @override
  Future<void> grant(String scanText) => _apiClient.get<Object?>(
        '/api/chat/scan-login/grant',
        query: <String, Object?>{'scanText': scanText},
      );

  @override
  Future<void> reject(String scanText, {String? reason}) =>
      _apiClient.get<Object?>(
        '/api/chat/scan-login/reject',
        query: <String, Object?>{
          'scanText': scanText,
          if (reason != null) 'reason': reason,
        },
      );

  @override
  Future<void> cancel(String connectionId, {String? reason}) =>
      _apiClient.get<Object?>(
        '/api/chat/scan-login/cancel',
        query: <String, Object?>{
          'connectionId': connectionId,
          if (reason != null) 'reason': reason,
        },
      );

  @override
  Future<String?> resolveLoginScan(String content, {String? scanType}) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/api/chat/scan-code/handle',
      data: <String, Object?>{
        'content': content,
        if (scanType != null) 'type': scanType,
      },
    );
    final handlers = response['scanHandlers'];
    final isScanLogin = handlers is List &&
        handlers.any((handler) {
          return handler is Map &&
              handler['action']?.toString() == 'scan-login';
        });
    if (!isScanLogin) return null;
    final resolvedContent = response['content']?.toString();
    return resolvedContent == null || resolvedContent.isEmpty
        ? null
        : resolvedContent;
  }
}
