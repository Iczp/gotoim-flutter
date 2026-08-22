import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/deep_link/deep_link_handler.dart';
import 'package:gotoim_flutter/core/deep_link/deep_link_target.dart';

void main() {
  group('DeepLinkHandler Authentication & Pending Links', () {
    test('queues protected link to PendingDeepLink when unauthenticated', () async {
      final handler = DeepLinkHandler(
        isAuthenticatedProvider: () => false,
      );

      const target = ChatDeepLink(sessionId: '123', messageId: 456);
      final result = await handler.handleTarget(target);

      expect(result.status, DeepLinkExecutionStatus.needsAuth);
      expect(handler.pendingDeepLink, isNotNull);
      expect(handler.pendingDeepLink!.target, equals(target));

      final consumed = handler.consumePendingDeepLink();
      expect(consumed?.target, equals(target));
      expect(handler.pendingDeepLink, isNull);
    });

    test('allows non-auth target even when unauthenticated', () async {
      final handler = DeepLinkHandler(
        isAuthenticatedProvider: () => false,
      );

      const target = ScanLoginDeepLink(qrCode: 'qr_test_123');
      final result = await handler.handleTarget(target);

      expect(result.status, isNot(DeepLinkExecutionStatus.needsAuth));
      expect(handler.pendingDeepLink, isNull);
    });
  });

  group('DeepLinkHandler Unimplemented Route Handling', () {
    test('returns notImplemented for ChatDeepLink without crashing', () async {
      final handler = DeepLinkHandler(
        isAuthenticatedProvider: () => true,
      );

      const target = ChatDeepLink(sessionId: '999');
      final result = await handler.handleTarget(target);

      expect(result.status, DeepLinkExecutionStatus.notImplemented);
      expect(result.message, contains('尚未实现 /chat'));
    });

    test('returns notImplemented for UserDeepLink without crashing', () async {
      final handler = DeepLinkHandler(
        isAuthenticatedProvider: () => true,
      );

      const target = UserDeepLink(userId: 'u100');
      final result = await handler.handleTarget(target);

      expect(result.status, DeepLinkExecutionStatus.notImplemented);
      expect(result.message, contains('尚未实现 /user'));
    });

    test('returns notImplemented for GroupDeepLink without crashing', () async {
      final handler = DeepLinkHandler(
        isAuthenticatedProvider: () => true,
      );

      const target = GroupDeepLink(groupId: 'g888');
      final result = await handler.handleTarget(target);

      expect(result.status, DeepLinkExecutionStatus.notImplemented);
      expect(result.message, contains('尚未实现 /group'));
    });

    test('returns notImplemented for GroupInviteDeepLink with security note', () async {
      final handler = DeepLinkHandler(
        isAuthenticatedProvider: () => true,
      );

      const target = GroupInviteDeepLink(token: 'tok_abc');
      final result = await handler.handleTarget(target);

      expect(result.status, DeepLinkExecutionStatus.notImplemented);
      expect(result.message, contains('安全要求：不得自动加群'));
    });

    test('returns notImplemented for OAuthCallbackDeepLink', () async {
      final handler = DeepLinkHandler(
        isAuthenticatedProvider: () => true,
      );

      const target = OAuthCallbackDeepLink(code: 'c123', state: 's456');
      final result = await handler.handleTarget(target);

      expect(result.status, DeepLinkExecutionStatus.notImplemented);
      expect(result.message, contains('OAuth Callback'));
    });
  });
}
