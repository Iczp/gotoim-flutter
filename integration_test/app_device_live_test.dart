import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:gotoim_flutter/app/app_navigation.dart';
import 'package:gotoim_flutter/app/application_providers.dart';
import 'package:gotoim_flutter/app/bootstrap.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:gotoim_flutter/core/device/client_device_context.dart';
import 'package:gotoim_flutter/features/auth/application/auth_controller.dart';

// Opt in on a developer-controlled device. Uses the user's existing session;
// never contains account credentials, resets app data, or creates users.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  const enabled = bool.fromEnvironment('APPDEVICE_LIVE_ACCEPTANCE');

  testWidgets(
    'live native registration, login binding and refresh remain stable',
    (tester) async {
      await bootstrap();
      await tester.pump();
      final container = rootProviderContainer;
      expect(
        container,
        isNotNull,
        reason: 'Application bootstrap must succeed',
      );
      final scope = container!;
      final environment = scope.read(appEnvironmentProvider);
      expect(environment.flavor, AppFlavor.development);
      expect(
        environment.deviceRegistrationApiPath,
        '/api/app-device/public/device-public/register',
      );
      final context = scope.read(clientDeviceContextProvider);
      expect(context.deviceId, isNotEmpty);
      final registration = scope.read(deviceRegistrationApiProvider);
      final first = await registration.register() as Map<String, dynamic>;
      final repeated = await registration.register() as Map<String, dynamic>;
      final device = first['device'] as Map<String, dynamic>;
      expect(device['deviceId'], context.deviceId);
      expect((repeated['device'] as Map<String, dynamic>)['id'], device['id']);
      expect(first['registrationProof'], isNull);
      // This identifier is already returned by the public registration contract.
      // Do not print token/profile/user information in the acceptance transcript.
      // ignore: avoid_print
      print('PASS native registration/retry; record=${device['id']}');

      final auth = scope.read(authControllerProvider);
      final deadline = DateTime.now().add(const Duration(minutes: 2));
      while (auth.status != AuthStatus.authenticated &&
          DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(
        auth.status,
        AuthStatus.authenticated,
        reason: 'Sign in on the phone before continuing the live acceptance',
      );
      final repository = scope.read(authRepositoryProvider);
      expect(await repository.restoreSession(), isTrue);
      await repository.refreshSession();
      final api = scope.read(apiClientProvider);
      final current = await api.get<Map<String, dynamic>>(
        '/api/app-device/public/device-public/current/${Uri.encodeComponent(context.appId)}',
      );
      expect(current['id'], device['id']);
      expect(current['deviceId'], context.deviceId);

      Future<List<dynamic>> ownDevices() async {
        final result = await api.get<Map<String, dynamic>>(
          '/api/app-device/public/device-public/my-devices',
          query: {'appId': context.appId, 'take': 200},
        );
        return result['items'] as List<dynamic>;
      }

      final own = await ownDevices();
      expect(own.where((row) => (row as Map)['id'] == device['id']).length, 1);
      await repository.refreshSession();
      expect(
        (await ownDevices())
            .where((row) => (row as Map)['id'] == device['id'])
            .length,
        1,
      );
      // ignore: avoid_print
      print(
        'PASS authenticated current/my-devices and repeated refresh binding',
      );
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
