import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/features/chat/presentation/widgets/chat_title_bar.dart';

void main() {
  group('Chat multi-select back navigation & ChatTitleBar Tests', () {
    testWidgets('ChatTitleBar shows close button in selectionMode and calls onCancelSelection', (tester) async {
      var cancelled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: ChatTitleBar(
              title: '测试群聊',
              showTransfer: true,
              selectionMode: true,
              onCancelSelection: () => cancelled = true,
              onTransfer: () {},
              onOpenSettings: () {},
            ),
            body: const SizedBox(),
          ),
        ),
      );

      // Should show close button instead of default back/transfer actions
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.byTooltip('转接'), findsNothing);
      expect(find.byTooltip('聊天设置'), findsNothing);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(cancelled, isTrue);
    });

    testWidgets('ChatTitleBar shows regular actions when selectionMode is false', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: ChatTitleBar(
              title: '测试群聊',
              showTransfer: true,
              selectionMode: false,
              onTransfer: () {},
              onOpenSettings: () {},
            ),
            body: const SizedBox(),
          ),
        ),
      );

      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.byTooltip('转接'), findsOneWidget);
      expect(find.byTooltip('聊天设置'), findsOneWidget);
    });

    testWidgets('PopScope cancels selectionMode on back instead of popping page', (tester) async {
      var selectionMode = true;
      var cancelCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              return PopScope(
                canPop: !selectionMode,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop && selectionMode) {
                    setState(() {
                      selectionMode = false;
                      cancelCount++;
                    });
                  }
                },
                child: Scaffold(
                  appBar: AppBar(title: Text(selectionMode ? '多选中' : '正常')),
                  body: Builder(
                    builder: (btnContext) => ElevatedButton(
                      onPressed: () => Navigator.maybePop(btnContext),
                      child: const Text('Back'),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );

      expect(find.text('多选中'), findsOneWidget);

      // First back invocation -> should NOT exit page, but cancel selection mode
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();

      expect(cancelCount, equals(1));
      expect(find.text('正常'), findsOneWidget);
    });
  });
}
