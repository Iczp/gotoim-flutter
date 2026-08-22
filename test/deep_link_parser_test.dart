import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/deep_link/deep_link_parser.dart';
import 'package:gotoim_flutter/core/deep_link/deep_link_target.dart';

void main() {
  const parser = DeepLinkParser(
    allowedCustomSchemes: ['gotoim-dev', 'gotoim'],
    allowedHosts: ['gotoim.com'],
  );

  group('DeepLinkParser URI Normalization', () {
    test('normalizes custom scheme with host and path', () {
      final uri = Uri.parse('gotoim-dev://chat/123/message/456');
      final segments = parser.normalizeSegments(uri);
      expect(segments, ['chat', '123', 'message', '456']);
    });

    test('normalizes custom scheme with triple slash', () {
      final uri = Uri.parse('gotoim-dev:///chat/123/message/456');
      final segments = parser.normalizeSegments(uri);
      expect(segments, ['chat', '123', 'message', '456']);
    });

    test('normalizes https URI into identical segments as custom scheme', () {
      final customUri = Uri.parse('gotoim-dev://chat/123/message/456');
      final httpsUri = Uri.parse('https://gotoim.com/chat/123/message/456');

      final customSegments = parser.normalizeSegments(customUri);
      final httpsSegments = parser.normalizeSegments(httpsUri);

      expect(customSegments, ['chat', '123', 'message', '456']);
      expect(httpsSegments, ['chat', '123', 'message', '456']);
      expect(customSegments, equals(httpsSegments));
    });
  });

  group('DeepLinkParser Valid URIs', () {
    test('parses chat link without message ID', () {
      final uri = Uri.parse('gotoim-dev://chat/123');
      final result = parser.parse(uri);

      expect(result.status, DeepLinkParseStatus.success);
      expect(result.target, isA<ChatDeepLink>());
      final chat = result.target as ChatDeepLink;
      expect(chat.sessionId, '123');
      expect(chat.messageId, isNull);
    });

    test('parses chat link with numeric message ID', () {
      final uri = Uri.parse('gotoim-dev://chat/123/message/5588575');
      final result = parser.parse(uri);

      expect(result.status, DeepLinkParseStatus.success);
      expect(result.target, isA<ChatDeepLink>());
      final chat = result.target as ChatDeepLink;
      expect(chat.sessionId, '123');
      expect(chat.messageId, 5588575);
    });

    test('parses HTTPS chat link to identical target', () {
      final uri = Uri.parse('https://gotoim.com/chat/123/message/5588575');
      final result = parser.parse(uri);

      expect(result.status, DeepLinkParseStatus.success);
      expect(
        result.target,
        equals(const ChatDeepLink(sessionId: '123', messageId: 5588575)),
      );
    });

    test('parses production scheme gotoim://', () {
      final uri = Uri.parse('gotoim://chat/123');
      final result = parser.parse(uri);

      expect(result.status, DeepLinkParseStatus.success);
      expect(result.target, equals(const ChatDeepLink(sessionId: '123')));
    });

    test('parses user profile link', () {
      final uri = Uri.parse('gotoim-dev://user/10086');
      final result = parser.parse(uri);

      expect(result.status, DeepLinkParseStatus.success);
      expect(result.target, equals(const UserDeepLink(userId: '10086')));
    });

    test('parses group profile link', () {
      final uri = Uri.parse('gotoim-dev://group/888');
      final result = parser.parse(uri);

      expect(result.status, DeepLinkParseStatus.success);
      expect(result.target, equals(const GroupDeepLink(groupId: '888')));
    });

    test('parses group invitation link', () {
      final uri = Uri.parse('gotoim-dev://invite/group/abcdef123');
      final result = parser.parse(uri);

      expect(result.status, DeepLinkParseStatus.success);
      expect(
        result.target,
        equals(const GroupInviteDeepLink(token: 'abcdef123')),
      );
      expect(result.target!.requiresAuth, isTrue);
    });

    test('parses scan-login with path parameter', () {
      final uri = Uri.parse('gotoim-dev://scan-login/abc123');
      final result = parser.parse(uri);

      expect(result.status, DeepLinkParseStatus.success);
      expect(
        result.target,
        equals(const ScanLoginDeepLink(qrCode: 'abc123')),
      );
    });

    test('parses scan-login with query parameter code', () {
      final uri = Uri.parse('gotoim-dev://scan-login?code=qr_token_777');
      final result = parser.parse(uri);

      expect(result.status, DeepLinkParseStatus.success);
      expect(
        result.target,
        equals(const ScanLoginDeepLink(qrCode: 'qr_token_777')),
      );
    });

    test('parses workbench mini-app link', () {
      final uri = Uri.parse('gotoim-dev://workbench/mail');
      final result = parser.parse(uri);

      expect(result.status, DeepLinkParseStatus.success);
      expect(
        result.target,
        equals(const WorkbenchDeepLink(appId: 'mail')),
      );
    });

    test('parses OAuth callback link with code and state', () {
      final uri = Uri.parse('gotoim-dev://oauth/callback?code=123&state=456');
      final result = parser.parse(uri);

      expect(result.status, DeepLinkParseStatus.success);
      expect(
        result.target,
        equals(const OAuthCallbackDeepLink(code: '123', state: '456')),
      );
    });
  });

  group('DeepLinkParser Security & Token Restrictions', () {
    test('rejects URI containing access_token', () {
      final uri = Uri.parse('gotoim-dev://oauth/callback?access_token=secret_token');
      final result = parser.parse(uri);

      expect(result.status, DeepLinkParseStatus.invalid);
      expect(result.reason, contains('Security violation'));
    });

    test('rejects URI containing refresh_token', () {
      final uri = Uri.parse('gotoim-dev://oauth/callback?refresh_token=secret_refresh');
      final result = parser.parse(uri);

      expect(result.status, DeepLinkParseStatus.invalid);
      expect(result.reason, contains('Security violation'));
    });

    test('rejects URI containing password', () {
      final uri = Uri.parse('gotoim-dev://user/100?password=secret_pwd');
      final result = parser.parse(uri);

      expect(result.status, DeepLinkParseStatus.invalid);
      expect(result.reason, contains('Security violation'));
    });
  });

  group('DeepLinkParser Invalid & Unsupported Input', () {
    test('returns invalid when chat link lacks sessionId', () {
      final uri = Uri.parse('gotoim-dev://chat');
      final result = parser.parse(uri);

      expect(result.status, DeepLinkParseStatus.invalid);
      expect(result.reason, contains('Missing sessionId'));
    });

    test('returns invalid when chat link with trailing slash lacks sessionId', () {
      final uri = Uri.parse('gotoim-dev://chat/');
      final result = parser.parse(uri);

      expect(result.status, DeepLinkParseStatus.invalid);
      expect(result.reason, contains('Missing sessionId'));
    });

    test('returns invalid when chat message link lacks messageId', () {
      final uri = Uri.parse('gotoim-dev://chat/123/message');
      final result = parser.parse(uri);

      expect(result.status, DeepLinkParseStatus.invalid);
      expect(result.reason, contains('Missing messageId'));
    });

    test('returns invalid when chat messageId is non-numeric', () {
      final uri = Uri.parse('gotoim-dev://chat/123/message/abc');
      final result = parser.parse(uri);

      expect(result.status, DeepLinkParseStatus.invalid);
      expect(result.reason, contains('must be a valid integer'));
    });

    test('returns unsupported for disallowed external domain', () {
      final uri = Uri.parse('https://evil.com/chat/123');
      final result = parser.parse(uri);

      expect(result.status, DeepLinkParseStatus.unsupported);
      expect(result.reason, contains('not an allowed GotoIM domain'));
    });

    test('returns unsupported for unknown scheme', () {
      final uri = Uri.parse('ftp://gotoim.com/chat/123');
      final result = parser.parse(uri);

      expect(result.status, DeepLinkParseStatus.unsupported);
      expect(result.reason, contains('not supported'));
    });

    test('returns unsupported for unknown action', () {
      final uri = Uri.parse('gotoim-dev://unknown/123');
      final result = parser.parse(uri);

      expect(result.status, DeepLinkParseStatus.unsupported);
      expect(result.reason, contains('not supported'));
    });

    test('handles arbitrary malformed URIs safely without throwing', () {
      final uri = Uri.parse('gotoim-dev://///???&&');
      final result = parser.parse(uri);

      expect(result.status, isNot(DeepLinkParseStatus.success));
      expect(result.reason, isNotNull);
    });
  });
}
