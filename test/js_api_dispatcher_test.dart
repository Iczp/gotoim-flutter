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
import 'package:gotoim_flutter/core/services/file/file_upload_service.dart';
import 'package:gotoim_flutter/core/services/media/media_service.dart';
import 'package:gotoim_flutter/core/services/scan/scan_code_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeCapabilities capabilities;
  late _FakeUploadService uploadService;
  late JsApiDispatcher dispatcher;

  setUp(() {
    capabilities = _FakeCapabilities();
    uploadService = _FakeUploadService();
    dispatcher = JsApiDispatcher(
      capabilities: capabilities,
      uploadService: uploadService,
    );
  });

  tearDown(() async {
    await dispatcher.dispose();
    await capabilities.dispose();
    await uploadService.dispose();
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

  test('removes a network subscription explicitly', () async {
    await dispatcher.handleRaw(
      '{"id":"watch","action":"onNetworkStatusChange","data":{"subscriptionId":"n-1"}}',
    );
    final response =
        jsonDecode(
              await dispatcher.handleRaw(
                '{"id":"off","action":"offNetworkStatusChange","data":{"subscriptionId":"n-1"}}',
              ),
            )
            as Map<String, dynamic>;

    expect(response['success'], isTrue);
    expect(response['data']['removed'], isTrue);
  });

  test('forwards subscribed file-upload progress events', () async {
    final eventFuture = dispatcher.events.first;
    final response =
        jsonDecode(
              await dispatcher.handleRaw(
                '{"id":"upload-watch","action":"file.onUploadEvent","data":{"subscriptionId":"u-1"}}',
              ),
            )
            as Map<String, dynamic>;
    expect(response['data']['subscriptionId'], 'u-1');

    uploadService.emit(
      const FileUploadEvent(
        name: 'file.uploadProgress',
        task: FileUploadTask(
          taskId: 'task-1',
          fileId: 'file-1',
          state: FileUploadState.uploading,
          sentBytes: 50,
          totalBytes: 100,
        ),
      ),
    );
    final event = await eventFuture;

    expect(event.name, 'file.uploadProgress');
    expect(event.data['subscriptionId'], 'u-1');
    expect(event.data['progress'], 0.5);
  });

  test('records a Flutter-to-H5 ping receipt as a bridge event', () async {
    final eventFuture = dispatcher.events.first;
    final response =
        jsonDecode(
              await dispatcher.handleRaw(
                '{"id":"ping-receipt","action":"diagnostics.reportHostPing","data":{"pingId":"ping-1","receivedAt":"2026-08-20T00:00:00.000Z","success":true,"systemInfo":{"platform":"android"}}}',
              ),
            )
            as Map<String, dynamic>;

    expect(response['success'], isTrue);
    expect(response['data']['received'], isTrue);

    final event = await eventFuture;
    expect(event.name, 'diagnostics.hostPingResult');
    expect(event.data['pingId'], 'ping-1');
    expect(event.data['success'], isTrue);
    expect(
      (event.data['systemInfo'] as Map<String, dynamic>)['platform'],
      'android',
    );
  });

  test('accepts the image decode bridge action with base64 input', () async {
    final response =
        jsonDecode(
              await dispatcher.handleRaw(
                '{"id":"image-1","action":"scan.decodeImage","data":{"base64":"aW1hZ2U="}}',
              ),
            )
            as Map<String, dynamic>;

    expect(response['success'], isTrue);
    expect(response['data']['result'], isNull);
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

  test('handles Native device JSAPIs (battery, brightness, vibrate, makePhoneCall)', () async {
    final batteryRes = jsonDecode(
      await dispatcher.handleRaw('{"id":"bat-1","action":"getBatteryInfo","data":{}}'),
    ) as Map<String, dynamic>;
    expect(batteryRes['success'], isTrue);
    expect(batteryRes['data']['level'], isNotNull);

    final brightRes = jsonDecode(
      await dispatcher.handleRaw('{"id":"bri-1","action":"getScreenBrightness","data":{}}'),
    ) as Map<String, dynamic>;
    expect(brightRes['success'], isTrue);
    expect(brightRes['data']['value'], isNotNull);

    final setBrightRes = jsonDecode(
      await dispatcher.handleRaw('{"id":"bri-2","action":"setScreenBrightness","data":{"value":0.7}}'),
    ) as Map<String, dynamic>;
    expect(setBrightRes['success'], isTrue);

    final vibRes = jsonDecode(
      await dispatcher.handleRaw('{"id":"vib-1","action":"vibrate","data":{"style":"light","duration":100}}'),
    ) as Map<String, dynamic>;
    expect(vibRes['success'], isTrue);

    final callRes = jsonDecode(
      await dispatcher.handleRaw('{"id":"call-1","action":"makePhoneCall","data":{"phoneNumber":"10086"}}'),
    ) as Map<String, dynamic>;
    expect(callRes['success'], isTrue);
  });

  test('manages Native sensor & system event subscriptions and unsubscriptions via JSAPI', () async {
    final accSubRes = jsonDecode(
      await dispatcher.handleRaw('{"id":"sub-acc","action":"onAccelerometerChange","data":{"subscriptionId":"acc-1"}}'),
    ) as Map<String, dynamic>;
    expect(accSubRes['success'], isTrue);
    expect(accSubRes['data']['subscriptionId'], 'acc-1');

    final accOffRes = jsonDecode(
      await dispatcher.handleRaw('{"id":"off-acc","action":"offAccelerometerChange","data":{"subscriptionId":"acc-1"}}'),
    ) as Map<String, dynamic>;
    expect(accOffRes['success'], isTrue);

    final gyroSubRes = jsonDecode(
      await dispatcher.handleRaw('{"id":"sub-gyro","action":"onGyroscopeChange","data":{"subscriptionId":"gyro-1"}}'),
    ) as Map<String, dynamic>;
    expect(gyroSubRes['success'], isTrue);

    final proxSubRes = jsonDecode(
      await dispatcher.handleRaw('{"id":"sub-prox","action":"onProximityChange","data":{"subscriptionId":"prox-1"}}'),
    ) as Map<String, dynamic>;
    expect(proxSubRes['success'], isTrue);

    final screenshotSubRes = jsonDecode(
      await dispatcher.handleRaw('{"id":"sub-ss","action":"onUserCaptureScreen","data":{"subscriptionId":"ss-1"}}'),
    ) as Map<String, dynamic>;
    expect(screenshotSubRes['success'], isTrue);

    final themeSubRes = jsonDecode(
      await dispatcher.handleRaw('{"id":"sub-theme","action":"onThemeChange","data":{"subscriptionId":"theme-1"}}'),
    ) as Map<String, dynamic>;
    expect(themeSubRes['success'], isTrue);
    expect(themeSubRes['data']['currentBrightness'], isNotNull);

    final resizeSubRes = jsonDecode(
      await dispatcher.handleRaw('{"id":"sub-resize","action":"onResize","data":{"subscriptionId":"resize-1"}}'),
    ) as Map<String, dynamic>;
    expect(resizeSubRes['success'], isTrue);
    expect(resizeSubRes['data']['currentSize'], isNotNull);

    final memSubRes = jsonDecode(
      await dispatcher.handleRaw('{"id":"sub-mem","action":"onMemoryWarning","data":{"subscriptionId":"mem-1"}}'),
    ) as Map<String, dynamic>;
    expect(memSubRes['success'], isTrue);
  });

  test('dispatches chooseFile and chooseImage with multi-selection, maxCount, and file types', () async {
    final fileRes = jsonDecode(
      await dispatcher.handleRaw(
        '{"id":"pick-files","action":"chooseFile","data":{"allowMultiple":true,"maxCount":5,"allowedExtensions":["pdf","docx"],"fileType":"custom"}}',
      ),
    ) as Map<String, dynamic>;
    expect(fileRes['success'], isTrue);
    expect(capabilities.lastFilePickerRequest?.allowMultiple, isTrue);
    expect(capabilities.lastFilePickerRequest?.maxCount, 5);
    expect(capabilities.lastFilePickerRequest?.allowedExtensions, ['pdf', 'docx']);
    expect(capabilities.lastFilePickerRequest?.fileType, FileTypeCategory.custom);

    final imgRes = jsonDecode(
      await dispatcher.handleRaw(
        '{"id":"pick-img","action":"chooseImage","data":{"allowMultiple":true,"maxCount":9,"preserveOriginal":false,"imageQuality":80}}',
      ),
    ) as Map<String, dynamic>;
    expect(imgRes['success'], isTrue);
    expect(capabilities.lastMediaPickRequest?.allowMultiple, isTrue);
    expect(capabilities.lastMediaPickRequest?.maxCount, 9);
    expect(capabilities.lastMediaPickRequest?.preserveOriginal, isFalse);
    expect(capabilities.lastMediaPickRequest?.imageQuality, 80);
  });
}

class _FakeCapabilities implements ClientCapabilityService {
  final StreamController<ClientNetworkStatus> _networkController =
      StreamController<ClientNetworkStatus>.broadcast();

  FilePickerRequest? lastFilePickerRequest;
  MediaPickRequest? lastMediaPickRequest;

  @override
  Future<List<SelectedFile>> chooseFile(FilePickerRequest request) async {
    lastFilePickerRequest = request;
    return const <SelectedFile>[];
  }

  @override
  Future<List<SelectedFile>> chooseImage(MediaPickRequest request) async {
    lastMediaPickRequest = request;
    return const <SelectedFile>[];
  }

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
    source: 'plugin',
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

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  void addNetworkStatus(ClientNetworkStatus status) =>
      _networkController.add(status);

  Future<void> dispose() => _networkController.close();
}

class _FakeTransport implements JsBridgeTransport {
  final List<String> messages = <String>[];

  @override
  Future<void> postMessage(String message) async => messages.add(message);
}

class _FakeUploadService implements FileUploadService {
  final StreamController<FileUploadEvent> _events =
      StreamController<FileUploadEvent>.broadcast();

  @override
  Stream<FileUploadEvent> get events => _events.stream;

  @override
  Future<bool> cancel(String taskId) async => taskId == 'task-1';

  @override
  Future<void> dispose() => _events.close();

  void emit(FileUploadEvent event) => _events.add(event);

  @override
  Future<FileUploadTask> start(SelectedFile file, FileUploadRequest request) =>
      throw UnimplementedError();

  @override
  FileUploadTask? task(String taskId) => null;
}
