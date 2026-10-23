import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/core/security/url_security_level.dart';
import 'package:gotoim_flutter/core/security/url_security_repository.dart';
import 'package:gotoim_flutter/core/security/url_security_service.dart';
import 'package:gotoim_flutter/core/security/widgets/url_risk_dialog.dart';
import 'package:gotoim_flutter/features/chat/data/models/chat_message.dart';
import 'package:gotoim_flutter/features/chat/presentation/message_menu/chat_message_menu.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UrlSecurityRepository & UrlSecurityService Tests', () {
    late AppEnvironment testEnv;
    late DefaultUrlSecurityRepository repository;
    late UrlSecurityService service;

    setUp(() {
      dotenv.loadFromString(
        envString:
            'API_BASE_URL=https://api.gotoim.com\n'
            'AUTH_BASE_URL=https://auth.gotoim.com\n'
            'DEEP_LINK_ALLOWED_HOSTS=gotoim.com',
      );
      testEnv = AppEnvironment.fromDotEnv(AppFlavor.development);
      repository = DefaultUrlSecurityRepository(environment: testEnv);
      service = UrlSecurityService(repository: repository);
    });

    test('1. Official whitelist domains evaluate to Safe', () async {
      final res1 = await repository.checkUrl('https://gotoim.com/safety');
      expect(res1.level, equals(UrlSecurityLevel.safe));
      expect(res1.isSafe, isTrue);

      final resSub = await repository.checkUrl('https://api.gotoim.com/v1');
      expect(resSub.level, equals(UrlSecurityLevel.safe));

      final resLocal = await repository.checkUrl('http://localhost:8080/test');
      expect(resLocal.level, equals(UrlSecurityLevel.safe));

      expect(service.isTrustedDomain('https://gotoim.com/profile'), isTrue);
    });

    test('2. Blacklisted malicious domains evaluate to Blocked', () async {
      final resScam = await repository.checkUrl('https://scam-test.xyz/claim');
      expect(resScam.level, equals(UrlSecurityLevel.blocked));
      expect(resScam.isBlocked, isTrue);
      expect(resScam.interceptReason, contains('涉嫌虚假投资与电信诈骗'));

      final resPhishing = await repository.checkUrl(
        'https://phishing-test.com/login',
      );
      expect(resPhishing.level, equals(UrlSecurityLevel.blocked));
      expect(resPhishing.isBlocked, isTrue);
    });

    test('3. Unknown third-party external links evaluate to Warning', () async {
      final res = await repository.checkUrl('https://flutter.dev/docs');
      expect(res.level, equals(UrlSecurityLevel.warning));
      expect(res.isWarning, isTrue);
      expect(res.domain, equals('flutter.dev'));
      expect(res.message, contains('离开本应用'));

      expect(service.isTrustedDomain('https://flutter.dev/docs'), isFalse);
    });

    test('4. Dynamic adding and removing whitelist/blacklist', () async {
      expect(
        (await repository.checkUrl('https://my-custom-test.com')).level,
        equals(UrlSecurityLevel.warning),
      );

      // 加白
      repository.addTrustedHost('my-custom-test.com');
      expect(
        (await repository.checkUrl('https://my-custom-test.com')).level,
        equals(UrlSecurityLevel.safe),
      );

      // 加黑
      repository.addBlockedHost('my-custom-test.com', reason: '测试手动封禁');
      expect(
        (await repository.checkUrl('https://my-custom-test.com')).level,
        equals(UrlSecurityLevel.blocked),
      );

      // 移除黑名单并移出白名单
      repository.removeBlockedHost('my-custom-test.com');
      repository.removeTrustedHost('my-custom-test.com');
      expect(
        (await repository.checkUrl('https://my-custom-test.com')).level,
        equals(UrlSecurityLevel.warning),
      );
    });

    test('5. Dangerous download detection and illegal schemes', () async {
      expect(
        service.isDangerousDownload('https://example.com/app.apk'),
        isTrue,
      );
      expect(
        service.isDangerousDownload('https://example.com/installer.exe'),
        isTrue,
      );
      expect(
        service.isDangerousDownload('https://example.com/image.png'),
        isFalse,
      );

      final jsRes = await repository.checkUrl('javascript:alert(1)');
      expect(jsRes.level, equals(UrlSecurityLevel.blocked));
      expect(jsRes.interceptReason, contains('仅允许标准 HTTP/HTTPS 协议'));
    });

    test('offline reports are not falsely acknowledged', () async {
      final success = await repository.report(
        target: 'https://malicious-scam.com/steal',
        reason: '涉嫌网络欺诈',
        description: '诱导填写银行卡密码',
      );
      expect(success, isFalse);
    });
    test('report succeeds only after server acknowledgement', () async {
      final api = _ReportApi();
      final online = DefaultUrlSecurityRepository(
        environment: testEnv,
        apiClient: api,
      );
      expect(
        await online.report(target: 'https://example.com', reason: 'test'),
        isTrue,
      );
      api.fail = true;
      expect(
        await online.report(target: 'https://example.com', reason: 'test'),
        isFalse,
      );
    });
    test('dangerous download suffixes include encoded paths and fragments', () {
      expect(
        service.isDangerousDownload('https://example.com/a.scr#download'),
        isTrue,
      );
      expect(
        service.isDangerousDownload('https://example.com/a%2Eexe?x=1'),
        isTrue,
      );
      expect(service.isDangerousDownload('https://example.com/a.cmd'), isTrue);
      expect(
        service.isDangerousDownload('https://example.com/a.png?name=a.exe'),
        isFalse,
      );
    });
  });

  group('ChatMessageMenuBuilder & Dialogs Tests', () {
    test('ChatMessageMenuBuilder includes report for peer messages', () {
      final myMessage = ChatMessage.fromJson(
        {
          'id': 1,
          'messageType': 0,
          'senderSessionUnitId': 'u1',
          'text': 'hello',
        },
        ownerId: 100,
        sessionUnitId: 'u1',
      );

      final peerMessage = ChatMessage.fromJson(
        {
          'id': 2,
          'messageType': 0,
          'senderSessionUnitId': 'u2',
          'text': 'Check this link: https://scam-test.xyz',
        },
        ownerId: 100,
        sessionUnitId: 'u1',
      );

      const builder = ChatMessageMenuBuilder();

      final myItems = builder.build(
        ChatMessageMenuContext(
          message: myMessage,
          canRecall: false,
          canRetry: false,
          isEarpiece: false,
        ),
      );
      expect(myItems.any((i) => i.id == 'report'), isFalse);

      final peerItems = builder.build(
        ChatMessageMenuContext(
          message: peerMessage,
          canRecall: false,
          canRetry: false,
          isEarpiece: false,
        ),
      );
      expect(peerItems.any((i) => i.id == 'report'), isTrue);
      final reportItem = peerItems.firstWhere((i) => i.id == 'report');
      expect(reportItem.label, equals('投诉'));
    });

    testWidgets('UrlRiskDialog renders domain and anti-fraud warning', (
      tester,
    ) async {
      const checkResult = UrlSecurityCheckResult(
        url: 'https://flutter.dev/docs',
        domain: 'flutter.dev',
        level: UrlSecurityLevel.warning,
        category: UrlRiskCategory.unknownThirdParty,
        message: '你即将离开 GotoIM 访问第三方网站，请注意防范电信网络诈骗。',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: UrlRiskDialog(checkResult: checkResult)),
        ),
      );

      expect(find.text('第三方网页访问提示'), findsOneWidget);
      expect(find.text('flutter.dev'), findsOneWidget);
      expect(find.text('继续访问'), findsOneWidget);
      expect(find.text('外部浏览器打开'), findsOneWidget);
      expect(find.text('投诉此链接'), findsOneWidget);
    });
  });
}

class _ReportApi implements ApiClient {
  bool fail = false;
  @override
  Future<T> post<T>(
    String path, {
    Map<String, Object?>? query,
    Object? data,
    Map<String, String>? headers,
    bool retryOnUnauthorized = true,
  }) async {
    if (fail) throw StateError('offline');
    return <String, dynamic>{'accepted': true} as T;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
