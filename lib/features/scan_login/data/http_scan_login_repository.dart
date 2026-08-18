import '../../../core/network/api_client.dart';
import '../domain/scan_login_models.dart';
import '../domain/scan_login_repository.dart';

class HttpScanLoginRepository implements ScanLoginRepository {
  HttpScanLoginRepository(
    this._apiClient, {
    String scanLoginTemplate = 'gotoim://scan-login?code={code}',
  }) : _scanLoginTemplate = ScanLoginTemplate(scanLoginTemplate);

  final ApiClient _apiClient;
  final ScanLoginTemplate _scanLoginTemplate;

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
        retryOnUnauthorized: false,
      );

  @override
  Future<void> reject(String scanText, {String? reason}) =>
      _apiClient.get<Object?>(
        '/api/chat/scan-login/reject',
        query: <String, Object?>{
          'scanText': scanText,
          if (reason != null) 'reason': reason,
        },
        retryOnUnauthorized: false,
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
      '/api/chat/scan-code/scan',
      query: <String, Object?>{
        'content': content,
        if (scanType != null) 'type': scanType,
      },
      data: <String, Object?>{},
    );
    final handlers = response['scanHandlers'];
    Map? handler;
    if (handlers is List) {
      for (final item in handlers) {
        if (item is Map && item['action']?.toString() == 'scan-login') {
          handler = item;
          break;
        }
      }
    }
    if (handler == null) return null;
    final resolvedContent = response['content']?.toString();
    if (resolvedContent == null || resolvedContent.isEmpty) return null;
    final handlerTemplate = handler['result']?.toString();
    final template = handlerTemplate == null || handlerTemplate.isEmpty
        ? _scanLoginTemplate
        : ScanLoginTemplate(handlerTemplate);
    return template.matches(resolvedContent) ? resolvedContent : null;
  }
}
