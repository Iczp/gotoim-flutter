import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:gotoim_flutter/core/browser/browser_home_page.dart';
import 'package:gotoim_flutter/core/browser/desktop_browser_window.dart';
import 'package:gotoim_flutter/core/widgets/desktop_startup_scene.dart';
import 'package:gotoim_flutter/features/auth/presentation/auth_loading_page.dart';

void main() {
  testWidgets('desktop auth checking keeps usable window controls', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: AuthLoadingPage(isDiagnosticsPreview: true)),
      ),
    );
    expect(find.text('正在恢复登录状态…'), findsOneWidget);
    expect(find.byTooltip('最小化'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('返回诊断中心'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('startup is opaque and reports actual initialization phase', (
    tester,
  ) async {
    final status = ValueNotifier('正在打开本地消息…');
    await tester.pumpWidget(DesktopStartupScene(status: status));
    expect(find.text('Goto IM'), findsWidgets);
    expect(find.text('正在打开本地消息…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byTooltip('最小化'), findsOneWidget);
    status.value = '正在进入工作区…';
    await tester.pump();
    expect(find.text('正在进入工作区…'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    status.dispose();
  });

  testWidgets(
    'local browser home submits addresses and searches without WebView',
    (tester) async {
      final destinations = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BrowserHomePage(onNavigate: destinations.add)),
        ),
      );
      expect(find.byType(InAppWebView), findsNothing);
      await tester.enterText(find.byType(TextField), 'example.com');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      expect(destinations.single, 'example.com');
      await tester.enterText(find.byType(TextField), 'Flutter 窗口');
      await tester.tap(find.byTooltip('打开'));
      final search = Uri.parse(destinations.last);
      expect(search.host, 'www.bing.com');
      expect(search.queryParameters['q'], 'Flutter 窗口');
    },
  );

  testWidgets(
    'new browser home mounts immediately without a security gate or WebView',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: DesktopBrowserWindow(initialUrl: 'about:blank'),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(BrowserHomePage), findsOneWidget);
      expect(find.byType(InAppWebView), findsNothing);
      expect(find.text('从这里，开始探索'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
