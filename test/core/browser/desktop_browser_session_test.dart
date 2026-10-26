import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/browser/desktop_browser_window.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:gotoim_flutter/core/security/url_security_level.dart';
import 'package:gotoim_flutter/core/security/url_security_repository.dart';

class _Security extends DefaultUrlSecurityRepository {
  _Security()
    : super(environment: AppEnvironment.fromDotEnv(AppFlavor.development));
  final pending = <String, Completer<UrlSecurityCheckResult>>{};
  @override
  Future<UrlSecurityCheckResult> checkUrl(String url) async {
    if (pending[url] case final completion?) return completion.future;
    final host = Uri.parse(url).host;
    return UrlSecurityCheckResult(
      url: url,
      domain: host,
      level:
          host == 'blocked.test'
              ? UrlSecurityLevel.blocked
              : host == 'warning.test'
              ? UrlSecurityLevel.warning
              : UrlSecurityLevel.safe,
      category: UrlRiskCategory.none,
      message: host,
    );
  }
}

class _Controller extends PlatformInAppWebViewController {
  _Controller(this.url)
    : super.implementation(
        PlatformInAppWebViewControllerCreationParams(id: url),
      );
  final String url;
  final loaded = <String>[];
  Uint8List? screenshot;
  int screenshotCalls = 0;
  @override
  Future<bool> canGoBack() async => false;
  @override
  Future<bool> canGoForward() async => false;
  @override
  Future<Uint8List?> takeScreenshot({
    ScreenshotConfiguration? screenshotConfiguration,
  }) async {
    screenshotCalls++;
    return screenshot;
  }

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async => null;
  @override
  Future<void> loadUrl({
    required URLRequest urlRequest,
    Uri? iosAllowingReadAccessTo,
    WebUri? allowingReadAccessTo,
  }) async => loaded.add(urlRequest.url.toString());
}

class _NativePlatform extends InAppWebViewPlatform {
  bool autoCommit = true;
  final mounted = <String, _SurfaceState>{};
  final created = <String>[];
  final disposed = <String>[];
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) => _NativeWidget(params, this);
}

class _NativeWidget extends PlatformInAppWebViewWidget {
  _NativeWidget(super.params, this.owner) : super.implementation();
  final _NativePlatform owner;
  @override
  Widget build(BuildContext context) => _Surface(params: params, owner: owner);
  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      InAppWebViewController.fromPlatform(platform: controller) as T;
  @override
  void dispose() {}
}

/// Models an independently mounted native surface, including a form whose
/// state must survive tab deletion and navigation gates.
class _Surface extends StatefulWidget {
  const _Surface({required this.params, required this.owner});
  final PlatformInAppWebViewWidgetCreationParams params;
  final _NativePlatform owner;
  @override
  State<_Surface> createState() => _SurfaceState();
}

class _SurfaceState extends State<_Surface> {
  late final String url;
  late final _Controller controller;
  final text = TextEditingController();
  @override
  void initState() {
    super.initState();
    url = widget.params.initialUrlRequest!.url.toString();
    controller = _Controller(url);
    widget.owner.created.add(url);
    widget.owner.mounted[url] = this;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.params.onWebViewCreated?.call(
          InAppWebViewController.fromPlatform(platform: controller),
        );
        if (widget.owner.autoCommit) {
          widget.params.onPageCommitVisible?.call(
            InAppWebViewController.fromPlatform(platform: controller),
            WebUri(url),
          );
        }
      }
    });
  }

  Future<NavigationActionPolicy?> navigate(String target) async =>
      await widget.params.shouldOverrideUrlLoading!(
        InAppWebViewController.fromPlatform(platform: controller),
        NavigationAction(
          request: URLRequest(url: WebUri(target)),
          isForMainFrame: true,
        ),
      );
  @override
  Widget build(BuildContext context) =>
      TextField(key: ValueKey('form:$url'), controller: text);
  @override
  void dispose() {
    widget.owner.disposed.add(url);
    widget.owner.mounted.remove(url);
    text.dispose();
    super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _NativePlatform platform;
  late _Security security;
  InAppWebViewPlatform? original;
  late Future<dynamic> Function(MethodCall) handler;
  setUp(() {
    dotenv.loadFromString(
      envString:
          'API_BASE_URL=https://api.gotoim.com\nAUTH_BASE_URL=https://auth.gotoim.com',
    );
    original = InAppWebViewPlatform.instance;
    platform = _NativePlatform();
    InAppWebViewPlatform.instance = platform;
    security = _Security();
  });
  tearDown(() {
    if (original != null) InAppWebViewPlatform.instance = original;
  });

  Future<void> open(WidgetTester tester, {bool settle = true}) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [urlSecurityRepositoryProvider.overrideWithValue(security)],
        child: MaterialApp(
          home: DesktopBrowserWindow(
            initialUrl: 'https://a.test',
            title: 'A',
            onRegisterMethodHandler: (callback) => handler = callback,
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets(
    'modal preview captures existing page without navigation or disposal',
    (tester) async {
      await open(tester);
      final surface = platform.mounted['https://a.test']!;
      surface.controller.screenshot = Uint8List.fromList([1, 2, 3]);
      surface.text.text = 'unsent form';
      final bytes = await handler(const MethodCall('window_dock_preview'));
      expect(bytes, [1, 2, 3]);
      expect(surface.text.text, 'unsent form');
      expect(surface.controller.loaded, isEmpty);
      expect(platform.created, ['https://a.test']);
      expect(platform.disposed, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'first paint replaces loading feedback without recreating the page',
    (tester) async {
      platform.autoCommit = false;
      await open(tester, settle: false);
      await tester.pump();
      expect(find.text('正在打开网页…'), findsOneWidget);
      final surface = platform.mounted['https://a.test']!;
      surface.widget.params.onPageCommitVisible?.call(
        InAppWebViewController.fromPlatform(platform: surface.controller),
        WebUri(surface.url),
      );
      await tester.pumpAndSettle();
      expect(find.text('正在打开网页…'), findsNothing);
      expect(platform.created, ['https://a.test']);
      expect(platform.disposed, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('readiness acknowledges a mounted host without another frame', (
    tester,
  ) async {
    await open(tester);
    final ready = await tester.runAsync(
      () => handler(
        const MethodCall('browser_ping'),
      ).timeout(const Duration(milliseconds: 200)),
    );
    expect(ready, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'hover shows a captured thumbnail and leaving removes the preview',
    (tester) async {
      await open(tester);
      final a = platform.mounted['https://a.test']!;
      a.controller.screenshot = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
      );
      a.widget.params.onProgressChanged?.call(
        InAppWebViewController.fromPlatform(platform: a.controller),
        100,
      );
      await tester.pump();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(0, 0));
      final region = find.byWidgetPredicate(
        (widget) =>
            widget.key?.toString().contains('browser_tab_hover_') ?? false,
      );
      await tester.runAsync(() async {
        await mouse.moveTo(tester.getCenter(region));
        final watch = Stopwatch()..start();
        while (watch.elapsed < const Duration(seconds: 3)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          final diagnostics =
              await handler(const MethodCall('browser_diagnostics')) as Map;
          if ((diagnostics['thumbnailReady'] as List).first == true) break;
        }
      });
      await tester.pumpAndSettle();
      expect(a.controller.screenshotCalls, 1);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget.key?.toString().contains('browser_tab_preview_') ?? false,
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Image && widget.image is MemoryImage,
        ),
        findsOneWidget,
      );
      await mouse.moveTo(const Offset(10, 600));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget.key?.toString().contains('browser_tab_preview_') ?? false,
        ),
        findsNothing,
      );
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'deleting an earlier tab preserves native mounts, form and active tab',
    (tester) async {
      await open(tester);
      await handler(
        const MethodCall('browser_add_tab', {
          'url': 'https://b.test',
          'title': 'B',
        }),
      );
      await tester.pumpAndSettle();
      final b = platform.mounted['https://b.test']!;
      await tester.enterText(
        find.byKey(const ValueKey('form:https://b.test')),
        'unsent form',
      );
      await handler(
        const MethodCall('browser_add_tab', {
          'url': 'https://c.test',
          'title': 'C',
        }),
      );
      await tester.pumpAndSettle();
      await handler(
        const MethodCall('browser_add_tab', {
          'url': 'https://b.test',
          'title': 'B',
        }),
      );
      await tester.pumpAndSettle();
      final before =
          await handler(const MethodCall('browser_diagnostics')) as Map;
      final aId = (before['tabIds'] as List).first;
      await tester.tap(find.byKey(ValueKey('close_browser_tab_$aId')));
      // The draggable title bar also recognises double clicks.
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      final after =
          await handler(const MethodCall('browser_diagnostics')) as Map;
      expect(after['urls'], ['https://b.test', 'https://c.test']);
      expect(after['activeTabId'], before['activeTabId']);
      expect(platform.mounted['https://b.test'], same(b));
      expect(b.text.text, 'unsent form');
      expect(platform.created, [
        'https://a.test',
        'https://b.test',
        'https://c.test',
      ]);
      expect(platform.disposed, ['https://a.test']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'warning and blocked navigations cancel before load without disposing old page',
    (tester) async {
      await open(tester);
      final a = platform.mounted['https://a.test']!;
      expect(
        await a.navigate('https://warning.test'),
        NavigationActionPolicy.CANCEL,
      );
      await tester.pumpAndSettle();
      expect(platform.disposed, isEmpty);
      await tester.tap(find.text('继续访问'));
      await tester.pumpAndSettle();
      expect(a.controller.loaded, ['https://warning.test']);
      expect(
        await a.navigate('https://warning.test'),
        NavigationActionPolicy.ALLOW,
      );
      expect(
        await a.navigate('https://blocked.test'),
        NavigationActionPolicy.CANCEL,
      );
      await tester.pumpAndSettle();
      expect(platform.disposed, isEmpty);
      expect(platform.created, ['https://a.test']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('a stale security response cannot block a newer navigation', (
    tester,
  ) async {
    await open(tester);
    final a = platform.mounted['https://a.test']!;
    final slow = Completer<UrlSecurityCheckResult>();
    security.pending['https://slow.test'] = slow;
    final first = a.navigate('https://slow.test');
    expect(await a.navigate('https://safe.test'), NavigationActionPolicy.ALLOW);
    slow.complete(
      const UrlSecurityCheckResult(
        url: 'https://slow.test',
        domain: 'slow.test',
        level: UrlSecurityLevel.blocked,
        category: UrlRiskCategory.other,
        message: 'old result',
      ),
    );
    expect(await first, NavigationActionPolicy.CANCEL);
    await tester.pumpAndSettle();
    expect(platform.disposed, isEmpty);
    expect(find.text('已停止访问该网页'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('slow security shows feedback, times out closed and can retry', (
    tester,
  ) async {
    await open(tester);
    final lateResult = Completer<UrlSecurityCheckResult>();
    security.pending['https://slow.test'] = lateResult;
    await handler(
      const MethodCall('browser_add_tab', {'url': 'https://slow.test'}),
    );
    await tester.pump();
    expect(find.text('正在进行安全核验...'), findsOneWidget);
    expect(platform.created, isNot(contains('https://slow.test')));
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    expect(find.text('安全核验超时，请点击“重新加载”重试'), findsOneWidget);
    expect(platform.created, isNot(contains('https://slow.test')));
    lateResult.complete(
      const UrlSecurityCheckResult(
        url: 'https://slow.test',
        domain: 'slow.test',
        level: UrlSecurityLevel.safe,
        category: UrlRiskCategory.none,
        message: 'late result',
      ),
    );
    await tester.pump();
    expect(platform.created, isNot(contains('https://slow.test')));
    security.pending.remove('https://slow.test');
    await tester.tap(find.text('重新加载').last);
    await tester.pumpAndSettle();
    expect(platform.created, contains('https://slow.test'));
    await tester.pumpWidget(const SizedBox());
  });
}
