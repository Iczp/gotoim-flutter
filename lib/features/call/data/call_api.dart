import 'package:dio/dio.dart';
import 'call_models.dart';

class CallApi {
  CallApi(this._dio);

  final Dio _dio;

  Future<CallJoinResultDto> invite({
    required String requestId,
    required String sessionId,
    required String senderSessionUnitId,
    required int callMode,
    required int mediaType,
    required List<String> targetSessionUnitIds,
    String? callId,
  }) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '/api/chat/call/invite',
      data: {
        'requestId': requestId,
        'sessionId': sessionId,
        'senderSessionUnitId': senderSessionUnitId,
        'callMode': callMode,
        'mediaType': mediaType,
        'targetSessionUnitIds': targetSessionUnitIds,
        if (callId != null) 'callId': callId,
      },
    );
    return CallJoinResultDto.fromJson(resp.data ?? const {});
  }

  Future<CallJoinResultDto> accept({
    required String requestId,
    required String callId,
    required String sessionUnitId,
    required int inviteRound,
  }) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '/api/chat/call/accept',
      data: {
        'requestId': requestId,
        'callId': callId,
        'sessionUnitId': sessionUnitId,
        'inviteRound': inviteRound,
      },
    );
    return CallJoinResultDto.fromJson(resp.data ?? const {});
  }

  Future<void> reject({
    required String requestId,
    required String callId,
    required String sessionUnitId,
    required int inviteRound,
    String? reason,
  }) async {
    await _dio.post<void>(
      '/api/chat/call/reject',
      data: {
        'requestId': requestId,
        'callId': callId,
        'sessionUnitId': sessionUnitId,
        'inviteRound': inviteRound,
        if (reason != null) 'reason': reason,
      },
    );
  }

  Future<void> hangup({
    required String requestId,
    required String callId,
    required String sessionUnitId,
  }) async {
    await _dio.post<void>(
      '/api/chat/call/hangup',
      data: {
        'requestId': requestId,
        'callId': callId,
        'sessionUnitId': sessionUnitId,
      },
    );
  }

  Future<CallHeartbeatResultDto> heartbeat({
    required String callId,
    required String sessionUnitId,
  }) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '/api/chat/call/heartbeat',
      data: {'callId': callId, 'sessionUnitId': sessionUnitId},
    );
    return CallHeartbeatResultDto.fromJson(resp.data ?? const {});
  }

  Future<CallJoinResultDto> refreshToken({
    required String callId,
    required String sessionUnitId,
  }) async {
    final resp = await _dio.post<Map<String, dynamic>>(
      '/api/chat/call/refresh-token',
      data: {'callId': callId, 'sessionUnitId': sessionUnitId},
    );
    return CallJoinResultDto.fromJson(resp.data ?? const {});
  }
}
