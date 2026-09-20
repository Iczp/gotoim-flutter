import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:gotoim_flutter/core/device/client_device_context.dart';
import 'package:gotoim_flutter/features/session/application/friend_presence_store.dart';
import 'package:gotoim_flutter/features/session/data/models/chat_owner.dart';
import 'package:gotoim_flutter/features/session/presentation/current_owner_header.dart';

class _FakeFriendPresenceStore extends ChangeNotifier
    implements FriendPresenceStore {
  @override
  List<String> deviceTypesForChatObjectId(int? chatObjectId) => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() => dotenv.loadFromString(envString: 'APP_NAME=Test'));

  testWidgets('CurrentOwnerHeader renders owner info and action buttons', (tester) async {
    const owner = ChatOwner(
      id: 1,
      name: '管理员身份',
      imageUrl: null,
      typeDescription: '个人',
    );
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
    var openDrawerCalled = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appEnvironmentProvider.overrideWithValue(
            AppEnvironment.fromDotEnv(AppFlavor.development),
          ),
          clientDeviceContextProvider.overrideWithValue(fakeDevice),
          friendPresenceStoreProvider.overrideWith(
            (ref) => _FakeFriendPresenceStore(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  CurrentOwnerHeader(
                    owner: owner,
                    hasMultiple: true,
                    isConnecting: false,
                    onPressed: () => openDrawerCalled = true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // 验证身份信息和头像
    expect(find.text('管理员身份'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);

    // 验证搜索图标和 + 号按钮
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(find.byIcon(Icons.add_circle_outline_rounded), findsOneWidget);

    // 点击左侧身份切换触发回调
    await tester.tap(find.text('管理员身份'));
    await tester.pump();
    expect(openDrawerCalled, isTrue);

    // 点击 + 号按钮弹出菜单
    await tester.tap(find.byIcon(Icons.add_circle_outline_rounded));
    await tester.pumpAndSettle();

    // 验证菜单项
    expect(find.text('扫一扫'), findsOneWidget);
    expect(find.text('添加好友'), findsOneWidget);
    expect(find.text('创建群聊'), findsOneWidget);
  });

  testWidgets('CurrentOwnerHeader displays otherUnreadCount on dropdown arrow and not on avatar', (tester) async {
    const owner = ChatOwner(
      id: 1,
      name: '管理员身份',
      imageUrl: null,
      typeDescription: '个人',
    );
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
          friendPresenceStoreProvider.overrideWith(
            (ref) => _FakeFriendPresenceStore(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  CurrentOwnerHeader(
                    owner: owner,
                    hasMultiple: true,
                    isConnecting: false,
                    otherUnreadCount: 5,
                    otherImmersedCount: 0,
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // 验证数字角标 5 显示在界面上（下拉箭头角标）
    expect(find.text('5'), findsOneWidget);
    // 验证下拉图标存在
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
  });
}
