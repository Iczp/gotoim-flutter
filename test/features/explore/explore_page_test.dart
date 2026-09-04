import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:gotoim_flutter/core/device/client_device_context.dart';
import 'package:gotoim_flutter/features/explore/presentation/explore_page.dart';
import 'package:gotoim_flutter/features/session/application/session_list_controller.dart';
import 'package:gotoim_flutter/features/session/data/models/chat_owner.dart';
import 'package:gotoim_flutter/features/session/data/models/logged_in_device.dart';

class _FakeSessionListController extends ChangeNotifier
    implements SessionListController {
  @override
  ChatOwner? get currentOwner => null;

  @override
  List<LoggedInDevice> get devices => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() => dotenv.loadFromString(envString: 'APP_NAME=Test'));

  testWidgets(
    'ExplorePage renders inside CustomScrollView and scrolls without error',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const fakeDevice = ClientDeviceContext(
        appId: 'test-app',
        appName: 'GotoIM',
        appVersion: '1.0.0',
        deviceId: 'device-test-1',
        deviceType: '1',
        platform: 'Android',
        brand: 'Google',
        model: 'Test Pixel',
        browser: '',
        pushClientId: '',
      );

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
            home: Scaffold(body: ExplorePage(isCompact: true)),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify CustomScrollView is present
      expect(find.byType(CustomScrollView), findsOneWidget);

      // Verify "扫一扫" cell inside CellGroup is present
      expect(find.text('扫一扫'), findsOneWidget);

      // Verify scrolling does not crash or throw assertion errors
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(CustomScrollView), const Offset(0, 300));
      await tester.pumpAndSettle();
    },
  );
}
