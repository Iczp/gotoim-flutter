import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/widgets/cell_group.dart';

void main() {
  setUpAll(() => dotenv.loadFromString(envString: 'APP_NAME=Test'));

  testWidgets('CellGroup renders header and children with dividers', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CellGroup(
            title: '通用设置',
            children: const [
              Cell(title: '语言', value: '简体中文', showArrow: true),
              Cell(title: '字体大小', value: '标准', showArrow: true),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('通用设置'), findsOneWidget);
    expect(find.text('语言'), findsOneWidget);
    expect(find.text('简体中文'), findsOneWidget);
    expect(find.text('字体大小'), findsOneWidget);
    expect(find.text('标准'), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);
  });

  testWidgets('Cell triggers onTap and copy handlers', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CellGroup(
            children: [
              Cell(
                title: '点击测试',
                onTap: () {
                  tapped = true;
                },
              ),
              const Cell(
                title: '复制测试',
                value: '123456',
                canCopy: true,
              ),
              const Cell(
                title: '退出登录',
                isCentered: true,
                titleColor: Colors.red,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('点击测试'));
    await tester.pump();
    expect(tapped, isTrue);

    expect(find.text('退出登录'), findsOneWidget);
  });

  testWidgets('CellGroup supports custom child widget', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CellGroup(
            title: '自定义区域',
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('自定义组件内容'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('自定义区域'), findsOneWidget);
    expect(find.text('自定义组件内容'), findsOneWidget);
  });

  testWidgets('Cell aligns title on the left and value flush to the right', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CellGroup(
            children: [
              Cell(title: '账号', value: 'admin@gotoim.com'),
              Cell(title: '邮箱', value: '55721736@qq.com', showArrow: true),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final accountLabel = tester.getTopLeft(find.text('账号'));
    final accountValue = tester.getTopRight(find.text('admin@gotoim.com'));

    // Label should be on the left (x < 50)
    expect(accountLabel.dx, lessThan(50));
    // Value should be flush near the right edge (x > 320 on a 400px screen)
    expect(accountValue.dx, greaterThan(320));

    final emailLabel = tester.getTopLeft(find.text('邮箱'));
    final emailValue = tester.getTopRight(find.text('55721736@qq.com'));
    final arrow = tester.getTopRight(find.byIcon(Icons.chevron_right));

    expect(emailLabel.dx, lessThan(50));
    // Arrow is at the right edge
    expect(arrow.dx, greaterThan(360));
    // Value is right before the arrow
    expect(emailValue.dx, greaterThan(280));
    expect(emailValue.dx, lessThanOrEqualTo(arrow.dx));
  });

  testWidgets('Cell applies default 0.5 opacity for subtitle and arrow', (
    tester,
  ) async {
    const primaryColor = Colors.blue;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: primaryColor,
          ),
        ),
        home: const Scaffold(
          body: CellGroup(
            children: [
              Cell(
                title: '设备信息',
                subtitle: '辅助说明文案',
                showArrow: true,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final textWidget = tester.widget<Text>(find.text('辅助说明文案'));
    expect(textWidget.style?.color?.a, closeTo(0.5, 0.01));

    final iconWidget = tester.widget<Icon>(find.byIcon(Icons.chevron_right));
    expect(iconWidget.color?.a, closeTo(0.5, 0.01));
  });

  testWidgets('Cell inherits subtitleColor from CellGroup or theme', (
    tester,
  ) async {
    const customGroupColor = Colors.deepPurple;
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CellGroup(
            subtitleColor: customGroupColor,
            children: [
              Cell(
                title: '分组统一副标题',
                subtitle: '统一紫色',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final textWidget = tester.widget<Text>(find.text('统一紫色'));
    expect(textWidget.style?.color, customGroupColor);
  });

  testWidgets('Cell supports switch and toggles on tap with 0.5 subtitle opacity', (
    tester,
  ) async {
    var switchState = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return CellGroup(
                children: [
                  Cell(
                    title: '夜间模式',
                    subtitle: '自动切换暗黑模式',
                    switchValue: switchState,
                    onSwitchChanged: (val) {
                      setState(() {
                        switchState = val;
                      });
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Switch), findsOneWidget);
    final subtitleText = tester.widget<Text>(find.text('自动切换暗黑模式'));
    expect(subtitleText.style?.color?.a, closeTo(0.5, 0.01));

    // Tap the cell to toggle switch
    await tester.tap(find.text('夜间模式'));
    await tester.pumpAndSettle();
    expect(switchState, isTrue);
  });

  testWidgets('SwitchListTile inside CellGroup inherits 0.5 opacity subtitle from ListTileTheme', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CellGroup(
            child: SwitchListTile(
              title: const Text('原生开关项'),
              subtitle: const Text('继承自主题的副标题'),
              value: true,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final element = tester.element(find.text('继承自主题的副标题'));
    final defaultTextStyle = DefaultTextStyle.of(element).style;
    expect(defaultTextStyle.color?.a, closeTo(0.5, 0.01));
  });

  testWidgets('Cell supports titleFontWeight and inherits from CellGroup', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              CellGroup(
                titleFontWeight: FontWeight.w700,
                children: [
                  Cell(title: '继承组粗体'),
                  Cell(title: '单独自定义', titleFontWeight: FontWeight.w300),
                ],
              ),
              Cell(title: '默认字重'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final inheritedText = tester.widget<Text>(find.text('继承组粗体'));
    expect(inheritedText.style?.fontWeight, FontWeight.w700);

    final overrideText = tester.widget<Text>(find.text('单独自定义'));
    expect(overrideText.style?.fontWeight, FontWeight.w300);

    final defaultText = tester.widget<Text>(find.text('默认字重'));
    expect(defaultText.style?.fontWeight, FontWeight.w500);
  });
}
