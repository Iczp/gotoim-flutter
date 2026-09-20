import 'dart:convert';

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
      final response = await _apiClient.get<dynamic>(
        '/api/chat/app-version/latest',
        query: <String, Object?>{
          'appId': appId,
          'platform': platform,
          'versionCode': versionCode,
          if (deviceId != null && deviceId.isNotEmpty) 'deviceId': deviceId,
        },
      );
      if (response == null) return null;
      if (response is String) {
        final trimmed = response.trim();
        if (trimmed.isEmpty) return null;
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is Map<String, dynamic> && decoded.isNotEmpty) {
            return AppVersionDto.fromJson(decoded);
          }
        } catch (_) {
          return null;
        }
        return null;
      }
      if (response is Map<String, dynamic>) {
        if (response.isEmpty) return null;
        return AppVersionDto.fromJson(response);
      }
      return null;
    } catch (error) {
      debugPrint('[AppUpdateApi] getLatestVersion failed: $error');
      rethrow;
    }
  }
}
