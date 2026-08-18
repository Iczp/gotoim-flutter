import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/features/scan_login/application/scan_login_controller.dart';
import 'package:gotoim_flutter/features/scan_login/domain/scan_login_models.dart';
import 'package:gotoim_flutter/features/scan_login/domain/scan_login_repository.dart';

void main() {
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
}

class _FakeScanLoginRepository implements ScanLoginRepository {
  int grantCalls = 0;
  int cancelCalls = 0;

  @override
  Future<void> cancel(String connectionId, {String? reason}) async {
    cancelCalls++;
  }

  @override
  Future<void> grant(String scanText) async {
    grantCalls++;
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
