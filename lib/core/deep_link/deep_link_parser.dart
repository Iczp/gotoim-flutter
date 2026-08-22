import 'package:flutter/foundation.dart';

import 'deep_link_target.dart';

/// Status of deep link parsing.
enum DeepLinkParseStatus {
  /// URI matched a known pattern and was parsed into a valid [DeepLinkTarget].
  success,

  /// URI domain or scheme is not recognized, or target action is unsupported.
  unsupported,

  /// URI matched a recognized scheme/action but had invalid or missing arguments.
  invalid,
}

/// Result of parsing a Deep Link URI.
@immutable
class DeepLinkParseResult {
  const DeepLinkParseResult._({
    required this.status,
    required this.rawUri,
    this.normalizedSegments = const [],
    this.target,
    this.reason,
  });

  /// Successfully parsed a [DeepLinkTarget].
  factory DeepLinkParseResult.success({
    required Uri rawUri,
    required List<String> normalizedSegments,
    required DeepLinkTarget target,
  }) {
    return DeepLinkParseResult._(
      status: DeepLinkParseStatus.success,
      rawUri: rawUri,
      normalizedSegments: List.unmodifiable(normalizedSegments),
      target: target,
    );
  }

  /// Scheme, host, or action is not supported by GotoIM.
  factory DeepLinkParseResult.unsupported({
    required Uri rawUri,
    required String reason,
    List<String> normalizedSegments = const [],
  }) {
    return DeepLinkParseResult._(
      status: DeepLinkParseStatus.unsupported,
      rawUri: rawUri,
      normalizedSegments: List.unmodifiable(normalizedSegments),
      reason: reason,
    );
  }

  /// Recognized action, but parameters were invalid or missing.
  factory DeepLinkParseResult.invalid({
    required Uri rawUri,
    required String reason,
    List<String> normalizedSegments = const [],
  }) {
    return DeepLinkParseResult._(
      status: DeepLinkParseStatus.invalid,
      rawUri: rawUri,
      normalizedSegments: List.unmodifiable(normalizedSegments),
      reason: reason,
    );
  }

  final DeepLinkParseStatus status;
  final Uri rawUri;
  final List<String> normalizedSegments;
  final DeepLinkTarget? target;
  final String? reason;

  bool get isSuccess => status == DeepLinkParseStatus.success;
  bool get isUnsupported => status == DeepLinkParseStatus.unsupported;
  bool get isInvalid => status == DeepLinkParseStatus.invalid;

  Map<String, dynamic> toMap() => {
        'status': status.name,
        'rawUri': rawUri.toString(),
        'normalizedSegments': normalizedSegments,
        if (target != null) 'target': target!.toMap(),
        if (target != null) 'targetType': target!.targetType,
        if (reason != null) 'reason': reason,
      };

  @override
  String toString() =>
      'DeepLinkParseResult(status: ${status.name}, target: $target, reason: $reason)';
}

/// Pure Dart parser for GotoIM Deep Link and Universal Link URIs.
///
/// Normalizes custom scheme URIs (e.g. `gotoim-dev://chat/123`) and HTTPS URIs
/// (e.g. `https://gotoim.com/chat/123`) into unified path segments:
/// `['chat', '123']`, then maps them to strongly-typed [DeepLinkTarget]s.
class DeepLinkParser {
  const DeepLinkParser({
    this.allowedCustomSchemes = const ['gotoim-dev', 'gotoim'],
    this.allowedHosts = const ['gotoim.com'],
  });

  /// Allowed custom schemes for development and production.
  final List<String> allowedCustomSchemes;

  /// Allowed domain hosts for HTTP/HTTPS universal links.
  final List<String> allowedHosts;

  /// Normalizes custom scheme and HTTPS URIs into unified segments.
  ///
  /// Examples:
  /// - `gotoim-dev://chat/123/message/456` -> `['chat', '123', 'message', '456']`
  /// - `https://gotoim.com/chat/123/message/456` -> `['chat', '123', 'message', '456']`
  /// - `gotoim-dev:///chat/123` -> `['chat', '123']`
  List<String> normalizeSegments(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    final customSchemes =
        allowedCustomSchemes.map((s) => s.toLowerCase()).toSet();

    if (customSchemes.contains(scheme)) {
      final segments = <String>[];
      if (uri.host.isNotEmpty) {
        segments.add(Uri.decodeComponent(uri.host));
      }
      for (final segment in uri.pathSegments) {
        if (segment.isNotEmpty) {
          segments.add(Uri.decodeComponent(segment));
        }
      }
      return segments;
    }

    if (scheme == 'http' || scheme == 'https') {
      return uri.pathSegments
          .where((s) => s.isNotEmpty)
          .map(Uri.decodeComponent)
          .toList();
    }

    return const [];
  }

  /// Parses a given URI into a [DeepLinkParseResult].
  ///
  /// Guarantees:
  /// - Never throws an uncaught exception on malformed URIs.
  /// - Distinguishes [DeepLinkParseStatus.success], [DeepLinkParseStatus.unsupported],
  ///   and [DeepLinkParseStatus.invalid].
  /// - Enforces strict security constraints against token leakage in URLs.
  DeepLinkParseResult parse(Uri uri) {
    try {
      final rawString = uri.toString();
      if (rawString.length > 4096) {
        return DeepLinkParseResult.invalid(
          rawUri: uri,
          reason: 'URI exceeds maximum allowed length of 4096 characters.',
        );
      }

      final scheme = uri.scheme.toLowerCase();
      final allowedSchemes =
          allowedCustomSchemes.map((s) => s.toLowerCase()).toSet();
      final allowedDomains = allowedHosts.map((h) => h.toLowerCase()).toSet();

      final isCustomScheme = allowedSchemes.contains(scheme);
      final isHttpScheme = scheme == 'http' || scheme == 'https';

      if (!isCustomScheme && !isHttpScheme) {
        return DeepLinkParseResult.unsupported(
          rawUri: uri,
          reason: 'Scheme "$scheme" is not supported.',
        );
      }

      if (isHttpScheme) {
        final host = uri.host.toLowerCase();
        if (!allowedDomains.contains(host)) {
          return DeepLinkParseResult.unsupported(
            rawUri: uri,
            reason: 'Host "$host" is not an allowed GotoIM domain.',
          );
        }
      }

      // Security check: sensitive credentials must not appear in deep link parameters
      final forbiddenKeys = {'access_token', 'refresh_token', 'password', 'secret'};
      for (final key in uri.queryParameters.keys) {
        if (forbiddenKeys.contains(key.toLowerCase())) {
          return DeepLinkParseResult.invalid(
            rawUri: uri,
            reason:
                'Security violation: Sensitive credential "$key" in query parameter is forbidden.',
          );
        }
      }

      final segments = normalizeSegments(uri);
      if (segments.isEmpty) {
        return DeepLinkParseResult.invalid(
          rawUri: uri,
          reason: 'Missing action path in URI.',
          normalizedSegments: segments,
        );
      }

      final action = segments[0].toLowerCase();
      return _parseAction(uri, action, segments);
    } catch (e, stack) {
      debugPrint('DeepLinkParser error: $e\n$stack');
      return DeepLinkParseResult.invalid(
        rawUri: uri,
        reason: 'Malformed URI parsing error: $e',
      );
    }
  }

  DeepLinkParseResult _parseAction(
    Uri uri,
    String action,
    List<String> segments,
  ) {
    switch (action) {
      case 'chat':
        return _parseChat(uri, segments);
      case 'user':
        return _parseUser(uri, segments);
      case 'group':
        return _parseGroup(uri, segments);
      case 'invite':
        return _parseInvite(uri, segments);
      case 'scan-login':
        return _parseScanLogin(uri, segments);
      case 'workbench':
        return _parseWorkbench(uri, segments);
      case 'oauth':
        return _parseOAuth(uri, segments);
      default:
        return DeepLinkParseResult.unsupported(
          rawUri: uri,
          normalizedSegments: segments,
          reason: 'Action "$action" is not supported.',
        );
    }
  }

  DeepLinkParseResult _parseChat(Uri uri, List<String> segments) {
    // Expected:
    // ['chat', '{sessionId}']
    // ['chat', '{sessionId}', 'message', '{messageId}']
    if (segments.length < 2 || segments[1].trim().isEmpty) {
      return DeepLinkParseResult.invalid(
        rawUri: uri,
        normalizedSegments: segments,
        reason: 'Missing sessionId for chat link.',
      );
    }

    final sessionId = segments[1].trim();

    if (segments.length == 2) {
      return DeepLinkParseResult.success(
        rawUri: uri,
        normalizedSegments: segments,
        target: ChatDeepLink(sessionId: sessionId),
      );
    }

    if (segments.length >= 3 && segments[2].toLowerCase() == 'message') {
      if (segments.length < 4 || segments[3].trim().isEmpty) {
        return DeepLinkParseResult.invalid(
          rawUri: uri,
          normalizedSegments: segments,
          reason: 'Missing messageId after "/message".',
        );
      }

      final messageIdStr = segments[3].trim();
      final messageId = int.tryParse(messageIdStr);
      if (messageId == null) {
        return DeepLinkParseResult.invalid(
          rawUri: uri,
          normalizedSegments: segments,
          reason:
              'Invalid messageId "$messageIdStr": must be a valid integer.',
        );
      }

      return DeepLinkParseResult.success(
        rawUri: uri,
        normalizedSegments: segments,
        target: ChatDeepLink(sessionId: sessionId, messageId: messageId),
      );
    }

    return DeepLinkParseResult.invalid(
      rawUri: uri,
      normalizedSegments: segments,
      reason: 'Unrecognized chat link format: /${segments.join('/')}',
    );
  }

  DeepLinkParseResult _parseUser(Uri uri, List<String> segments) {
    // Expected: ['user', '{userId}']
    if (segments.length < 2 || segments[1].trim().isEmpty) {
      return DeepLinkParseResult.invalid(
        rawUri: uri,
        normalizedSegments: segments,
        reason: 'Missing userId for user link.',
      );
    }

    return DeepLinkParseResult.success(
      rawUri: uri,
      normalizedSegments: segments,
      target: UserDeepLink(userId: segments[1].trim()),
    );
  }

  DeepLinkParseResult _parseGroup(Uri uri, List<String> segments) {
    // Expected: ['group', '{groupId}']
    if (segments.length < 2 || segments[1].trim().isEmpty) {
      return DeepLinkParseResult.invalid(
        rawUri: uri,
        normalizedSegments: segments,
        reason: 'Missing groupId for group link.',
      );
    }

    return DeepLinkParseResult.success(
      rawUri: uri,
      normalizedSegments: segments,
      target: GroupDeepLink(groupId: segments[1].trim()),
    );
  }

  DeepLinkParseResult _parseInvite(Uri uri, List<String> segments) {
    // Expected: ['invite', 'group', '{token}']
    if (segments.length < 2 || segments[1].toLowerCase() != 'group') {
      return DeepLinkParseResult.unsupported(
        rawUri: uri,
        normalizedSegments: segments,
        reason: 'Unsupported invite category "${segments.length > 1 ? segments[1] : ''}".',
      );
    }

    if (segments.length < 3 || segments[2].trim().isEmpty) {
      return DeepLinkParseResult.invalid(
        rawUri: uri,
        normalizedSegments: segments,
        reason: 'Missing group invitation token.',
      );
    }

    return DeepLinkParseResult.success(
      rawUri: uri,
      normalizedSegments: segments,
      target: GroupInviteDeepLink(token: segments[2].trim()),
    );
  }

  DeepLinkParseResult _parseScanLogin(Uri uri, List<String> segments) {
    // Expected:
    // ['scan-login', '{qrCode}']
    // OR query param: 'code' / 'qrCode' (e.g. gotoim-dev://scan-login?code=123)
    String? qrCode;
    if (segments.length >= 2 && segments[1].trim().isNotEmpty) {
      qrCode = segments[1].trim();
    } else {
      qrCode = uri.queryParameters['code'] ?? uri.queryParameters['qrCode'];
    }

    if (qrCode == null || qrCode.trim().isEmpty) {
      return DeepLinkParseResult.invalid(
        rawUri: uri,
        normalizedSegments: segments,
        reason: 'Missing qrCode / code for scan-login.',
      );
    }

    return DeepLinkParseResult.success(
      rawUri: uri,
      normalizedSegments: segments,
      target: ScanLoginDeepLink(qrCode: qrCode.trim()),
    );
  }

  DeepLinkParseResult _parseWorkbench(Uri uri, List<String> segments) {
    // Expected: ['workbench', '{appId}']
    if (segments.length < 2 || segments[1].trim().isEmpty) {
      return DeepLinkParseResult.invalid(
        rawUri: uri,
        normalizedSegments: segments,
        reason: 'Missing appId for workbench link.',
      );
    }

    return DeepLinkParseResult.success(
      rawUri: uri,
      normalizedSegments: segments,
      target: WorkbenchDeepLink(appId: segments[1].trim()),
    );
  }

  DeepLinkParseResult _parseOAuth(Uri uri, List<String> segments) {
    // Expected: ['oauth', 'callback'] with query parameter ?code=...
    if (segments.length < 2 || segments[1].toLowerCase() != 'callback') {
      return DeepLinkParseResult.unsupported(
        rawUri: uri,
        normalizedSegments: segments,
        reason: 'Unsupported OAuth endpoint "${segments.length > 1 ? segments[1] : ''}".',
      );
    }

    final code = uri.queryParameters['code'];
    if (code == null || code.trim().isEmpty) {
      return DeepLinkParseResult.invalid(
        rawUri: uri,
        normalizedSegments: segments,
        reason: 'Missing "code" query parameter in OAuth callback.',
      );
    }

    return DeepLinkParseResult.success(
      rawUri: uri,
      normalizedSegments: segments,
      target: OAuthCallbackDeepLink(
        code: code.trim(),
        state: uri.queryParameters['state'],
      ),
    );
  }
}
