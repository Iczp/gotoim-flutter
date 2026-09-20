import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/compliance/agreement_viewer_page.dart';

void main() {
  group('AgreementViewerPage', () {
    testWidgets('renders title and pure text content with safe scrolling', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AgreementViewerPage(
            title: '测试用户服务协议',
            content: '这是详细的条款第一条，第二条，第三条。',
            initialMode: AgreementViewMode.pureText,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('测试用户服务协议'), findsNWidgets(2)); // AppBar and Title Header
      expect(find.text('这是详细的条款第一条，第二条，第三条。'), findsOneWidget);
      expect(find.text('已滑动至协议底部'), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(find.byType(SelectionArea), findsOneWidget);
    });

    testWidgets('can copy agreement text to clipboard', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AgreementViewerPage(
            title: '测试协议',
            content: '条款正文内容',
            initialMode: AgreementViewMode.pureText,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final copyButton = find.byIcon(Icons.copy_rounded);
      expect(copyButton, findsOneWidget);
      await tester.tap(copyButton);
      await tester.pump();

      expect(find.text('协议内容已复制到剪贴板'), findsOneWidget);
    });
  });
}
