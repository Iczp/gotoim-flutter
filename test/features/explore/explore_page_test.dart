import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:gotoim_flutter/core/device/client_device_context.dart';
import 'package:gotoim_flutter/core/services/window_service.dart';
import 'package:gotoim_flutter/features/explore/presentation/explore_page.dart';
import 'package:gotoim_flutter/features/home/presentation/home_sections.dart';
import 'package:gotoim_flutter/features/session/application/session_list_controller.dart';
import 'package:gotoim_flutter/features/session/data/models/chat_owner.dart';
import 'package:gotoim_flutter/features/session/data/models/logged_in_device.dart';
import 'package:gotoim_flutter/features/social/application/social_notifications_controller.dart';
import 'package:gotoim_flutter/features/social/data/social_repository.dart';
import 'package:gotoim_flutter/app/shell/desktop_dock_rail.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';

class _FakeApiClient extends Fake implements ApiClient {}

class _FakeWindowService extends Fake implements WindowService {
  int openSocialCount = 0;
  String? lastSocialInitialPath;

  @override
  Future<void> openSocial({String initialPath = '/social'}) async {
    openSocialCount++;
    lastSocialInitialPath = initialPath;
  }
}

class _FakeSessionListController extends ChangeNotifier
    implements SessionListController {
  @override
  ChatOwner? get currentOwner => null;

  @override
  int get otherUnreadCount => 0;

  @override
  int get otherImmersedCount => 0;

  @override
  int get totalUnreadCount => 0;

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
      expect(find.text('扫一扫'), findsWidgets);

      // Verify scrolling does not crash or throw assertion errors
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(CustomScrollView), const Offset(0, 300));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'DesktopDockRail and ExplorePage open Social via WindowService.openSocial()',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeWindowService = _FakeWindowService();
      final fakeNotifications = SocialNotificationsController(
        SocialRepository(_FakeApiClient()),
      )..unreadCount = 3;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            windowServiceProvider.overrideWithValue(fakeWindowService),
            sessionListControllerProvider.overrideWith(
              (ref) => _FakeSessionListController(),
            ),
            socialNotificationsProvider.overrideWith(
              (ref) => fakeNotifications,
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Row(
                children: [
                  DesktopDockRail(
                    selected: HomeSection.explore,
                    onSelected: (_) {},
                  ),
                  const Expanded(child: ExplorePage(isCompact: false)),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify DesktopDockRail has Social item and tapping it triggers openSocial()
      final railSocial = find.descendant(
        of: find.byType(DesktopDockRail),
        matching: find.byTooltip('Social'),
      );
      expect(railSocial, findsOneWidget);
      await tester.tap(railSocial);
      await tester.pump();
      expect(fakeWindowService.openSocialCount, 1);
      expect(fakeWindowService.lastSocialInitialPath, '/social');

      // Verify ExplorePage Social feature card also triggers openSocial()
      final exploreSocial = find.text('动态广场 (Social)');
      expect(exploreSocial, findsOneWidget);
      await tester.tap(exploreSocial);
      await tester.pump();
      expect(fakeWindowService.openSocialCount, 2);
    },
  );
}
