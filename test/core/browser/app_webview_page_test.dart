import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/browser/app_webview_page.dart';
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

  group('AppWebViewPage', () {
    testWidgets('renders title, back button, and more button', (tester) async {
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
          child: const MaterialApp(
            home: AppWebViewPage(
              initialUrl: 'https://im.gotoim.com/article/123',
              title: '文章详情',
            ),
          ),
        ),
      );

      // Verify AppBar elements
      expect(find.text('文章详情'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
    });

    testWidgets('tapping more button opens WeChat style action sheet', (tester) async {
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
          child: const MaterialApp(
            home: AppWebViewPage(
              initialUrl: 'https://im.gotoim.com/docs/intro',
              title: '使用指南',
              fallbackContent: '离线纯文本说明内容。',
            ),
          ),
        ),
      );

      final moreButton = find.byIcon(Icons.more_horiz_rounded);
      expect(moreButton, findsOneWidget);

      await tester.tap(moreButton);
      await tester.pumpAndSettle();

      // Check WeChat-like sheet contents
      expect(find.text('转发给朋友'), findsOneWidget);
      expect(find.text('在浏览器打开'), findsOneWidget);
      expect(find.text('复制链接'), findsOneWidget);
      expect(find.text('查看纯文本'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);

      // Dismiss
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('取消'), findsNothing);
    });
  });
}
