import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/features/scan_login/application/scan_login_controller.dart';
import 'package:gotoim_flutter/features/scan_login/domain/scan_login_models.dart';
import 'package:gotoim_flutter/features/scan_login/domain/scan_login_repository.dart';

void main() {
  test('scan-login template only accepts a non-empty login code', () {
    const template = ScanLoginTemplate('gotoim://scan-login?code={code}');

    expect(template.matches('gotoim://scan-login?code=abc-123'), isTrue);
    expect(template.matches('gotoim://scan-login?code='), isFalse);
    expect(template.matches('gotoim://other?code=abc-123'), isFalse);
  });

  test('scan-login response uses top-level client information as fallback', () {
    final request = ScanLoginRequest.fromJson(<String, dynamic>{
      'connectionId': 'connection-1',
      'scanUserId': 'user-1',
      'scanUserName': 'admin',
      'scanClientId': 'IM_Mobile',
      'state': '8451',
      'connectionPool': null,
    });

    expect(request.scanUserName, 'admin');
    expect(request.device.clientId, 'IM_Mobile');
    expect(request.device.appName, isNull);
    expect(request.state, '8451');
  });

  test('only grants login after the request was inspected and approved',
      () async {
    final repository = _FakeScanLoginRepository();
    final controller =
        ScanLoginController(repository, 'gotoim://scan-login?code=1');

    expect(await controller.grant(), isFalse);
    expect(repository.grantCalls, 0);

    await controller.load();
    expect(await controller.grant(), isTrue);
    expect(repository.grantCalls, 1);
    expect(repository.cancelCalls, 0);
  });

  test('closing an unapproved request cancels the backend login challenge',
      () async {
    final repository = _FakeScanLoginRepository();
    final controller =
        ScanLoginController(repository, 'gotoim://scan-login?code=1');

    await controller.load();
    await controller.cancelIfNeeded();

    expect(repository.cancelCalls, 1);
    expect(repository.grantCalls, 0);
  });

  test('does not send a second authorization after the first attempt fails',
      () async {
    final repository = _FakeScanLoginRepository()
      ..grantError = StateError('network interrupted');
    final controller =
        ScanLoginController(repository, 'gotoim://scan-login?code=1');

    await controller.load();
    expect(await controller.grant(), isFalse);
    expect(await controller.grant(), isFalse);
    expect(repository.grantCalls, 1);
    expect(controller.authorizationAttempted, isTrue);
  });
}

class _FakeScanLoginRepository implements ScanLoginRepository {
  int grantCalls = 0;
  int cancelCalls = 0;
  Object? grantError;

  @override
  Future<void> cancel(String connectionId, {String? reason}) async {
    cancelCalls++;
  }

  @override
  Future<void> grant(String scanText) async {
    grantCalls++;
    if (grantError != null) throw grantError!;
  }

  @override
  Future<ScanLoginRequest> inspect(String scanText) async =>
      const ScanLoginRequest(
        connectionId: 'connection-1',
        scanUserId: 'user-1',
        scanUserName: 'User',
        device: LoginDevice(
          appName: 'Goto IM Web',
          deviceInfo: 'Chrome on Windows',
          clientId: 'client-1',
        ),
      );

  @override
  Future<void> reject(String scanText, {String? reason}) async {}

  @override
  Future<String?> resolveLoginScan(String content, {String? scanType}) async =>
      content;
}
