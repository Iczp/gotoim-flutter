import 'package:dio/dio.dart';
import '../network/token_storage.dart';
import 'statistic_device.dart';
import 'statistic_event.dart';

/// 上传结果
class StatisticUploadResult {
  const StatisticUploadResult({
    required this.isSuccess,
    this.receivedCount = 0,
    this.successCount = 0,
    this.duplicateCount = 0,
    this.errorMessage,
    this.statusCode,
  });

  final bool isSuccess;
  final int receivedCount;
  final int successCount;
  final int duplicateCount;
  final String? errorMessage;
  final int? statusCode;

  @override
  String toString() {
    return 'StatisticUploadResult(success: $isSuccess, received: $receivedCount, new: $successCount, dup: $duplicateCount, error: $errorMessage)';
  }
}

/// 统计 HTTP API 接口
abstract class StatisticApi {
  Future<StatisticUploadResult> uploadEvents({
    required StatisticDeviceInfo device,
    required List<StatisticEvent> events,
  });
}

/// 基于 Dio 的统计 API 实现
class DioStatisticApi implements StatisticApi {
  DioStatisticApi({
    required String baseUrl,
    Dio? dio,
    TokenStorage? tokenStorage,
  })  : _baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 15),
                sendTimeout: const Duration(seconds: 15),
                headers: const <String, String>{
                  'Accept': 'application/json',
                  'Content-Type': 'application/json',
                },
              ),
            ),
        _tokenStorage = tokenStorage;

  final String _baseUrl;
  final Dio _dio;
  final TokenStorage? _tokenStorage;

  @override
  Future<StatisticUploadResult> uploadEvents({
    required StatisticDeviceInfo device,
    required List<StatisticEvent> events,
  }) async {
    if (events.isEmpty) {
      return const StatisticUploadResult(isSuccess: true);
    }

    final url = '$_baseUrl/api/app-statistic/events';

    // 尝试携带当前 AccessToken
    String? token;
    try {
      token = await _tokenStorage?.readAccessToken();
    } catch (_) {}

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };

    final payload = <String, dynamic>{
      'device': device.toApiDto(),
      'events': events
          .map(
            (e) => e.toApiDto(
              fallbackPlatform: device.platform,
              fallbackAppVersion: device.appVersion,
              fallbackOsVersion: device.osVersion,
              fallbackChannel: device.channel,
            ),
          )
          .toList(growable: false),
    };

    try {
      final response = await _dio.post<dynamic>(
        url,
        data: payload,
        options: Options(headers: headers),
      );

      final statusCode = response.statusCode ?? 200;
      if (statusCode >= 200 && statusCode < 300) {
        final data = response.data;
        if (data is Map) {
          return StatisticUploadResult(
            isSuccess: true,
            receivedCount: (data['receivedCount'] as num?)?.toInt() ?? events.length,
            successCount: (data['successCount'] as num?)?.toInt() ?? events.length,
            duplicateCount: (data['duplicateCount'] as num?)?.toInt() ?? 0,
            statusCode: statusCode,
          );
        }
        return StatisticUploadResult(
          isSuccess: true,
          receivedCount: events.length,
          successCount: events.length,
          statusCode: statusCode,
        );
      }

      return StatisticUploadResult(
        isSuccess: false,
        statusCode: statusCode,
        errorMessage: 'HTTP $statusCode: ${response.statusMessage}',
      );
    } on DioException catch (dioErr) {
      String? detailMessage;
      final resData = dioErr.response?.data;
      if (resData is Map) {
        final err = resData['error'];
        if (err is Map) {
          detailMessage = err['details']?.toString() ?? err['message']?.toString();
        } else if (resData['message'] != null) {
          detailMessage = resData['message']?.toString();
        }
      }
      return StatisticUploadResult(
        isSuccess: false,
        statusCode: dioErr.response?.statusCode,
        errorMessage: detailMessage ?? dioErr.message ?? dioErr.error?.toString(),
      );
    } catch (e) {
      return StatisticUploadResult(
        isSuccess: false,
        errorMessage: e.toString(),
      );
    }
  }
}
