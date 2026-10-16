import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:gotoim_flutter/core/device/client_device_context.dart';
import 'package:gotoim_flutter/core/native/device.dart';
import 'package:gotoim_flutter/core/platform/platform_contract.dart';
import 'package:uuid/uuid.dart';

class _FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> data = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return data[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }
}

class _FakeNativeDevice extends NativeDevice {
  _FakeNativeDevice({this.permanentId});

  final String? permanentId;

  @override
  Future<String?> getPermanentDeviceId() async => permanentId;
}

class _FakePlatformFacade implements PlatformFacade {
  const _FakePlatformFacade({required this.kind, this.isWeb = false});

  @override
  final PlatformKind kind;

  @override
  final bool isWeb;

  @override
  bool get supportsMultipleWindows => false;

  @override
  bool get supportsNativeFilePaths => !isWeb;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  dotenv.loadFromString(
    envString:
        'API_BASE_URL=http://localhost:8044\n'
        'AUTH_BASE_URL=http://localhost:8043\n'
        'AUTH_CLIENT_ID=IM_Mobile\n'
        'AUTH_CLIENT_SECRET=secret\n'
        'AUTH_SCOPE=IM\n'
        'AUTH_LOGIN_GRANT_TYPE=password\n'
        'SIGNALR_BASE_URL=http://localhost:8044\n'
        'APP_ID=com.gotoim.client\n'
        'APP_NAME=GotoIM\n'
        'APP_VERSION=1.0.0\n',
  );
  final fakeEnv = AppEnvironment.fromDotEnv(AppFlavor.development);

  group('ClientDeviceContextFactory Persistent Device ID', () {
    test(
      'reuses existing deviceId in secure storage without querying hardware',
      () async {
        final storage = _FakeSecureStorage();
        storage.data['gotoim.device-id.v1'] =
            '11111111-2222-3333-4444-555555555555';

        final factory = ClientDeviceContextFactory(
          storage: storage,
          nativeDevice: _FakeNativeDevice(permanentId: 'hardware-different-id'),
        );

        final deviceId = await factory.resolveDeviceId(
          platformFacade: const _FakePlatformFacade(kind: PlatformKind.android),
        );

        expect(deviceId, '11111111-2222-3333-4444-555555555555');
      },
    );

    test(
      'resolves and normalizes hardware permanent ID from native device',
      () async {
        final storage = _FakeSecureStorage();
        const hardwareDrmUuid = 'abcdef01-2345-6789-abcd-ef0123456789';

        final factory = ClientDeviceContextFactory(
          storage: storage,
          nativeDevice: _FakeNativeDevice(permanentId: hardwareDrmUuid),
        );

        final deviceId = await factory.resolveDeviceId(
          platformFacade: const _FakePlatformFacade(kind: PlatformKind.android),
        );

        expect(deviceId, hardwareDrmUuid);
        expect(storage.data['gotoim.device-id.v1'], hardwareDrmUuid);
      },
    );

    test(
      'simulates app uninstall and reinstall on Android: produces identical deviceId',
      () async {
        final storage = _FakeSecureStorage();
        const rawWidevineDrmId = 'widevine-device-hardware-secret-key-12345';
        final nativeDevice = _FakeNativeDevice(permanentId: rawWidevineDrmId);

        // First install
        final factory1 = ClientDeviceContextFactory(
          storage: storage,
          nativeDevice: nativeDevice,
        );
        final id1 = await factory1.resolveDeviceId(
          platformFacade: const _FakePlatformFacade(kind: PlatformKind.android),
        );

        // Simulate Android uninstallation: Android OS wipes /data/data/<package>/
        storage.data.clear();
        expect(storage.data['gotoim.device-id.v1'], isNull);

        // Second install (reinstalling app on same device)
        final factory2 = ClientDeviceContextFactory(
          storage: storage,
          nativeDevice: nativeDevice,
        );
        final id2 = await factory2.resolveDeviceId(
          platformFacade: const _FakePlatformFacade(kind: PlatformKind.android),
        );

        // Must be completely identical across installs!
        expect(id2, id1);
        expect(id2, isNotEmpty);
        expect(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          ).hasMatch(id2),
          isTrue,
        );
      },
    );

    test(
      'falls back to UUID generator if hardware ID is empty, and writes to storage',
      () async {
        final storage = _FakeSecureStorage();

        final factory = ClientDeviceContextFactory(
          storage: storage,
          nativeDevice: _FakeNativeDevice(permanentId: null),
          uuid: const Uuid(),
        );

        final context = await factory.create(
          environment: fakeEnv,
          platformFacade: const _FakePlatformFacade(kind: PlatformKind.android),
        );

        expect(context.deviceId, isNotEmpty);
        expect(storage.data['gotoim.device-id.v1'], context.deviceId);
        expect(context.appId, fakeEnv.appId);
        expect(context.platform, 'android');
      },
    );

    test('resolves deviceId on web platform and writes to storage', () async {
      final storage = _FakeSecureStorage();

      final factory = ClientDeviceContextFactory(
        storage: storage,
        nativeDevice: _FakeNativeDevice(permanentId: null),
        uuid: const Uuid(),
      );

      final context = await factory.create(
        environment: fakeEnv,
        platformFacade: const _FakePlatformFacade(
          kind: PlatformKind.web,
          isWeb: true,
        ),
      );

      expect(context.deviceId, isNotEmpty);
      expect(context.deviceType, 'web');
      expect(context.platform, 'web');
      expect(storage.data['gotoim.device-id.v1'], context.deviceId);
    });
  });
}
