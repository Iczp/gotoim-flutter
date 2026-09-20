import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/widgets/app_badge.dart';

void main() {
  group('AppBadge Tests', () {
    testWidgets('renders count correctly and shows pop-in animation', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppBadge(count: 19),
          ),
        ),
      );

      // 动画完全过渡后
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
      expect(find.text('9'), findsOneWidget);
    });

    testWidgets('does not render when count is 0 and showZero is false', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppBadge(count: 0),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('0'), findsNothing);
    });

    testWidgets('renders when count is 0 and showZero is true', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppBadge(count: 0, showZero: true),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('transitions from 19 to 20 with scroll numbers', (
      tester,
    ) async {
      var count = 19;
      late StateSetter stateSetter;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                stateSetter = setState;
                return AppBadge(count: count);
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);
      expect(find.text('9'), findsOneWidget);

      // 切换到 20
      stateSetter(() {
        count = 20;
      });
      await tester.pump();
      // 在动画中期（150ms），滚轮同时包含新旧字符
      await tester.pump(const Duration(milliseconds: 160));

      // 动画完全过渡后
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('overflows to 99+ when count exceeds maxCount', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppBadge(count: 100, maxCount: 99),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('+'), findsOneWidget);
      expect(find.text('9'), findsNWidgets(2));
    });

    testWidgets('renders dot mode correctly', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppBadge(dot: true),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // dot 模式下不渲染任何文字
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('renders as overlay when child is provided', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppBadge(
              count: 5,
              child: Icon(Icons.mail),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.mail), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.byType(Positioned), findsOneWidget);
      expect(find.byType(Stack), findsWidgets);
    });
  });
}
