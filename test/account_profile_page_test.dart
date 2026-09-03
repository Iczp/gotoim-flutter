import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:gotoim_flutter/core/device/client_device_context.dart';
import 'package:gotoim_flutter/features/account/presentation/account_profile_page.dart';
import 'package:gotoim_flutter/features/auth/application/auth_controller.dart';
import 'package:gotoim_flutter/features/auth/domain/auth_repository.dart';
import 'package:gotoim_flutter/features/auth/domain/auth_session.dart';
import 'package:gotoim_flutter/core/realtime/signalr_gateway.dart';

class FakeAuthRepository implements AuthRepository {
  @override
  Future<bool> restoreSession() async => true;
  @override
  Future<void> login({required String username, required String password}) async {}
  @override
  Future<void> loginWithScanToken(String scanToken) async {}
  @override
  Future<String> getClientCredentialsAccessToken() async => 'fake-token';
  @override
  Future<void> logout() async {}
  @override
  Future<AuthSession> refreshSession() async => const AuthSession(
        accessToken: 'new-token',
        refreshToken: 'new-refresh',
        expiresIn: Duration(hours: 1),
      );
  @override
  Future<Map<String, dynamic>> getUserInfo() async => {
        'preferred_username': 'test_admin',
        'name': '系统管理员',
        'email': 'admin@gotoim.com',
        'phone_number': '13800138000',
        'role': ['Administrator', 'Auditor'],
      };
  @override
  Future<Map<String, dynamic>> introspect(RevocationTokenType tokenType) async => {};
  @override
  Future<void> revoke(RevocationTokenType tokenType) async {}
}

class FakeSignalRGateway implements SignalRGateway {
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() => dotenv.loadFromString(envString: 'APP_NAME=Test'));

  testWidgets('AccountProfilePage renders profile details, roles, and device info', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fakeRepo = FakeAuthRepository();
    final fakeSignalR = FakeSignalRGateway();
    final authController = AuthController(fakeRepo, fakeSignalR);
    await authController.fetchUserInfo();

    const fakeDevice = ClientDeviceContext(
      appId: 'test.gotoim.app',
      appName: 'GotoIM',
      appVersion: '1.0.0',
      deviceId: 'device-1234567890abcdef',
      deviceType: 'Desktop',
      platform: 'Windows',
      brand: 'TestBrand',
      model: 'TestModel',
      browser: '',
      pushClientId: '',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appEnvironmentProvider.overrideWithValue(
            AppEnvironment.fromDotEnv(AppFlavor.development),
          ),
          authControllerProvider.overrideWith((ref) => authController),
          clientDeviceContextProvider.overrideWithValue(fakeDevice),
        ],
        child: const MaterialApp(
          home: AccountProfilePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Title
    expect(find.text('账号'), findsWidgets);

    // Verify basic info
    expect(find.text('test_admin'), findsOneWidget);
    expect(find.text('系统管理员'), findsOneWidget);
    expect(find.text('admin@gotoim.com'), findsOneWidget);
    expect(find.text('13800138000'), findsOneWidget);

    // Verify roles
    expect(find.text('Administrator'), findsOneWidget);
    expect(find.text('Auditor'), findsOneWidget);

    // Verify storage, security, device, token refresh, and logout
    expect(find.text('本地缓存'), findsOneWidget);
    expect(find.text('登录日志'), findsOneWidget);
    expect(find.text('TestBrand'), findsOneWidget);
    expect(find.text('TestModel'), findsOneWidget);
    expect(find.text('刷新Token'), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);
  });
}
