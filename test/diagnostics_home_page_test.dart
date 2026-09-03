import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/widgets/cell_group.dart';
import 'package:gotoim_flutter/features/diagnostics/presentation/diagnostics_home_page.dart';

void main() {
  setUpAll(() => dotenv.loadFromString(envString: 'APP_NAME=Test'));

  testWidgets('DiagnosticsHomePage renders all CellGroups and Cells', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: DiagnosticsHomePage(),
      ),
    );
    await tester.pumpAndSettle();

    // Check main title
    expect(find.text('开发诊断中心'), findsOneWidget);

    // Check category group headers
    expect(find.text('基础设施与网络'), findsOneWidget);
    expect(find.text('聊天与实时通信'), findsOneWidget);
    expect(find.text('系统与设备能力'), findsOneWidget);

    // Verify CellGroup widgets exist
    expect(find.byType(CellGroup), findsWidgets);
    expect(find.byType(Cell), findsWidgets);

    // Verify some cell titles
    expect(find.text('Remote DevTools / AI 日志'), findsOneWidget);
    expect(find.text('认证与敏感凭据'), findsOneWidget);
    expect(find.text('消息列表数据流'), findsOneWidget);
    expect(find.text('Native / Device 设备能力'), findsOneWidget);
  });
}
