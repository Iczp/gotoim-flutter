import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../../database/unified_database.dart';
import 'abp_application_configuration_dto.dart';
import 'abp_configuration_api.dart';

/// Repository for ABP application configuration with offline-first SQLite cache.
class AbpConfigurationRepository {
  AbpConfigurationRepository({
    required AbpConfigurationApi api,
    required UnifiedDatabase database,
  }) : _api = api,
       _database = database;

  final AbpConfigurationApi _api;
  final UnifiedDatabase _database;

  static const String _cacheKey = 'abp_application_configuration';
  static const String _cacheTimeKey = 'abp_application_configuration_cached_at';

  AbpApplicationConfigurationDto? _cachedInMemory;

  /// In-memory cache getter for fast synchronous access.
  AbpApplicationConfigurationDto? get currentInMemory => _cachedInMemory;

  /// Loads cached configuration from SQLite [UnifiedDatabase].
  Future<AbpApplicationConfigurationDto?> loadCachedConfiguration() async {
    try {
      final jsonString = await _database.readSettingValue(_cacheKey);
      if (jsonString == null || jsonString.isEmpty) return null;
      final decoded = jsonDecode(jsonString);
      if (decoded is! Map) return null;
      final config = AbpApplicationConfigurationDto.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      _cachedInMemory = config;
      return config;
    } catch (e) {
      debugPrint('[AbpConfigRepo] Failed to read cached configuration: $e');
      return null;
    }
  }

  /// Fetches the latest configuration from `/api/abp/application-configuration`
  /// and updates the local SQLite cache.
  Future<AbpApplicationConfigurationDto> fetchAndCacheConfiguration({
    bool includeLocalizationResources = false,
  }) async {
    final config = await _api.getConfiguration(
      includeLocalizationResources: includeLocalizationResources,
    );
    _cachedInMemory = config;
    try {
      final encoded = jsonEncode(config.raw);
      await _database.writeSettingValue(
        id: _cacheKey,
        group: 'abp',
        value: encoded,
      );
      await _database.writeSettingValue(
        id: _cacheTimeKey,
        group: 'abp',
        value: DateTime.now().toIso8601String(),
      );
    } catch (e) {
      debugPrint('[AbpConfigRepo] Failed to persist configuration cache: $e');
    }
    return config;
  }

  /// Reads the timestamp when the configuration was last successfully cached.
  Future<DateTime?> readLastCachedAt() async {
    final str = await _database.readSettingValue(_cacheTimeKey);
    if (str == null || str.isEmpty) return null;
    return DateTime.tryParse(str);
  }

  /// Clears local persisted configuration and in-memory cache.
  Future<void> clearCache() async {
    _cachedInMemory = null;
    try {
      await _database.writeSettingValue(
        id: _cacheKey,
        group: 'abp',
        value: '',
      );
      await _database.writeSettingValue(
        id: _cacheTimeKey,
        group: 'abp',
        value: '',
      );
    } catch (e) {
      debugPrint('[AbpConfigRepo] Failed to clear configuration cache: $e');
    }
  }
}
