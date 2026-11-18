import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/application_providers.dart';
import '../../../core/network/api_client.dart';
import 'models/qr_code_models.dart';

final qrCodeApiProvider = Provider<QrCodeApi>((ref) {
  final client = ref.watch(apiClientProvider);
  return QrCodeApi(client);
});

/// 通用二维码与扫码识别 API
class QrCodeApi {
  QrCodeApi(this._client);

  final ApiClient _client;

  Future<QrCodeDetailModel> generate({
    int? ownerId,
    int? scene,
    int? inviterId,
    bool? isPermanent,
    int? expireDays,
    bool forceReset = false,
    String? title,
    int? maxUseCount,
    String? payloadJson,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/api/chat/qr-code/generate',
      data: <String, dynamic>{
        if (ownerId != null) 'ownerId': ownerId,
        if (scene != null) 'scene': scene,
        if (inviterId != null) 'inviterId': inviterId,
        if (isPermanent != null) 'isPermanent': isPermanent,
        if (expireDays != null) 'expireDays': expireDays,
        'forceReset': forceReset,
        if (title != null) 'title': title,
        if (maxUseCount != null) 'maxUseCount': maxUseCount,
        if (payloadJson != null) 'payloadJson': payloadJson,
      },
    );
    return QrCodeDetailModel.fromJson(json);
  }

  Future<QrCodeDetailModel> reset({
    int? ownerId,
    int? scene,
    int? inviterId,
    bool? isPermanent,
    int? expireDays,
    String? title,
    int? maxUseCount,
    String? payloadJson,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/api/chat/qr-code/reset',
      data: <String, dynamic>{
        if (ownerId != null) 'ownerId': ownerId,
        if (scene != null) 'scene': scene,
        if (inviterId != null) 'inviterId': inviterId,
        if (isPermanent != null) 'isPermanent': isPermanent,
        if (expireDays != null) 'expireDays': expireDays,
        'forceReset': true,
        if (title != null) 'title': title,
        if (maxUseCount != null) 'maxUseCount': maxUseCount,
        if (payloadJson != null) 'payloadJson': payloadJson,
      },
    );
    return QrCodeDetailModel.fromJson(json);
  }

  Future<QrCodeScanDataModel> getByCode(
    String code, {
    int? currentChatObjectId,
  }) async {
    final json = await _client.get<Map<String, dynamic>>(
      '/api/chat/qr-code/by-code',
      query: <String, Object?>{
        'code': code,
        if (currentChatObjectId != null)
          'currentChatObjectId': currentChatObjectId,
      },
    );
    return QrCodeScanDataModel.fromJson(json);
  }

  Future<QrCodeScanDataModel?> resolve(
    String content, {
    int? currentChatObjectId,
  }) async {
    final json = await _client.get<Map<String, dynamic>?>(
      '/api/chat/qr-code/resolve',
      query: <String, Object?>{
        'content': content,
        if (currentChatObjectId != null)
          'currentChatObjectId': currentChatObjectId,
      },
    );
    if (json == null || json.isEmpty) return null;
    return QrCodeScanDataModel.fromJson(json);
  }

  Future<QrCodeApplyOutputModel> apply({
    required String code,
    int? applicantChatObjectId,
    String? requestMessage,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/api/chat/qr-code/apply',
      data: <String, dynamic>{
        'code': code,
        if (applicantChatObjectId != null)
          'applicantChatObjectId': applicantChatObjectId,
        if (requestMessage != null && requestMessage.isNotEmpty)
          'requestMessage': requestMessage,
      },
    );
    return QrCodeApplyOutputModel.fromJson(json);
  }

  Future<void> disable(String id) async {
    await _client.post<Object?>(
      '/api/chat/qr-code/$id/disable',
    );
  }

  Future<ScanCodeResultModel> scanCode({
    required String type,
    required String content,
    int? currentChatObjectId,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/api/chat/scan-code/scan',
      query: <String, Object?>{
        'type': type,
        'content': content,
        if (currentChatObjectId != null)
          'currentChatObjectId': currentChatObjectId,
      },
    );
    return ScanCodeResultModel.fromJson(json);
  }
}
