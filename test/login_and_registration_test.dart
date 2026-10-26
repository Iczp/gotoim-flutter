import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
  Future<void> login({
    required String username,
    required String password,
  }) async {
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
  Future<Map<String, dynamic>> introspect(
    RevocationTokenType tokenType,
  ) async => {};

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
    'Windows login initializes with a mouse present and survives route removal',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const channel = MethodChannel('gotoim/window');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1180, 15));
      final auth = AuthController(_FakeAuthRepository(), _FakeSignalRGateway());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith((ref) => auth),
            privacyServiceProvider.overrideWith((ref) => _FakePrivacyService()),
          ],
          child: const MaterialApp(home: LoginPage()),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
      await mouse.moveTo(tester.getCenter(find.byTooltip('切换浅色/深色主题')));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await mouse.moveTo(const Offset(20, 20));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      await mouse.removePointer();
      debugDefaultTargetPlatformOverride = null;
    },
  );

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
          child: const MaterialApp(home: LoginPage()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Verify initial Login mode elements
      expect(find.text('Goto IM'), findsOneWidget);
      expect(find.text('跨平台统一即时通讯客户端'), findsOneWidget);
      expect(find.text('登 录'), findsOneWidget);
      expect(find.text('没有账号？立即注册'), findsOneWidget);
      expect(find.text('扫码登录'), findsOneWidget);

      // Exercise the same tooltip State across password/label rebuilds.
      for (var i = 0; i < 3; i++) {
        await tester.longPress(find.byTooltip('显示密码'));
        await tester.pump(const Duration(milliseconds: 600));
        await tester.tap(find.byTooltip('显示密码'));
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(find.byTooltip('隐藏密码'));
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);
      }

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer();
      for (var i = 0; i < 3; i++) {
        await mouse.moveTo(tester.getCenter(find.byTooltip('显示密码')));
        await tester.pump(const Duration(seconds: 1));
        await mouse.down(tester.getCenter(find.byTooltip('显示密码')));
        await mouse.up();
        await tester.pump(const Duration(milliseconds: 300));
        await mouse.moveTo(tester.getCenter(find.byTooltip('切换浅色/深色主题')));
        await tester.pump(const Duration(seconds: 1));
        await mouse.down(tester.getCenter(find.byTooltip('切换浅色/深色主题')));
        await mouse.up();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byTooltip('隐藏密码'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
      }
      await mouse.removePointer();
      await tester.pump(const Duration(seconds: 1));

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
