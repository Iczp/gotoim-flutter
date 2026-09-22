import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/widgets/gotoim_logo.dart';
import 'package:gotoim_flutter/features/auth/presentation/auth_loading_page.dart';
import 'package:gotoim_flutter/features/diagnostics/presentation/splash_and_logo_diagnostics_page.dart';

void main() {
  group('GotoImLogo Component Tests', () {
    testWidgets('renders GotoImLogo with custom size and breathing animation', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: GotoImLogo(size: 160.0, enableBreathing: true)),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(GotoImLogo), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SizedBox &&
              widget.width == 160.0 &&
              widget.height == 160.0,
        ),
        findsOneWidget,
      );
    });

    testWidgets('handles tap event when onTap callback is provided', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: GotoImLogo(size: 100.0, onTap: () => tapped = true),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byType(GotoImLogo));
      expect(tapped, isTrue);
    });
  });

  group('AuthLoadingPage Splash Tests', () {
    testWidgets('renders full-screen immersion Splash with brand elements', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: AuthLoadingPage(isDiagnosticsPreview: true)),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      // Check for App Name and Logo
      expect(find.text('Goto IM'), findsOneWidget);
      expect(find.byType(GotoImLogo), findsOneWidget);
      expect(find.text('跨平台即时通讯 · 智能互联'), findsOneWidget);

      // Advance timer by 3.5 seconds to trigger escape options
      await tester.pump(const Duration(milliseconds: 3500));
      expect(find.text('返回诊断中心'), findsOneWidget);
    });
  });

  group('SplashAndLogoDiagnosticsPage Tests', () {
    testWidgets('renders diagnostics cards, slider and platform chips', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: SplashAndLogoDiagnosticsPage()),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('启动页与 Logo 体验中心'), findsOneWidget);
      expect(find.text('功能概览与支持平台'), findsOneWidget);
      expect(find.text('Logo 实验室 (交互调节)'), findsOneWidget);
      expect(find.text('全屏 Splash 沉浸体验'), findsOneWidget);
      expect(find.text('屏幕边缘与 Insets 诊断'), findsOneWidget);

      // Verify platforms
      expect(find.text('Android'), findsOneWidget);
      expect(find.text('iOS'), findsOneWidget);
      expect(find.text('Windows'), findsOneWidget);
    });
  });
}
