import 'package:flutter/foundation.dart';

import '../../../../core/network/api_client.dart';
import '../models/app_version_dto.dart';

class AppUpdateApi {
  AppUpdateApi(this._apiClient);

  final ApiClient _apiClient;

  Future<AppVersionDto?> getLatestVersion({
    required String appId,
    required String platform,
    required int versionCode,
    String? deviceId,
  }) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        '/api/chat/app-version/latest',
        query: <String, Object?>{
          'appId': appId,
          'platform': platform,
          'versionCode': versionCode,
          if (deviceId != null && deviceId.isNotEmpty) 'deviceId': deviceId,
        },
      );
      if (response.isEmpty) return null;
      return AppVersionDto.fromJson(response);
    } catch (error) {
      debugPrint('[AppUpdateApi] getLatestVersion failed: $error');
      rethrow;
    }
  }
}
