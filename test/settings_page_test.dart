import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/widgets/cell_group.dart';
import 'package:gotoim_flutter/features/settings/presentation/settings_page.dart';

void main() {
  setUpAll(() => dotenv.loadFromString(envString: 'APP_NAME=Test'));

  testWidgets('SettingsPage renders all sections and entrance items', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Check title
    expect(find.text('设置'), findsOneWidget);

    // Check group headers
    expect(find.text('账号与安全'), findsOneWidget);
    expect(find.text('通用与显示'), findsOneWidget);
    expect(find.text('系统与支持'), findsOneWidget);

    // Check cells
    expect(find.text('个人信息'), findsOneWidget);
    expect(find.text('账号管理'), findsOneWidget);
    expect(find.text('登录设备'), findsOneWidget);
    expect(find.text('外观与主题'), findsOneWidget);
    expect(find.text('局域网文件管理'), findsOneWidget);
    expect(find.text('扫码登录终端'), findsOneWidget);
    expect(find.text('清理临时缓存'), findsOneWidget);
    expect(find.text('关于 Goto IM'), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);

    expect(find.byType(CellGroup), findsWidgets);
    expect(find.byType(Cell), findsWidgets);
  });
}
