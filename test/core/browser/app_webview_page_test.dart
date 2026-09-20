import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/browser/app_webview_page.dart';

void main() {
  group('AppWebViewPage', () {
    testWidgets('renders title, back button, and more button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AppWebViewPage(
            initialUrl: 'https://im.gotoim.com/article/123',
            title: '文章详情',
          ),
        ),
      );

      // Verify AppBar elements
      expect(find.text('文章详情'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
    });

    testWidgets('tapping more button opens WeChat style action sheet', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AppWebViewPage(
            initialUrl: 'https://im.gotoim.com/docs/intro',
            title: '使用指南',
            fallbackContent: '离线纯文本说明内容。',
          ),
        ),
      );

      final moreButton = find.byIcon(Icons.more_horiz_rounded);
      expect(moreButton, findsOneWidget);

      await tester.tap(moreButton);
      await tester.pumpAndSettle();

      // Check WeChat-like sheet contents
      expect(find.text('发送给朋友'), findsOneWidget);
      expect(find.text('在浏览器打开'), findsOneWidget);
      expect(find.text('复制链接'), findsOneWidget);
      expect(find.text('查看纯文本'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);

      // Dismiss
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('取消'), findsNothing);
    });
  });
}
