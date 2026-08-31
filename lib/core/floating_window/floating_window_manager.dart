import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'floating_window_models.dart';

final floatingWindowManagerProvider = Provider<FloatingWindowManager>((ref) {
  final manager = FloatingWindowManager();
  ref.onDispose(manager.dispose);
  return manager;
});

class FloatingWindowManager extends ChangeNotifier {
  final Map<String, FloatingWindowEntry> _entries = {};
  final Map<String, Offset> _rememberedPositions = {};
  int _nextZIndex = 0;

  List<FloatingWindowEntry> get entries =>
      _entries.values.toList()..sort((a, b) => a.zIndex.compareTo(b.zIndex));

  bool contains(String id) => _entries.containsKey(id);
  FloatingWindowEntry? find(String id) => _entries[id];

  void show({
    required String id,
    required Widget child,
    FloatingWindowType type = FloatingWindowType.custom,
    FloatingWindowContentMode contentMode = FloatingWindowContentMode.flutter,
    FloatingWindowOptions options = const FloatingWindowOptions(),
    VoidCallback? onRestore,
  }) {
    final existing = _entries[id];
    final position =
        existing?.position ??
        (options.initialPosition ??
            _rememberedPositions[id] ??
            const Offset(16, 96));
    _entries[id] = FloatingWindowEntry(
      id: id,
      type: type,
      contentMode: contentMode,
      child: child,
      options: options,
      position: position,
      size: existing?.size ?? options.initialSize,
      visible: true,
      zIndex: ++_nextZIndex,
      onRestore: onRestore,
    );
    notifyListeners();
  }

  void hide(String id) =>
      _change(id, (entry) => entry.copyWith(visible: false));
  void showWindow(String id) => _change(
    id,
    (entry) => entry.copyWith(visible: true, zIndex: ++_nextZIndex),
  );
  void close(String id) {
    if (_entries.remove(id) != null) notifyListeners();
  }

  /// Restores a floating item to its original presentation.
  ///
  /// Returns false when the item is absent or has no restore action.
  bool restore(String id) {
    final action = _entries[id]?.onRestore;
    if (action == null) return false;
    action();
    return true;
  }

  void closeAll() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }

  void bringToFront(String id) =>
      _change(id, (entry) => entry.copyWith(zIndex: ++_nextZIndex));
  void updatePosition(String id, Offset position) {
    _rememberedPositions[id] = position;
    _change(id, (entry) => entry.copyWith(position: position));
  }

  void updateSize(String id, Size size) =>
      _change(id, (entry) => entry.copyWith(size: size));

  void _change(
    String id,
    FloatingWindowEntry Function(FloatingWindowEntry) update,
  ) {
    final entry = _entries[id];
    if (entry == null) return;
    final next = update(entry);
    if (next == entry) return;
    _entries[id] = next;
    notifyListeners();
  }
}
