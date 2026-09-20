import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/browser/wechat_browser_more_sheet.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:gotoim_flutter/core/device/client_device_context.dart';
import 'package:gotoim_flutter/features/session/application/session_list_controller.dart';
import 'package:gotoim_flutter/features/session/data/models/chat_owner.dart';
import 'package:gotoim_flutter/features/session/data/models/session_summary.dart';

class _FakeSessionListController extends ChangeNotifier
    implements SessionListController {
  @override
  List<SessionSummary> get sessions => const [];

  @override
  ChatOwner? get currentOwner => null;

  @override
  int? get currentOwnerId => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => dotenv.loadFromString(
      envString: 'APP_NAME=Test\nAPI_BASE_URL=https://api.test.com'));

  const fakeDevice = ClientDeviceContext(
    appId: 'test-app',
    appName: 'GotoIM',
    appVersion: '1.0.0',
    deviceId: 'test-device-id',
    deviceType: '1',
    platform: 'Android',
    brand: 'Google',
    model: 'Test Pixel',
    browser: '',
    pushClientId: '',
  );

  group('WeChatBrowserMoreSheet', () {
    testWidgets('renders header, actions in two rows, and cancel button', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appEnvironmentProvider.overrideWithValue(
              AppEnvironment.fromDotEnv(AppFlavor.development),
            ),
            clientDeviceContextProvider.overrideWithValue(fakeDevice),
            sessionListControllerProvider.overrideWith(
              (ref) => _FakeSessionListController(),
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () {
                        showWeChatBrowserMoreSheet(
                          context,
                          url: 'https://im.gotoim.com/test-page.html',
                          title: '测试网页',
                          onRefresh: () {},
                        );
                      },
                      child: const Text('打开更多菜单'),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开更多菜单'));
      await tester.pumpAndSettle();

      // Verify Header
      expect(find.text('测试网页'), findsOneWidget);

      // Verify Row 1: Share / Core actions
      expect(find.text('转发给朋友'), findsOneWidget);
      expect(find.text('分享到朋友圈'), findsOneWidget);
      expect(find.text('收藏'), findsOneWidget);
      expect(find.text('搜一搜'), findsOneWidget);
      expect(find.text('用电脑打开'), findsOneWidget);
      expect(find.text('在浏览器打开'), findsOneWidget);

      // Verify Row 2: Tools & Utilities
      expect(find.text('浮窗'), findsOneWidget);
      expect(find.text('听全文'), findsOneWidget);
      expect(find.text('稍后听'), findsOneWidget);
      expect(find.text('保存为图片'), findsOneWidget);
      expect(find.text('投诉'), findsOneWidget);
      expect(find.text('复制链接'), findsOneWidget);

      // Verify Bottom Cancel button
      expect(find.text('取消'), findsOneWidget);
    });

    testWidgets('tapping 取消 button dismisses bottom sheet', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appEnvironmentProvider.overrideWithValue(
              AppEnvironment.fromDotEnv(AppFlavor.development),
            ),
            clientDeviceContextProvider.overrideWithValue(fakeDevice),
            sessionListControllerProvider.overrideWith(
              (ref) => _FakeSessionListController(),
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () {
                        showWeChatBrowserMoreSheet(
                          context,
                          url: 'https://im.gotoim.com/hello',
                          title: '你好',
                        );
                      },
                      child: const Text('弹出菜单'),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('弹出菜单'));
      await tester.pumpAndSettle();

      expect(find.text('取消'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(find.text('取消'), findsNothing);
    });
  });
}
