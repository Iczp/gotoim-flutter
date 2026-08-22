import 'package:flutter/foundation.dart';

/// Represents a parsed, strongly-typed Deep Link target.
///
/// Use pattern matching on the sealed hierarchy:
/// ```dart
/// switch (target) {
///   case ChatDeepLink(:final sessionId, :final messageId): ...
///   case UserDeepLink(:final userId): ...
///   case GroupDeepLink(:final groupId): ...
///   case GroupInviteDeepLink(:final token): ...
///   case ScanLoginDeepLink(:final qrCode): ...
///   case WorkbenchDeepLink(:final appId): ...
///   case OAuthCallbackDeepLink(:final code, :final state): ...
/// }
/// ```
@immutable
sealed class DeepLinkTarget {
  const DeepLinkTarget();

  /// Human-readable type name for logging and diagnostics.
  String get targetType;

  /// Whether this target requires an authenticated session before navigation.
  bool get requiresAuth;

  /// Serializes the target fields for diagnostics display and testing.
  Map<String, dynamic> toMap();
}

/// Deep link targeting a chat session or specific chat message.
///
/// URI patterns:
/// - `gotoim-dev://chat/{sessionId}`
/// - `gotoim-dev://chat/{sessionId}/message/{messageId}`
/// - `https://gotoim.com/chat/{sessionId}`
/// - `https://gotoim.com/chat/{sessionId}/message/{messageId}`
class ChatDeepLink extends DeepLinkTarget {
  const ChatDeepLink({
    required this.sessionId,
    this.messageId,
  });

  final String sessionId;
  final int? messageId;

  @override
  String get targetType => 'ChatDeepLink';

  @override
  bool get requiresAuth => true;

  @override
  Map<String, dynamic> toMap() => {
        'sessionId': sessionId,
        if (messageId != null) 'messageId': messageId,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatDeepLink &&
          runtimeType == other.runtimeType &&
          sessionId == other.sessionId &&
          messageId == other.messageId;

  @override
  int get hashCode => Object.hash(sessionId, messageId);

  @override
  String toString() =>
      'ChatDeepLink(sessionId: $sessionId, messageId: $messageId)';
}

/// Deep link targeting a user profile card.
///
/// URI patterns:
/// - `gotoim-dev://user/{userId}`
/// - `https://gotoim.com/user/{userId}`
class UserDeepLink extends DeepLinkTarget {
  const UserDeepLink({required this.userId});

  final String userId;

  @override
  String get targetType => 'UserDeepLink';

  @override
  bool get requiresAuth => true;

  @override
  Map<String, dynamic> toMap() => {'userId': userId};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserDeepLink &&
          runtimeType == other.runtimeType &&
          userId == other.userId;

  @override
  int get hashCode => userId.hashCode;

  @override
  String toString() => 'UserDeepLink(userId: $userId)';
}

/// Deep link targeting a group detail / profile.
///
/// URI patterns:
/// - `gotoim-dev://group/{groupId}`
/// - `https://gotoim.com/group/{groupId}`
class GroupDeepLink extends DeepLinkTarget {
  const GroupDeepLink({required this.groupId});

  final String groupId;

  @override
  String get targetType => 'GroupDeepLink';

  @override
  bool get requiresAuth => true;

  @override
  Map<String, dynamic> toMap() => {'groupId': groupId};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupDeepLink &&
          runtimeType == other.runtimeType &&
          groupId == other.groupId;

  @override
  int get hashCode => groupId.hashCode;

  @override
  String toString() => 'GroupDeepLink(groupId: $groupId)';
}

/// Deep link targeting a group invitation confirmation page.
///
/// Note: Deep Link opens a confirmation page, NEVER auto-joins.
///
/// URI patterns:
/// - `gotoim-dev://invite/group/{token}`
/// - `https://gotoim.com/invite/group/{token}`
class GroupInviteDeepLink extends DeepLinkTarget {
  const GroupInviteDeepLink({required this.token});

  final String token;

  @override
  String get targetType => 'GroupInviteDeepLink';

  @override
  bool get requiresAuth => true;

  @override
  Map<String, dynamic> toMap() => {'token': token};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupInviteDeepLink &&
          runtimeType == other.runtimeType &&
          token == other.token;

  @override
  int get hashCode => token.hashCode;

  @override
  String toString() => 'GroupInviteDeepLink(token: $token)';
}

/// Deep link targeting scan login verification.
///
/// URI patterns:
/// - `gotoim-dev://scan-login/{qrCode}`
/// - `gotoim-dev://scan-login?code={qrCode}`
/// - `https://gotoim.com/scan-login/{qrCode}`
class ScanLoginDeepLink extends DeepLinkTarget {
  const ScanLoginDeepLink({required this.qrCode});

  final String qrCode;

  @override
  String get targetType => 'ScanLoginDeepLink';

  @override
  bool get requiresAuth => false;

  @override
  Map<String, dynamic> toMap() => {'qrCode': qrCode};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScanLoginDeepLink &&
          runtimeType == other.runtimeType &&
          qrCode == other.qrCode;

  @override
  int get hashCode => qrCode.hashCode;

  @override
  String toString() => 'ScanLoginDeepLink(qrCode: $qrCode)';
}

/// Deep link targeting a workbench mini-app or tool.
///
/// URI patterns:
/// - `gotoim-dev://workbench/{appId}`
/// - `https://gotoim.com/workbench/{appId}`
class WorkbenchDeepLink extends DeepLinkTarget {
  const WorkbenchDeepLink({required this.appId});

  final String appId;

  @override
  String get targetType => 'WorkbenchDeepLink';

  @override
  bool get requiresAuth => true;

  @override
  Map<String, dynamic> toMap() => {'appId': appId};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkbenchDeepLink &&
          runtimeType == other.runtimeType &&
          appId == other.appId;

  @override
  int get hashCode => appId.hashCode;

  @override
  String toString() => 'WorkbenchDeepLink(appId: $appId)';
}

/// Deep link targeting an OAuth callback.
///
/// Sensitive credentials (access_token, refresh_token, password) are strictly forbidden in URL.
///
/// URI patterns:
/// - `gotoim-dev://oauth/callback?code={code}&state={state}`
/// - `https://gotoim.com/oauth/callback?code={code}&state={state}`
class OAuthCallbackDeepLink extends DeepLinkTarget {
  const OAuthCallbackDeepLink({
    required this.code,
    this.state,
  });

  final String code;
  final String? state;

  @override
  String get targetType => 'OAuthCallbackDeepLink';

  @override
  bool get requiresAuth => false;

  @override
  Map<String, dynamic> toMap() => {
        'code': code,
        if (state != null) 'state': state,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OAuthCallbackDeepLink &&
          runtimeType == other.runtimeType &&
          code == other.code &&
          state == other.state;

  @override
  int get hashCode => Object.hash(code, state);

  @override
  String toString() => 'OAuthCallbackDeepLink(code: $code, state: $state)';
}
