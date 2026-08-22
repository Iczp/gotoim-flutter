import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_navigation.dart';
import 'deep_link_parser.dart';
import 'deep_link_target.dart';

/// Execution status of a deep link action.
enum DeepLinkExecutionStatus {
  /// Successfully navigated or executed.
  success,

  /// Target requires an authenticated user session, saved to pending queue.
  needsAuth,

  /// Target is well-formed and parsed, but the corresponding business page is not yet implemented.
  notImplemented,

  /// Target was invalid, unsupported, or execution encountered an error.
  failed,

  /// Skipped or ignored.
  ignored,
}

/// Result of attempting to execute a deep link.
@immutable
class DeepLinkExecutionResult {
  const DeepLinkExecutionResult({
    required this.status,
    required this.target,
    required this.message,
    this.elapsedMs = 0,
  });

  final DeepLinkExecutionStatus status;
  final DeepLinkTarget? target;
  final String message;
  final int elapsedMs;

  bool get isSuccess => status == DeepLinkExecutionStatus.success;
  bool get isNeedsAuth => status == DeepLinkExecutionStatus.needsAuth;
  bool get isNotImplemented => status == DeepLinkExecutionStatus.notImplemented;

  Map<String, dynamic> toMap() => {
        'status': status.name,
        if (target != null) 'target': target!.toMap(),
        if (target != null) 'targetType': target!.targetType,
        'message': message,
        'elapsedMs': elapsedMs,
      };

  @override
  String toString() =>
      'DeepLinkExecutionResult(status: ${status.name}, message: $message, elapsedMs: ${elapsedMs}ms)';
}

/// Record of a deep link waiting for authentication completion.
class PendingDeepLink {
  const PendingDeepLink({
    required this.target,
    required this.timestamp,
    required this.rawUri,
  });

  final DeepLinkTarget target;
  final DateTime timestamp;
  final Uri rawUri;

  @override
  String toString() =>
      'PendingDeepLink(target: $target, timestamp: $timestamp, rawUri: $rawUri)';
}

/// Dispatches parsed [DeepLinkTarget]s to Flutter routing and business flows.
///
/// Features:
/// - Validates authentication state for protected targets.
/// - Queues pending deep links when unauthenticated to resume after login.
/// - Connects to existing [GoRouter] routes safely without creating mockup dummy pages.
/// - Returns explicit [DeepLinkExecutionStatus.notImplemented] for unbuilt routes.
class DeepLinkHandler {
  DeepLinkHandler({
    this.isAuthenticatedProvider,
    this.navigatorProvider,
  });

  /// Function to check whether current session is authenticated.
  final bool Function()? isAuthenticatedProvider;

  /// Provider for the root NavigatorState (used for GoRouter context lookup).
  final NavigatorState? Function()? navigatorProvider;

  PendingDeepLink? _pendingDeepLink;

  /// Current pending deep link waiting for login.
  PendingDeepLink? get pendingDeepLink => _pendingDeepLink;

  /// Clears any queued pending deep link.
  void clearPendingDeepLink() {
    _pendingDeepLink = null;
  }

  /// Consumes and clears the pending deep link.
  PendingDeepLink? consumePendingDeepLink() {
    final pending = _pendingDeepLink;
    _pendingDeepLink = null;
    return pending;
  }

  /// Handles a parsed [DeepLinkParseResult].
  Future<DeepLinkExecutionResult> handleParseResult(
    DeepLinkParseResult parseResult,
  ) async {
    final stopwatch = Stopwatch()..start();

    if (!parseResult.isSuccess || parseResult.target == null) {
      stopwatch.stop();
      return DeepLinkExecutionResult(
        status: DeepLinkExecutionStatus.failed,
        target: parseResult.target,
        message: parseResult.reason ?? 'Failed to parse deep link URI.',
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
    }

    final result = await handleTarget(
      parseResult.target!,
      rawUri: parseResult.rawUri,
    );
    stopwatch.stop();
    return DeepLinkExecutionResult(
      status: result.status,
      target: result.target,
      message: result.message,
      elapsedMs: stopwatch.elapsedMilliseconds,
    );
  }

  /// Dispatches a strongly-typed [DeepLinkTarget].
  Future<DeepLinkExecutionResult> handleTarget(
    DeepLinkTarget target, {
    Uri? rawUri,
  }) async {
    final stopwatch = Stopwatch()..start();

    // 1. Check authentication if required
    final isAuthenticated = isAuthenticatedProvider?.call() ?? true;
    if (target.requiresAuth && !isAuthenticated) {
      _pendingDeepLink = PendingDeepLink(
        target: target,
        timestamp: DateTime.now(),
        rawUri: rawUri ?? Uri.parse('gotoim-dev://${target.targetType}'),
      );
      stopwatch.stop();
      return DeepLinkExecutionResult(
        status: DeepLinkExecutionStatus.needsAuth,
        target: target,
        message: '用户尚未登录，已存入 PendingDeepLink 待登录完成后继续执行。',
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
    }

    // 2. Dispatch according to target
    try {
      switch (target) {
        case ScanLoginDeepLink(:final qrCode):
          return _handleScanLogin(target, qrCode, stopwatch);

        case WorkbenchDeepLink(:final appId):
          return _handleWorkbench(target, appId, stopwatch);

        case ChatDeepLink(:final sessionId, :final messageId):
          stopwatch.stop();
          return DeepLinkExecutionResult(
            status: DeepLinkExecutionStatus.notImplemented,
            target: target,
            message:
                '解析成功 (ChatDeepLink: sessionId=$sessionId, messageId=$messageId)，'
                '但当前项目尚未实现 /chat 聊天页面路由。',
            elapsedMs: stopwatch.elapsedMilliseconds,
          );

        case UserDeepLink(:final userId):
          stopwatch.stop();
          return DeepLinkExecutionResult(
            status: DeepLinkExecutionStatus.notImplemented,
            target: target,
            message:
                '解析成功 (UserDeepLink: userId=$userId)，'
                '但当前项目尚未实现 /user 用户页面路由。',
            elapsedMs: stopwatch.elapsedMilliseconds,
          );

        case GroupDeepLink(:final groupId):
          stopwatch.stop();
          return DeepLinkExecutionResult(
            status: DeepLinkExecutionStatus.notImplemented,
            target: target,
            message:
                '解析成功 (GroupDeepLink: groupId=$groupId)，'
                '但当前项目尚未实现 /group 群组页面路由。',
            elapsedMs: stopwatch.elapsedMilliseconds,
          );

        case GroupInviteDeepLink(:final token):
          stopwatch.stop();
          return DeepLinkExecutionResult(
            status: DeepLinkExecutionStatus.notImplemented,
            target: target,
            message:
                '解析成功 (GroupInviteDeepLink: token=$token)，'
                '但当前项目尚未实现 /invite/group 邀请确认页面。安全要求：不得自动加群。',
            elapsedMs: stopwatch.elapsedMilliseconds,
          );

        case OAuthCallbackDeepLink(:final code, :final state):
          stopwatch.stop();
          return DeepLinkExecutionResult(
            status: DeepLinkExecutionStatus.notImplemented,
            target: target,
            message:
                '解析成功 (OAuthCallback: code=$code, state=$state)，'
                '但当前项目尚未实现 OAuth Callback 处理页面。',
            elapsedMs: stopwatch.elapsedMilliseconds,
          );
      }
    } catch (e, stack) {
      stopwatch.stop();
      debugPrint('DeepLinkHandler execution error: $e\n$stack');
      return DeepLinkExecutionResult(
        status: DeepLinkExecutionStatus.failed,
        target: target,
        message: '执行路由跳转失败: $e',
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  DeepLinkExecutionResult _handleScanLogin(
    ScanLoginDeepLink target,
    String qrCode,
    Stopwatch stopwatch,
  ) {
    final nav = (navigatorProvider?.call() ?? rootNavigatorKey.currentState);
    if (nav != null && nav.context.mounted) {
      GoRouter.of(nav.context).push('/scan-login?scanText=$qrCode');
      stopwatch.stop();
      return DeepLinkExecutionResult(
        status: DeepLinkExecutionStatus.success,
        target: target,
        message: '成功导航至扫码登录确认页面: /scan-login?scanText=$qrCode',
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
    }

    stopwatch.stop();
    return DeepLinkExecutionResult(
      status: DeepLinkExecutionStatus.failed,
      target: target,
      message: '无法获取 Navigator 上下文进行路由跳转。',
      elapsedMs: stopwatch.elapsedMilliseconds,
    );
  }

  DeepLinkExecutionResult _handleWorkbench(
    WorkbenchDeepLink target,
    String appId,
    Stopwatch stopwatch,
  ) {
    final nav = (navigatorProvider?.call() ?? rootNavigatorKey.currentState);
    if (nav != null && nav.context.mounted) {
      GoRouter.of(nav.context).push('/workbench');
      stopwatch.stop();
      return DeepLinkExecutionResult(
        status: DeepLinkExecutionStatus.success,
        target: target,
        message: '成功导航至工作台页面: /workbench (appId: $appId)',
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
    }

    stopwatch.stop();
    return DeepLinkExecutionResult(
      status: DeepLinkExecutionStatus.failed,
      target: target,
      message: '无法获取 Navigator 上下文进行路由跳转。',
      elapsedMs: stopwatch.elapsedMilliseconds,
    );
  }
}
