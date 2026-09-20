import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/browser/wechat_browser_more_sheet.dart';

void main() {
  group('WeChatBrowserMoreSheet', () {
    testWidgets('renders domain, actions in two rows, and cancel button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      showWeChatBrowserMoreSheet(
                        context,
                        url: 'https://im.gotoim.com/test-page.html',
                        title: '测试网页',
                        onRefresh: () {},
                      );
                    },
                    child: const Text('打开更多菜单'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('打开更多菜单'));
      await tester.pumpAndSettle();

      // Verify domain header
      expect(find.text('网页由 im.gotoim.com 提供'), findsOneWidget);

      // Verify Row 1: Share / Core actions
      expect(find.text('发送给朋友'), findsOneWidget);
      expect(find.text('分享到朋友圈'), findsOneWidget);
      expect(find.text('微信收藏'), findsOneWidget);
      expect(find.text('浮窗'), findsOneWidget);

      // Verify Row 2: Tools & Utilities
      expect(find.text('在浏览器打开'), findsOneWidget);
      expect(find.text('复制链接'), findsOneWidget);
      expect(find.text('刷新'), findsOneWidget);
      expect(find.text('调整字体'), findsOneWidget);
      expect(find.text('投诉'), findsOneWidget);

      // Verify Bottom Cancel button
      expect(find.text('取消'), findsOneWidget);
    });

    testWidgets('tapping 取消 button dismisses bottom sheet', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      showWeChatBrowserMoreSheet(
                        context,
                        url: 'https://im.gotoim.com/hello',
                        title: '你好',
                      );
                    },
                    child: const Text('弹出菜单'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('弹出菜单'));
      await tester.pumpAndSettle();

      expect(find.text('取消'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(find.text('取消'), findsNothing);
    });
  });
}
