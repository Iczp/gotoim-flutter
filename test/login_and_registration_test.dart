import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:gotoim_flutter/core/compliance/privacy_service.dart';
import 'package:gotoim_flutter/features/auth/application/auth_controller.dart';
import 'package:gotoim_flutter/features/auth/domain/auth_repository.dart';
import 'package:gotoim_flutter/features/auth/domain/auth_session.dart';
import 'package:gotoim_flutter/features/auth/presentation/login_page.dart';
import 'package:gotoim_flutter/core/realtime/signalr_gateway.dart';

class _FakeAuthRepository implements AuthRepository {
  String? registeredUsername;
  String? registeredPassword;
  String? loggedInUsername;
  String? loggedInPassword;

  @override
  Future<bool> restoreSession() async => false;

  @override
  Future<void> login({required String username, required String password}) async {
    loggedInUsername = username;
    loggedInPassword = password;
  }

  @override
  Future<void> register({
    required String username,
    required String password,
    String? emailAddress,
  }) async {
    registeredUsername = username;
    registeredPassword = password;
  }

  @override
  Future<void> loginWithScanToken(String scanToken) async {}

  @override
  Future<String> getClientCredentialsAccessToken() async => 'fake-token';

  @override
  Future<void> logout() async {}

  @override
  Future<AuthSession> refreshSession() async => const AuthSession(
        accessToken: 'token',
        refreshToken: 'refresh',
        expiresIn: Duration(hours: 1),
      );

  @override
  Future<Map<String, dynamic>> getUserInfo() async => {'userName': 'test'};

  @override
  Future<Map<String, dynamic>> introspect(RevocationTokenType tokenType) async => {};

  @override
  Future<void> revoke(RevocationTokenType tokenType) async {}
}

class _FakeSignalRGateway implements SignalRGateway {
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePrivacyService extends ChangeNotifier implements PrivacyService {
  @override
  bool get hasAgreed => true;

  @override
  DateTime? get agreedAt => DateTime.now();

  @override
  bool get isInitialized => true;

  @override
  Future<bool> initialize() async => true;

  @override
  Future<void> saveAgreement() async {}

  @override
  Future<void> resetAgreement() async {}
}

void main() {
  setUpAll(() {
    dotenv.loadFromString(envString: 'APP_NAME=GotoIM');
  });

  testWidgets(
    'LoginPage renders without overflow on standard phone viewport and toggles between login and register',
    (tester) async {
      // Standard phone screen resolution: 390x844 (iPhone 12/13/14)
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      final fakeRepo = _FakeAuthRepository();
      final fakeSignalR = _FakeSignalRGateway();
      final authController = AuthController(fakeRepo, fakeSignalR);
      final fakePrivacy = _FakePrivacyService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith((ref) => authController),
            privacyServiceProvider.overrideWith((ref) => fakePrivacy),
          ],
          child: const MaterialApp(
            home: LoginPage(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Verify initial Login mode elements
      expect(find.text('Goto IM'), findsOneWidget);
      expect(find.text('跨平台统一即时通讯客户端'), findsOneWidget);
      expect(find.text('登 录'), findsOneWidget);
      expect(find.text('没有账号？立即注册'), findsOneWidget);
      expect(find.text('扫码登录'), findsOneWidget);

      // Verify confirm password field is NOT present in login mode
      expect(find.text('确认密码'), findsNothing);

      // Tap "没有账号？立即注册"
      await tester.tap(find.text('没有账号？立即注册'));
      await tester.pump(const Duration(milliseconds: 200));

      // Verify Register mode elements
      expect(find.text('加入 Goto IM'), findsOneWidget);
      expect(find.text('创建即时通讯协同账号'), findsOneWidget);
      expect(find.text('确认密码'), findsOneWidget);
      expect(find.text('注 册'), findsOneWidget);
      expect(find.text('已有账号？返回登录'), findsOneWidget);

      // Tap "已有账号？返回登录"
      await tester.tap(find.text('已有账号？返回登录'));
      await tester.pump(const Duration(milliseconds: 200));

      // Verify switched back to Login mode
      expect(find.text('Goto IM'), findsOneWidget);
      expect(find.text('登 录'), findsOneWidget);
      expect(find.text('确认密码'), findsNothing);
    },
  );
}
