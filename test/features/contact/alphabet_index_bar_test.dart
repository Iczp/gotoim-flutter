import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/features/contact/presentation/widgets/alphabet_index_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final alphabetKeys = List.generate(
    26,
    (index) => String.fromCharCode(65 + index),
  ); // A-Z

  group('AlphabetIndexBar Responsive Layout Tests', () {
    testWidgets(
      'Renders in tall portrait constraints without overflow',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 32,
                height: 600,
                child: AlphabetIndexBar(
                  keys: alphabetKeys,
                  activeKey: 'A',
                  onSelected: (_) {},
                  onScrollToTop: () {},
                  onScrollToBottom: () {},
                  onDragging: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 验证没有 RenderFlex overflow
        expect(tester.takeException(), isNull);
        // 竖屏下保留全部字母与跳转图标
        expect(find.text('A'), findsOneWidget);
        expect(find.text('Z'), findsOneWidget);
        expect(find.byType(AlphabetJumpIcon), findsNWidgets(2));
      },
    );

    testWidgets(
      'Renders in exact landscape overflow height constraint (197.3px) without overflow',
      (tester) async {
        String? draggingKey;
        String? selectedKey;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 32,
                  height: 197.3, // 引起用户报错的精确高度约束
                  child: AlphabetIndexBar(
                    keys: alphabetKeys,
                    activeKey: 'B',
                    onSelected: (key) => selectedKey = key,
                    onScrollToTop: () {},
                    onScrollToBottom: () {},
                    onDragging: (key) => draggingKey = key,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // 验证无任何 RenderFlex overflow 异常
        expect(tester.takeException(), isNull);

        // 矮高度下省略跳转图标，为字母留出全部垂直空间
        expect(find.byType(AlphabetJumpIcon), findsNothing);

        // 首尾字母与激活字母始终显示
        expect(find.text('A'), findsOneWidget);
        expect(find.text('B'), findsOneWidget);
        expect(find.text('Z'), findsOneWidget);

        // 测试手势拖拽
        final bar = find.byType(AlphabetIndexBar);
        final barTopLeft = tester.getTopLeft(bar);
        final barHeight = tester.getSize(bar).height;

        // 在中间位置按下，触发拖拽
        final testGesture = await tester.startGesture(
          barTopLeft + Offset(16, barHeight / 2),
        );
        await tester.pump();

        expect(draggingKey, isNotNull);

        // 松手
        await testGesture.up();
        await tester.pumpAndSettle();

        expect(selectedKey, isNotNull);
      },
    );

    testWidgets(
      'Renders in ultra compact height (120px) gracefully with dot sampling',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 32,
                height: 120.0,
                child: AlphabetIndexBar(
                  keys: alphabetKeys,
                  activeKey: 'M',
                  onSelected: (_) {},
                  onScrollToTop: () {},
                  onScrollToBottom: () {},
                  onDragging: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        // 激活的 'M' 和首尾必须优先展示
        expect(find.text('A'), findsOneWidget);
        expect(find.text('M'), findsOneWidget);
        expect(find.text('Z'), findsOneWidget);
      },
    );
  });
}
