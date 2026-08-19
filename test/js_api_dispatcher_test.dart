import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/capabilities/client_capability_models.dart';
import 'package:gotoim_flutter/core/capabilities/client_capability_service.dart';
import 'package:gotoim_flutter/core/jsbridge/js_api_dispatcher.dart';
import 'package:gotoim_flutter/core/jsbridge/js_bridge_session.dart';
import 'package:gotoim_flutter/core/notifications/local_notification_contract.dart';
import 'package:gotoim_flutter/core/platform/platform_contract.dart';
import 'package:gotoim_flutter/core/services/file/file_picker_service.dart';
import 'package:gotoim_flutter/core/services/scan/scan_code_service.dart';

void main() {
  late _FakeCapabilities capabilities;
  late JsApiDispatcher dispatcher;

  setUp(() {
    capabilities = _FakeCapabilities();
    dispatcher = JsApiDispatcher(capabilities: capabilities);
  });

  tearDown(() async {
    await dispatcher.dispose();
    await capabilities.dispose();
  });

  test('dispatches Uni-compatible getSystemInfo request', () async {
    final response =
        jsonDecode(
              await dispatcher.handleRaw(
                '{"id":"system-1","action":"getSystemInfo","data":{}}',
              ),
            )
            as Map<String, dynamic>;

    expect(response['id'], 'system-1');
    expect(response['success'], isTrue);
    expect(response['data']['appId'], 'gotoim');
    expect(response['data']['platform'], 'windows');
  });

  test('returns a structured error for an unsupported action', () async {
    final response =
        jsonDecode(
              await dispatcher.handleRaw(
                '{"id":"missing","action":"unknown.action","data":{}}',
              ),
            )
            as Map<String, dynamic>;

    expect(response['success'], isFalse);
    expect(response['error']['code'], 'NOT_SUPPORTED');
  });

  test('forwards subscribed network changes as bridge events', () async {
    final futureEvent = dispatcher.events.first;
    final response =
        jsonDecode(
              await dispatcher.handleRaw(
                '{"id":"watch","action":"onNetworkStatusChange","data":{"subscriptionId":"n-1"}}',
              ),
            )
            as Map<String, dynamic>;
    expect(response['data']['subscriptionId'], 'n-1');

    capabilities.addNetworkStatus(
      ClientNetworkStatus(
        types: const <ClientNetworkType>[ClientNetworkType.wifi],
        observedAt: DateTime.utc(2026, 8, 19),
      ),
    );
    final event = await futureEvent;

    expect(event.name, 'network.statusChange');
    expect(event.data['subscriptionId'], 'n-1');
    expect(
      (event.data['status'] as Map<String, Object>)['isConnected'],
      isTrue,
    );
  });

  test(
    'bridge session writes dispatcher responses to its host transport',
    () async {
      final transport = _FakeTransport();
      final session = JsBridgeSession(
        dispatcher: dispatcher,
        transport: transport,
      );
      session.start();

      await session.handleIncoming(
        '{"id":"device-1","action":"getDeviceInfo","data":{}}',
      );
      await session.dispose();

      final response =
          jsonDecode(transport.messages.single) as Map<String, dynamic>;
      expect(response['id'], 'device-1');
      expect(response['success'], isTrue);
    },
  );
}

class _FakeCapabilities implements ClientCapabilityService {
  final StreamController<ClientNetworkStatus> _networkController =
      StreamController<ClientNetworkStatus>.broadcast();

  @override
  Future<List<SelectedFile>> chooseFile(FilePickerRequest request) async =>
      const <SelectedFile>[];

  @override
  Future<ScanCodeResult?> decodeImage(DecodeImageRequest request) async => null;

  @override
  Future<List<ClientCapabilitySupport>> getCapabilities() async =>
      const <ClientCapabilitySupport>[
        ClientCapabilitySupport(
          name: 'system.getSystemInfo',
          isSupported: true,
          message: 'ok',
        ),
      ];

  @override
  Future<String?> getClipboardData() async => 'clipboard';

  @override
  Future<ClientDeviceInfo> getDeviceInfo() async => const ClientDeviceInfo(
    platform: PlatformKind.windows,
    appScopedDeviceId: 'stable-device',
    deviceType: 'windows',
    brand: 'Test',
    model: 'Model',
    systemName: 'Windows',
    systemVersion: '11',
    isPhysicalDevice: true,
    browser: null,
  );

  @override
  Future<ClientNetworkStatus> getNetworkType() async => ClientNetworkStatus(
    types: const <ClientNetworkType>[ClientNetworkType.wifi],
    observedAt: DateTime.utc(2026, 8, 19),
  );

  @override
  Future<ClientSystemInfo> getSystemInfo() async => const ClientSystemInfo(
    platform: PlatformKind.windows,
    isWeb: false,
    locale: 'zh-CN',
    brightness: 'light',
    devicePixelRatio: 1,
    windowWidth: 1280,
    windowHeight: 720,
    screenWidth: 1280,
    screenHeight: 720,
    safeAreaTop: 0,
    safeAreaRight: 0,
    safeAreaBottom: 0,
    safeAreaLeft: 0,
    appId: 'gotoim',
    appName: 'Goto IM',
    appVersion: '1.0.0',
  );

  @override
  Stream<ClientNetworkStatus> get networkStatusChanges =>
      _networkController.stream;

  @override
  LocalNotificationSupport get notificationSupport =>
      const LocalNotificationSupport(
        platform: PlatformKind.windows,
        isSupported: true,
        message: 'ok',
      );

  @override
  Future<LocalNotificationPermissionResult>
  requestNotificationPermission() async =>
      const LocalNotificationPermissionResult(
        status: LocalNotificationPermissionStatus.notRequired,
        message: 'ok',
      );

  @override
  Future<ScanCodeResult?> scanCode(
    NavigatorState navigator,
    ScanCodeRequest request,
  ) async => null;

  @override
  Future<void> setClipboardData(String value) async {}

  void addNetworkStatus(ClientNetworkStatus status) =>
      _networkController.add(status);

  Future<void> dispose() => _networkController.close();
}

class _FakeTransport implements JsBridgeTransport {
  final List<String> messages = <String>[];

  @override
  Future<void> postMessage(String message) async => messages.add(message);
}
