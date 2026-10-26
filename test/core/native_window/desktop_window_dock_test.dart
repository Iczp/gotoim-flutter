import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/native_window/desktop_window_dock_controller.dart';
import 'package:gotoim_flutter/core/browser/desktop_browser_dock_controller.dart'
    show desktopBrowserDockProvider;
import 'package:gotoim_flutter/core/platform/platform_facade.dart';
import 'package:gotoim_flutter/core/services/window_service.dart';

class _Platform implements PlatformFacade {
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

class _Windows extends DefaultWindowService {
  _Windows() : super(platformFacade: _Platform(), isSubWindow: true);
  final open = {'browser', 'media'};
  final events = <String>[];
  final failedDocks = <String>{};
  final failedUndocks = <String>{};
  Completer<void>? mediaWait;
  @override
  Future<void> bringToFront(String targetId) async {}
  @override
  bool isWindowOpen(String targetId) => open.contains(targetId);
  @override
  Future<void> ensureDockWindowReady(String targetId) async {
    if (!open.contains(targetId)) throw StateError('closed');
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
    events.add('dock:$targetId:$slotId');
    if (targetId == 'media') await mediaWait?.future;
    return open.contains(targetId) && !failedDocks.contains(targetId);
  }

  @override
  Future<bool> sendWindowUndockCommand(
    String targetId, {
    bool showWindow = true,
  }) async {
    events.add('undock:$targetId:$showWindow');
    return !failedUndocks.contains(targetId);
  }

  @override
  Future<void> sendWindowUpdateBoundsCommand({
    required String targetId,
    required String slotId,
    required int x,
    required int y,
    required int width,
    required int height,
  }) async => events.add('bounds:$targetId:$slotId:$width');
  @override
  Future<void> closeWindow(String targetId, {String? windowId}) async {
    events.add('close:$targetId');
    open.remove(targetId);
    onWindowClosed?.call(targetId);
  }
}

void main() {
  late ProviderContainer container;
  late _Windows service;
  late DesktopWindowDockNotifier dock;
  setUp(() {
    service = _Windows();
    container = ProviderContainer(
      overrides: [windowServiceProvider.overrideWithValue(service)],
    );
    dock = container.read(desktopWindowDockProvider.notifier);
    service.onWindowDockLayoutRequested =
        (id) async =>
            dock.updateBounds(id, (x: 600, y: 44, width: 520, height: 700));
  });
  tearDown(() => container.dispose());

  test(
    'replacing a slot pops out its occupant without closing either content',
    () async {
      await dock.dock(targetId: 'browser');
      await dock.dock(targetId: 'media');
      expect(dock.slot(DesktopWindowDockNotifier.chatRight).targetId, 'media');
      expect(service.events, contains('undock:browser:true'));
      expect(service.events.where((e) => e.startsWith('close:')), isEmpty);
      expect(service.open, {'browser', 'media'});
    },
  );
  test('a failed replacement restores the original occupant', () async {
    await dock.dock(targetId: 'browser');
    service.failedDocks.add('media');
    await expectLater(dock.dock(targetId: 'media'), throwsStateError);
    expect(dock.slot(DesktopWindowDockNotifier.chatRight).targetId, 'browser');
    expect(dock.slot(DesktopWindowDockNotifier.chatRight).isDocked, isTrue);
    expect(
      service.events.where((e) => e == 'dock:browser:chat:right').length,
      2,
    );
  });
  test('a failed displacement keeps the original occupant', () async {
    await dock.dock(targetId: 'browser');
    service.failedUndocks.add('browser');
    await expectLater(dock.dock(targetId: 'media'), throwsStateError);
    expect(dock.slot(DesktopWindowDockNotifier.chatRight).targetId, 'browser');
    expect(service.events, isNot(contains('dock:media:chat:right')));
  });
  test(
    'closing a displaced browser never closes the current media occupant',
    () async {
      service.open.add('tool:browser');
      final browser = container.read(desktopBrowserDockProvider.notifier);
      await dock.dock(targetId: 'media');
      await browser.closeDocked();
      expect(service.events, contains('close:tool:browser'));
      expect(service.events, isNot(contains('close:media')));
      expect(dock.slot(DesktopWindowDockNotifier.chatRight).targetId, 'media');
    },
  );
  test(
    'a failed replacement and failed recovery leave a truthful empty slot',
    () async {
      await dock.dock(targetId: 'browser');
      service.failedDocks.addAll({'browser', 'media'});
      await expectLater(dock.dock(targetId: 'media'), throwsStateError);
      expect(
        dock.slot(DesktopWindowDockNotifier.chatRight).shouldRenderPlaceholder,
        isFalse,
      );
      expect(
        dock.slot(DesktopWindowDockNotifier.chatRight).lastError,
        isNotNull,
      );
      expect(service.open, {'browser', 'media'});
    },
  );
  test(
    'unchanged layout completes replacement handshake without repeated bounds IPC',
    () async {
      await dock.dock(targetId: 'browser');
      final before =
          service.events.where((e) => e.startsWith('bounds:')).length;
      for (var i = 0; i < 50; i++) {
        dock.updateBounds(DesktopWindowDockNotifier.chatRight, (
          x: 600,
          y: 44,
          width: 520,
          height: 700,
        ));
      }
      await Future<void>.delayed(Duration.zero);
      expect(
        service.events.where((e) => e.startsWith('bounds:')).length,
        before,
      );
      // The same rectangle must still satisfy a NEW layout request on replacement.
      await dock.dock(targetId: 'media');
      expect(dock.slot(DesktopWindowDockNotifier.chatRight).targetId, 'media');
      dock.updateBounds(DesktopWindowDockNotifier.chatRight, (
        x: 600,
        y: 44,
        width: 600,
        height: 700,
      ));
      await Future<void>.delayed(Duration.zero);
      expect(service.events.last, 'bounds:media:chat:right:600');
    },
  );

  test(
    'different slots own their bounds and one window cannot occupy both',
    () async {
      await dock.dock(targetId: 'browser');
      await dock.dock(targetId: 'media', slotId: 'aux');
      dock.updateBounds('aux', (x: 0, y: 0, width: 400, height: 600));
      await Future<void>.delayed(Duration.zero);
      expect(service.events.last, 'bounds:media:aux:400');
      await expectLater(
        dock.dock(targetId: 'browser', slotId: 'aux'),
        throwsStateError,
      );
      await dock.undock(targetId: 'media');
      expect(dock.slot(DesktopWindowDockNotifier.chatRight).isDocked, isTrue);
      expect(dock.slot('aux').shouldRenderPlaceholder, isFalse);
    },
  );
  test(
    'closing replacement while native attach waits restores the old window',
    () async {
      await dock.dock(targetId: 'browser');
      service.mediaWait = Completer<void>();
      final replacing = dock.dock(targetId: 'media');
      await Future<void>.delayed(Duration.zero);
      await service.closeWindow('media');
      service.mediaWait!.complete();
      await replacing;
      expect(
        dock.slot(DesktopWindowDockNotifier.chatRight).targetId,
        'browser',
      );
      expect(dock.slot(DesktopWindowDockNotifier.chatRight).isDocked, isTrue);
    },
  );
  test(
    'closing the target clears its slot and unregisters callbacks on dispose',
    () async {
      await dock.dock(targetId: 'media');
      await dock.closeSlot(DesktopWindowDockNotifier.chatRight);
      expect(
        dock.slot(DesktopWindowDockNotifier.chatRight).shouldRenderPlaceholder,
        isFalse,
      );
      container.dispose();
      expect(service.onWindowDockRequested, isNull);
      expect(service.onWindowUndockRequested, isNull);
      expect(service.onWindowClosed, isNull);
      // tearDown must not dispose the same container twice.
      container = ProviderContainer();
    },
  );
}
