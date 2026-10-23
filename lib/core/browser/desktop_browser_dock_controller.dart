import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../native_window/desktop_window_dock_controller.dart';
import '../services/window_service.dart';
import 'desktop_browser_window.dart';

export '../native_window/desktop_window_dock_controller.dart';

typedef BrowserDockingStatus = WindowDockingStatus;

/// Browser entrypoint compatibility. Presentation belongs to the shared dock
/// controller; this adapter only opens browser content.
class DesktopBrowserDockNotifier extends Notifier<DesktopWindowDockState> {
  final _pendingOpens = <String, Future<void>>{};
  static const browserTargetId = 'tool:browser';
  DesktopWindowDockNotifier get _dock =>
      ref.read(desktopWindowDockProvider.notifier);
  DefaultWindowService get _service =>
      ref.read(windowServiceProvider) as DefaultWindowService;
  @override
  DesktopWindowDockState build() {
    final service = _service;
    Future<void> open(String url, String? title) =>
        requestDock(url: url, title: title);
    Future<void> standalone() => requestUndock();
    void closed() => _dock.windowClosed(browserTargetId);
    service.onBrowserDockRequested = open;
    service.onBrowserStandaloneRequested = standalone;
    service.onBrowserClosed = closed;
    ref.onDispose(() {
      if (service.onBrowserDockRequested == open) {
        service.onBrowserDockRequested = null;
      }
      if (service.onBrowserStandaloneRequested == standalone) {
        service.onBrowserStandaloneRequested = null;
      }
      if (service.onBrowserClosed == closed) service.onBrowserClosed = null;
    });
    DesktopWindowDockState select(Map<String, DesktopWindowDockState> slots) {
      final slot =
          slots[DesktopWindowDockNotifier.chatRight] ??
          const DesktopWindowDockState();
      return slot.targetId == null || slot.targetId == browserTargetId
          ? slot
          : DesktopWindowDockState(width: slot.width);
    }

    ref.listen(desktopWindowDockProvider, (_, next) => state = select(next));
    return select(ref.read(desktopWindowDockProvider));
  }

  static String? validateAndNormalizeUrl(String? url) =>
      DesktopBrowserWindow.validateAndNormalizeUrl(url);
  Future<void> requestDock({String? url, String? title}) {
    final key = url == null ? '' : (validateAndNormalizeUrl(url) ?? url.trim());
    final pending = _pendingOpens[key];
    if (pending != null) return pending;
    late final Future<void> opening;
    opening = _dock
        .dock(
          targetId: browserTargetId,
          prepareWindow:
              () => _service.ensureBrowserHost(url: url, title: title),
        )
        .whenComplete(() {
          if (identical(_pendingOpens[key], opening)) _pendingOpens.remove(key);
        });
    _pendingOpens[key] = opening;
    return opening;
  }

  Future<void> requestUndock({
    bool showWindow = true,
    String? activeUrl,
    String? activeTitle,
  }) => _dock.undock(targetId: browserTargetId, showWindow: showWindow);
  void updatePendingBounds({
    required int viewX,
    required int viewY,
    required int width,
    required int height,
  }) => _dock.updateBounds(DesktopWindowDockNotifier.chatRight, (
    x: viewX,
    y: viewY,
    width: width,
    height: height,
  ));
  void rejectLayout() =>
      _dock.rejectLayout(DesktopWindowDockNotifier.chatRight);
  void setWidth(double width, {double min = 360, double max = 960}) => _dock
      .setWidth(DesktopWindowDockNotifier.chatRight, width.clamp(min, max));
  Future<void> closeDocked() => _dock.closeTarget(browserTargetId);
}

final desktopBrowserDockProvider =
    NotifierProvider<DesktopBrowserDockNotifier, DesktopWindowDockState>(
      DesktopBrowserDockNotifier.new,
    );
