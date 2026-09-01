import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/floating_window/floating_window.dart';
import 'package:gotoim_flutter/core/services/task/app_task_manager.dart';
import 'package:gotoim_flutter/core/services/task/app_task_manager_android.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AndroidAppTaskManager openMiniApp sends correct arguments', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.gotoim.task_manager'),
      (call) async {
        calls.add(call);
        return null;
      },
    );

    final manager = FloatingWindowManager();
    final taskManager = AndroidAppTaskManager(floatingWindowManager: manager);

    await taskManager.openMiniApp(
      MiniAppTaskRequest(
        appId: 'oa',
        title: 'OA 协同办公',
        url: Uri.parse('https://oa.gotoim.com'),
        reuseExisting: true,
      ),
    );

    expect(calls.length, 1);
    expect(calls.first.method, 'openMiniApp');
    expect(calls.first.arguments['appId'], 'oa');
    expect(calls.first.arguments['url'], 'https://oa.gotoim.com');
  });

  test('AndroidAppTaskManager handles onMiniAppMinimized and onMiniAppClosed', () async {
    final manager = FloatingWindowManager();
    final channel = const MethodChannel('com.gotoim.task_manager');
    final taskManager = AndroidAppTaskManager(channel: channel, floatingWindowManager: manager);
    expect(taskManager.isSupported, isTrue);


    // Simulate minimize broadcast delivered from native
    final binding = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    await binding.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(
        const MethodCall('onMiniAppMinimized', {
          'appId': 'crm',
          'title': 'CRM 客户管理',
          'url': 'https://crm.gotoim.com',
        }),
      ),
      (data) {},
    );

    // Floating window manager should contain miniapp:crm
    expect(manager.contains('miniapp:crm'), isTrue);

    // Simulate close event from native
    await binding.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(
        const MethodCall('onMiniAppClosed', {
          'appId': 'crm',
        }),
      ),
      (data) {},
    );

    expect(manager.contains('miniapp:crm'), isFalse);
  });
}
