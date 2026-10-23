import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/browser/desktop_browser_dock_controller.dart';
import 'package:gotoim_flutter/core/platform/platform_facade.dart';
import 'package:gotoim_flutter/core/services/window_service.dart';

class _Windows implements PlatformFacade {
  @override
  PlatformKind get kind => PlatformKind.windows;
  @override
  bool get isWeb => false;
  @override
  bool get isDesktop => true;
  @override
  bool get supportsMultipleWindows => true;
  @override
  bool get supportsNativeFilePaths => true;
}

class _BrowserService extends DefaultWindowService {
  _BrowserService() : super(platformFacade: _Windows(), isSubWindow: true);
  final events = <String>[];
  final urls = <String>[];
  bool open = false;
  bool dockSucceeds = true;
  bool undockSucceeds = true;
  Completer<void>? dockWait;
  @override
  Future<void> ensureDockWindowReady(String targetId) async {}
  @override
  bool isWindowOpen(String targetId) => open;
  @override
  Future<void> bringToFront(String targetId) async =>
      events.add('front:$targetId');
  @override
  Future<void> ensureBrowserHost({String? url, String? title}) async {
    if (!open) {
      open = true;
      events.add('create');
    }
    if (url != null) urls.add(url);
  }

  @override
  Future<bool> sendWindowDockCommand({
    required String targetId,
    required String slotId,
    required int x,
    required int y,
    required int width,
    required int height,
  }) async {
    events.add('dock');
    await dockWait?.future;
    return dockSucceeds;
  }

  @override
  Future<void> sendWindowUpdateBoundsCommand({
    required String targetId,
    required String slotId,
    required int x,
    required int y,
    required int width,
    required int height,
  }) async => events.add('bounds:$width');
  @override
  Future<bool> sendWindowUndockCommand(
    String targetId, {
    bool showWindow = true,
  }) async {
    events.add('undock');
    return undockSucceeds;
  }

  @override
  Future<void> closeWindow(String targetId, {String? windowId}) async {
    events.add('close');
    open = false;
    urls.clear();
    onBrowserClosed?.call();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _BrowserService service;
  late ProviderContainer container;
  late DesktopBrowserDockNotifier notifier;
  setUp(() {
    service = _BrowserService();
    container = ProviderContainer(
      overrides: [windowServiceProvider.overrideWithValue(service)],
    );
    notifier = container.read(desktopBrowserDockProvider.notifier);
    service.onBrowserDockLayoutRequested = () async {
      notifier.updatePendingBounds(
        viewX: 700,
        viewY: 48,
        width: 520,
        height: 600,
      );
    };
  });
  tearDown(() => container.dispose());

  test('cold open exposes loading state and merges repeated clicks', () async {
    service.dockWait = Completer<void>();
    final first = notifier.requestDock(url: 'https://a.example');
    final repeated = notifier.requestDock(url: 'https://a.example');
    expect(identical(first, repeated), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(desktopBrowserDockProvider).status,
      WindowDockingStatus.docking,
    );
    service.dockWait!.complete();
    await first;
    expect(container.read(desktopBrowserDockProvider).isDocked, isTrue);
    expect(service.urls, ['https://a.example']);
    await notifier.requestDock(url: 'https://a.example');
    expect(service.urls.length, 2);
  });

  test(
    'dock/undock/redock retains host and all tabs without opening a snapshot',
    () async {
      await notifier.requestDock(url: 'https://a.example');
      await notifier.requestDock(url: 'https://b.example');
      await notifier.requestUndock();
      await notifier.requestDock();
      expect(service.events.where((event) => event == 'create').length, 1);
      expect(service.events, isNot(contains('close')));
      expect(service.urls, ['https://a.example', 'https://b.example']);
      expect(container.read(desktopBrowserDockProvider).isDocked, isTrue);
    },
  );

  test('failed undock rolls back to usable docked state', () async {
    await notifier.requestDock(url: 'https://a.example');
    service.undockSucceeds = false;
    await expectLater(notifier.requestUndock(), throwsStateError);
    final state = container.read(desktopBrowserDockProvider);
    expect(state.isDocked, isTrue);
    expect(state.lastError, isNotNull);
    expect(service.urls, ['https://a.example']);
  });

  test('failed dock restores standalone and preserves live host', () async {
    service.dockSucceeds = false;
    await expectLater(
      notifier.requestDock(url: 'https://a.example'),
      throwsStateError,
    );
    expect(
      container.read(desktopBrowserDockProvider).status,
      BrowserDockingStatus.unattached,
    );
    expect(service.open, isTrue);
    expect(service.events.last, 'front:tool:browser');
  });

  test('overlapping presentation requests run in order', () async {
    service.dockWait = Completer<void>();
    final dock = notifier.requestDock(url: 'https://a.example');
    final undock = notifier.requestUndock();
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(desktopBrowserDockProvider).status,
      BrowserDockingStatus.docking,
    );
    expect(service.events, isNot(contains('undock')));
    service.dockWait!.complete();
    await Future.wait([dock, undock]);
    expect(
      service.events.indexOf('undock'),
      greaterThan(service.events.indexOf('dock')),
    );
    expect(
      container.read(desktopBrowserDockProvider).status,
      BrowserDockingStatus.unattached,
    );
  });

  test('insufficient layout fails before changing the browser', () async {
    service.onBrowserDockLayoutRequested = () async => notifier.rejectLayout();
    await expectLater(notifier.requestDock(), throwsStateError);
    expect(service.events, isNot(contains('create')));
    expect(
      container.read(desktopBrowserDockProvider).lastError,
      contains('窗口太窄'),
    );
  });

  test(
    'a native close during docking cannot resurrect the closed panel',
    () async {
      service.dockWait = Completer<void>();
      final dock = notifier.requestDock(url: 'https://a.example');
      await Future<void>.delayed(Duration.zero);
      await service.closeWindow('tool:browser');
      service.dockWait!.complete();
      await dock;
      expect(
        container.read(desktopBrowserDockProvider).shouldRenderPlaceholder,
        isFalse,
      );
      expect(service.urls, isEmpty);
    },
  );

  test(
    'close clears host and provider callbacks do not outlive container',
    () async {
      await notifier.requestDock(url: 'https://a.example');
      await notifier.closeDocked();
      expect(service.open, isFalse);
      expect(
        container.read(desktopBrowserDockProvider).shouldRenderPlaceholder,
        isFalse,
      );
      container.invalidate(desktopBrowserDockProvider);
      expect(service.onBrowserDockRequested, isNull);
      expect(service.onBrowserStandaloneRequested, isNull);
      expect(service.onBrowserClosed, isNull);
    },
  );
}
