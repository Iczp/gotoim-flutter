import 'package:flutter/foundation.dart';

/// ABP vNext Current User DTO (`Volo.Abp.AspNetCore.Mvc.ApplicationConfigurations.CurrentUserDto`).
///
/// Ref: `docs/api/swagger-v1-2026-08-27.json`
@immutable
class AbpCurrentUser {
  const AbpCurrentUser({
    this.isAuthenticated = false,
    this.id,
    this.tenantId,
    this.impersonatorUserId,
    this.impersonatorTenantId,
    this.impersonatorUserName,
    this.impersonatorTenantName,
    this.userName,
    this.name,
    this.surName,
    this.email,
    this.emailVerified = false,
    this.phoneNumber,
    this.phoneNumberVerified = false,
    this.roles = const [],
    this.sessionId,
  });

  final bool isAuthenticated;
  final String? id;
  final String? tenantId;
  final String? impersonatorUserId;
  final String? impersonatorTenantId;
  final String? impersonatorUserName;
  final String? impersonatorTenantName;
  final String? userName;
  final String? name;
  final String? surName;
  final String? email;
  final bool emailVerified;
  final String? phoneNumber;
  final bool phoneNumberVerified;
  final List<String> roles;
  final String? sessionId;

  /// 显示名称，依次优先尝试：姓名(name) > 用户名(userName) > 手机号 > 邮箱 > 未命名用户。
  String get displayName {
    final trimmedName = name?.trim();
    if (trimmedName != null && trimmedName.isNotEmpty) return trimmedName;
    final trimmedUserName = userName?.trim();
    if (trimmedUserName != null && trimmedUserName.isNotEmpty) {
      return trimmedUserName;
    }
    final trimmedPhone = phoneNumber?.trim();
    if (trimmedPhone != null && trimmedPhone.isNotEmpty) return trimmedPhone;
    final trimmedEmail = email?.trim();
    if (trimmedEmail != null && trimmedEmail.isNotEmpty) return trimmedEmail;
    return '未命名用户';
  }

  /// 全名（姓 + 名 或 名 + 姓）
  String get fullName {
    final s = surName?.trim() ?? '';
    final n = name?.trim() ?? '';
    if (s.isEmpty && n.isEmpty) return displayName;
    if (s.isEmpty) return n;
    if (n.isEmpty) return s;
    return '$s $n'.trim();
  }

  factory AbpCurrentUser.fromJson(Map<String, dynamic> json) {
    return AbpCurrentUser(
      isAuthenticated: json['isAuthenticated'] == true,
      id: json['id']?.toString(),
      tenantId: json['tenantId']?.toString(),
      impersonatorUserId: json['impersonatorUserId']?.toString(),
      impersonatorTenantId: json['impersonatorTenantId']?.toString(),
      impersonatorUserName: json['impersonatorUserName']?.toString(),
      impersonatorTenantName: json['impersonatorTenantName']?.toString(),
      userName: json['userName']?.toString(),
      name: json['name']?.toString(),
      surName: json['surName']?.toString(),
      email: json['email']?.toString(),
      emailVerified: json['emailVerified'] == true,
      phoneNumber: json['phoneNumber']?.toString(),
      phoneNumberVerified: json['phoneNumberVerified'] == true,
      roles:
          (json['roles'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList(growable: false) ??
          const [],
      sessionId: json['sessionId']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'isAuthenticated': isAuthenticated,
      'id': id,
      'tenantId': tenantId,
      'impersonatorUserId': impersonatorUserId,
      'impersonatorTenantId': impersonatorTenantId,
      'impersonatorUserName': impersonatorUserName,
      'impersonatorTenantName': impersonatorTenantName,
      'userName': userName,
      'name': name,
      'surName': surName,
      'email': email,
      'emailVerified': emailVerified,
      'phoneNumber': phoneNumber,
      'phoneNumberVerified': phoneNumberVerified,
      'roles': roles,
      'sessionId': sessionId,
    };
  }

  AbpCurrentUser copyWith({
    bool? isAuthenticated,
    String? id,
    String? tenantId,
    String? impersonatorUserId,
    String? impersonatorTenantId,
    String? impersonatorUserName,
    String? impersonatorTenantName,
    String? userName,
    String? name,
    String? surName,
    String? email,
    bool? emailVerified,
    String? phoneNumber,
    bool? phoneNumberVerified,
    List<String>? roles,
    String? sessionId,
  }) {
    return AbpCurrentUser(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      impersonatorUserId: impersonatorUserId ?? this.impersonatorUserId,
      impersonatorTenantId: impersonatorTenantId ?? this.impersonatorTenantId,
      impersonatorUserName: impersonatorUserName ?? this.impersonatorUserName,
      impersonatorTenantName:
          impersonatorTenantName ?? this.impersonatorTenantName,
      userName: userName ?? this.userName,
      name: name ?? this.name,
      surName: surName ?? this.surName,
      email: email ?? this.email,
      emailVerified: emailVerified ?? this.emailVerified,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      phoneNumberVerified: phoneNumberVerified ?? this.phoneNumberVerified,
      roles: roles ?? this.roles,
      sessionId: sessionId ?? this.sessionId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AbpCurrentUser &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          userName == other.userName &&
          isAuthenticated == other.isAuthenticated &&
          tenantId == other.tenantId &&
          name == other.name &&
          surName == other.surName &&
          email == other.email &&
          phoneNumber == other.phoneNumber;

  @override
  int get hashCode => Object.hash(
    id,
    userName,
    isAuthenticated,
    tenantId,
    name,
    surName,
    email,
    phoneNumber,
  );
}
