import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../platform/desktop_window_adapter.dart';
import '../services/window_service.dart';

enum WindowDockingStatus { unattached, docking, docked, undocking }

class DesktopWindowDockState {
  const DesktopWindowDockState({
    this.targetId,
    this.status = WindowDockingStatus.unattached,
    this.width = 520,
    this.lastError,
    this.requestSeq = 0,
    this.routeCovered = false,
    this.preview,
  });
  final String? targetId;
  final WindowDockingStatus status;
  final double width;
  final String? lastError;
  final int requestSeq;
  final bool routeCovered;
  final Uint8List? preview;
  bool get isDocked => status == WindowDockingStatus.docked;
  bool get isTransitioning =>
      status == WindowDockingStatus.docking ||
      status == WindowDockingStatus.undocking;
  bool get shouldRenderPlaceholder => status != WindowDockingStatus.unattached;
  DesktopWindowDockState copyWith({
    String? targetId,
    WindowDockingStatus? status,
    double? width,
    String? lastError,
    int? requestSeq,
    bool clearError = false,
    bool? routeCovered,
    Uint8List? preview,
    bool clearPreview = false,
  }) => DesktopWindowDockState(
    targetId: targetId ?? this.targetId,
    status: status ?? this.status,
    width: width ?? this.width,
    lastError: clearError ? null : lastError ?? this.lastError,
    requestSeq: requestSeq ?? this.requestSeq,
    routeCovered: routeCovered ?? this.routeCovered,
    preview: clearPreview ? null : preview ?? this.preview,
  );
}

typedef WindowDockBounds = ({int x, int y, int width, int height});

/// Presentation only: the business window owns its content and controllers.
/// One window per slot; replacing an occupant pops it out without disposing it.
class DesktopWindowDockNotifier
    extends Notifier<Map<String, DesktopWindowDockState>> {
  static const chatRight = 'chat:right';
  Future<void> _operations = Future<void>.value();
  final _layouts = <String, Completer<WindowDockBounds>>{};
  final _bounds = <String, WindowDockBounds>{};
  final _updating = <String>{};
  final _generations = <String, int>{};
  bool _disposed = false;
  int _routeRevision = 0;

  /// Keep a memory-only preview underneath modal Flutter routes. The native
  /// window remains alive, but must hide so it cannot paint over the dialog.
  Future<void> setRouteVisible(bool visible) async {
    final revision = ++_routeRevision;
    if (visible) {
      await DesktopWindowAdapter.setBrowserDockVisible(true, route: true);
      if (_disposed || revision != _routeRevision) return;
      for (final id in state.keys.toList()) {
        _put(id, slot(id).copyWith(routeCovered: false, clearPreview: true));
      }
      return;
    }
    final targets = Map.of(state);
    await Future.wait(
      targets.entries.where((entry) => entry.value.isDocked).map((entry) async {
        final bytes = await _service.captureDockPreview(entry.value.targetId!);
        if (_disposed ||
            revision != _routeRevision ||
            slot(entry.key).targetId != entry.value.targetId ||
            !slot(entry.key).isDocked) {
          return;
        }
        _put(
          entry.key,
          slot(entry.key).copyWith(
            routeCovered: true,
            preview: bytes,
            clearPreview: bytes == null,
          ),
        );
      }),
    );
    if (_disposed || revision != _routeRevision) return;
    // Paint the replacement before exposing it by hiding the native HWND.
    await WidgetsBinding.instance.endOfFrame;
    if (_disposed || revision != _routeRevision) return;
    await DesktopWindowAdapter.setBrowserDockVisible(false, route: true);
  }

  DefaultWindowService get _service =>
      ref.read(windowServiceProvider) as DefaultWindowService;
  DesktopWindowDockState slot(String id) =>
      state[id] ?? const DesktopWindowDockState();
  void _put(String id, DesktopWindowDockState value) =>
      state = {...state, id: value};

  @override
  Map<String, DesktopWindowDockState> build() {
    final service = _service;
    service.onWindowDockRequested = dock;
    service.onWindowUndockRequested = undock;
    service.onWindowClosed = windowClosed;
    ref.onDispose(() {
      _disposed = true;
      for (final ready in _layouts.values) {
        if (!ready.isCompleted) ready.completeError(StateError('吸附区域已释放'));
      }
      if (service.onWindowDockRequested == dock) {
        service.onWindowDockRequested = null;
      }
      if (service.onWindowUndockRequested == undock) {
        service.onWindowUndockRequested = null;
      }
      if (service.onWindowClosed == windowClosed) service.onWindowClosed = null;
    });
    return {};
  }

  Future<void> _serialize(Future<void> Function() action) {
    final next = _operations.then((_) async {
      if (!_disposed) await action();
    });
    _operations = next.catchError((Object _) {});
    return next;
  }

  Future<void> dock({
    required String targetId,
    String slotId = chatRight,
    Future<void> Function()? prepareWindow,
  }) => _serialize(() async {
    final service = _service;
    if (!service.supportsWindowDocking) throw UnsupportedError('当前平台暂不支持窗口吸附');
    final occupiedSlot = state.entries.where(
      (e) =>
          e.key != slotId &&
          e.value.targetId == targetId &&
          e.value.shouldRenderPlaceholder,
    );
    if (occupiedSlot.isNotEmpty) throw StateError('窗口已占用其他吸附区域，请先弹出');
    final previous = slot(slotId);
    final generation = _generations[targetId] ?? 0;
    final previousGeneration =
        previous.targetId == null ? 0 : (_generations[previous.targetId] ?? 0);
    final ready = Completer<WindowDockBounds>();
    final layout = ready.future.timeout(const Duration(seconds: 5));
    layout.ignore();
    _layouts[slotId] = ready;
    var displaced = false;
    var attached = false;
    bool valid() => !_disposed && generation == (_generations[targetId] ?? 0);
    _put(
      slotId,
      previous.copyWith(
        targetId: targetId,
        status: WindowDockingStatus.docking,
        requestSeq: previous.requestSeq + 1,
        clearError: true,
        routeCovered: false,
        clearPreview: true,
      ),
    );
    try {
      await service.bringToFront('main');
      if (service.onWindowDockLayoutRequested != null) {
        await service.onWindowDockLayoutRequested!(slotId);
      } else {
        await service.onBrowserDockLayoutRequested?.call();
      }
      final bounds = await layout;
      if (!valid()) throw StateError('目标窗口已关闭');
      await prepareWindow?.call();
      if (!valid()) throw StateError('目标窗口已关闭');
      await service.ensureDockWindowReady(targetId);
      if (!valid()) throw StateError('目标窗口已关闭');
      if (previous.isDocked && previous.targetId != targetId) {
        if (!await service.sendWindowUndockCommand(previous.targetId!)) {
          throw StateError('原窗口弹出失败');
        }
        displaced = true;
      }
      if (!await service.sendWindowDockCommand(
        targetId: targetId,
        slotId: slotId,
        x: bounds.x,
        y: bounds.y,
        width: bounds.width,
        height: bounds.height,
      )) {
        throw StateError('窗口吸附失败，已保留原内容');
      }
      attached = true;
      if (!valid()) {
        await service.sendWindowUndockCommand(targetId, showWindow: false);
        throw StateError('目标窗口已关闭');
      }
      _put(
        slotId,
        slot(
          slotId,
        ).copyWith(status: WindowDockingStatus.docked, clearError: true),
      );
      await _flush(slotId);
      if (displaced && valid()) await service.bringToFront('main');
    } catch (error) {
      if (!_disposed) {
        final previousAlive =
            previous.targetId == null ||
            (previousGeneration == (_generations[previous.targetId] ?? 0) &&
                service.isWindowOpen(previous.targetId!));
        var restored = !displaced && previousAlive;
        final bounds = _bounds[slotId];
        if (displaced &&
            bounds != null &&
            previousGeneration == (_generations[previous.targetId] ?? 0) &&
            service.isWindowOpen(previous.targetId!)) {
          try {
            restored = await service.sendWindowDockCommand(
              targetId: previous.targetId!,
              slotId: slotId,
              x: bounds.x,
              y: bounds.y,
              width: bounds.width,
              height: bounds.height,
            );
          } catch (_) {
            restored = false;
          }
        }
        _put(
          slotId,
          (restored ? previous : DesktopWindowDockState(width: previous.width))
              .copyWith(lastError: error.toString()),
        );
        if (valid() &&
            !attached &&
            targetId != previous.targetId &&
            service.isWindowOpen(targetId)) {
          await service.bringToFront(targetId);
        }
      }
      if (valid()) rethrow;
    } finally {
      _layouts.remove(slotId);
    }
  });

  Future<void> undock({required String targetId, bool showWindow = true}) =>
      _serialize(() async {
        final entries =
            state.entries
                .where((e) => e.value.targetId == targetId && e.value.isDocked)
                .toList();
        for (final entry in entries) {
          final previous = entry.value;
          final generation = _generations[targetId] ?? 0;
          _put(
            entry.key,
            previous.copyWith(
              status: WindowDockingStatus.undocking,
              clearError: true,
            ),
          );
          try {
            if (!await _service.sendWindowUndockCommand(
              targetId,
              showWindow: showWindow,
            )) {
              throw StateError('窗口弹出失败，已保留吸附区域');
            }
            if (!_disposed && generation == (_generations[targetId] ?? 0)) {
              _put(entry.key, DesktopWindowDockState(width: previous.width));
            }
          } catch (error) {
            if (!_disposed && generation == (_generations[targetId] ?? 0)) {
              _put(entry.key, previous.copyWith(lastError: error.toString()));
            }
            rethrow;
          }
        }
      });

  void windowClosed(String targetId) {
    if (_disposed) return;
    _generations[targetId] = (_generations[targetId] ?? 0) + 1;
    for (final entry in state.entries.toList()) {
      if (entry.value.targetId != targetId) continue;
      final ready = _layouts[entry.key];
      if (ready != null && !ready.isCompleted) {
        ready.completeError(StateError('窗口已关闭'));
      }
      _put(entry.key, DesktopWindowDockState(width: entry.value.width));
    }
  }

  void updateBounds(String slotId, WindowDockBounds bounds) {
    if (_disposed || bounds.width <= 0 || bounds.height <= 0) return;
    final unchanged = _bounds[slotId] == bounds;
    _bounds[slotId] = bounds;
    final ready = _layouts[slotId];
    if (ready != null && !ready.isCompleted) ready.complete(bounds);
    if (unchanged) return;
    if (slot(slotId).isDocked) unawaited(_flush(slotId));
  }

  void rejectLayout(String slotId) {
    final ready = _layouts[slotId];
    if (ready != null && !ready.isCompleted) {
      ready.completeError(StateError('窗口太窄或吸附区域不可用'));
    } else if (slot(slotId).isDocked) {
      unawaited(
        undock(targetId: slot(slotId).targetId!).catchError((Object _) {}),
      );
    }
  }

  Future<void> _flush(String slotId) async {
    if (_disposed || !_updating.add(slotId)) return;
    try {
      WindowDockBounds? sent;
      while (!_disposed && slot(slotId).isDocked && _bounds[slotId] != sent) {
        sent = _bounds[slotId];
        if (sent == null) break;
        await _service.sendWindowUpdateBoundsCommand(
          targetId: slot(slotId).targetId!,
          slotId: slotId,
          x: sent.x,
          y: sent.y,
          width: sent.width,
          height: sent.height,
        );
      }
    } catch (error) {
      if (!_disposed && slot(slotId).isDocked) {
        _put(slotId, slot(slotId).copyWith(lastError: error.toString()));
      }
    } finally {
      _updating.remove(slotId);
    }
  }

  void setWidth(String slotId, double width) =>
      _put(slotId, slot(slotId).copyWith(width: width.clamp(360.0, 960.0)));
  Future<void> closeSlot(String slotId) => _serialize(() async {
    final target = slot(slotId).targetId;
    if (target != null) await _service.closeWindow(target);
  });
  Future<void> closeTarget(String targetId) =>
      _serialize(() => _service.closeWindow(targetId));
}

final desktopWindowDockProvider = NotifierProvider<
  DesktopWindowDockNotifier,
  Map<String, DesktopWindowDockState>
>(DesktopWindowDockNotifier.new);
