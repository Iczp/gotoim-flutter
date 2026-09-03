import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:gotoim_flutter/core/device/client_device_context.dart';
import 'package:gotoim_flutter/core/widgets/cell_group.dart';
import 'package:gotoim_flutter/features/mine/presentation/mine_page.dart';
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

  testWidgets('MinePage renders user card, content cells, and settings entrance', (
    tester,
  ) async {
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
        child: MaterialApp(
          home: Scaffold(
            body: MinePage(
              isCompact: true,
              onOpenOwnerDrawer: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify User Info
    expect(find.text('当前用户'), findsOneWidget);

    // Verify Sections
    expect(find.text('我的内容'), findsOneWidget);
    expect(find.text('设置与服务'), findsOneWidget);
    expect(find.text('账号操作'), findsOneWidget);

    // Verify Settings Main Entrance
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('外观主题、字体大小、账号与通用设置'), findsOneWidget);

    // Verify Content items
    expect(find.text('账号设置'), findsOneWidget);
    expect(find.text('扫一扫'), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);

    // Confirm that old inline theme controls are NOT rendered on MinePage
    expect(find.text('色彩模式'), findsNothing);
    expect(find.text('列表过界效果'), findsNothing);
    expect(find.byType(CellGroup), findsWidgets);
  });
}
