import 'package:flutter/foundation.dart';
import 'abp_current_user.dart';

/// ABP vNext Application Configuration DTO
/// (`Volo.Abp.AspNetCore.Mvc.ApplicationConfigurations.ApplicationConfigurationDto`).
///
/// Ref: `docs/api/swagger-v1-2026-08-27.json`
@immutable
class AbpApplicationConfigurationDto {
  const AbpApplicationConfigurationDto({
    required this.currentUser,
    this.raw = const {},
  });

  final AbpCurrentUser currentUser;

  /// Complete raw payload from `/api/abp/application-configuration`
  /// containing auth, setting, features, localization, etc.
  final Map<String, dynamic> raw;

  Map<String, dynamic>? get auth =>
      raw['auth'] is Map ? Map<String, dynamic>.from(raw['auth'] as Map) : null;

  Map<String, dynamic>? get setting =>
      raw['setting'] is Map
          ? Map<String, dynamic>.from(raw['setting'] as Map)
          : null;

  Map<String, dynamic>? get features =>
      raw['features'] is Map
          ? Map<String, dynamic>.from(raw['features'] as Map)
          : null;

  factory AbpApplicationConfigurationDto.fromJson(Map<String, dynamic> json) {
    final userJson = json['currentUser'];
    final currentUser =
        userJson is Map
            ? AbpCurrentUser.fromJson(Map<String, dynamic>.from(userJson))
            : const AbpCurrentUser();
    return AbpApplicationConfigurationDto(
      currentUser: currentUser,
      raw: Map<String, dynamic>.unmodifiable(json),
    );
  }

  Map<String, dynamic> toJson() => raw;
}
