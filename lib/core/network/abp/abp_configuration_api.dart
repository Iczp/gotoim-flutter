import '../api_client.dart';
import 'abp_application_configuration_dto.dart';

/// ABP vNext Application Configuration API.
///
/// Path: `/api/abp/application-configuration`
/// Ref: `docs/api/swagger-v1-2026-08-27.json`
class AbpConfigurationApi {
  const AbpConfigurationApi(this._apiClient);

  final ApiClient _apiClient;

  /// Fetches application configuration from `/api/abp/application-configuration`.
  ///
  /// By default, [includeLocalizationResources] is set to `false` to optimize
  /// network payload and initialization speed.
  Future<AbpApplicationConfigurationDto> getConfiguration({
    bool includeLocalizationResources = false,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      '/api/abp/application-configuration',
      query:
          includeLocalizationResources
              ? null
              : const <String, Object?>{'IncludeLocalizationResources': false},
    );
    return AbpApplicationConfigurationDto.fromJson(response);
  }
}
