import 'package:flutter/widgets.dart';

import 'adaptive_page_config.dart';
import 'adaptive_page_presentation.dart';

class AdaptivePageController extends ChangeNotifier {
  AdaptivePageController(
    this.config, {
    required AdaptivePagePresentation presentation,
  }) : _presentation = presentation;

  final AdaptivePageConfig config;
  AdaptivePagePresentation _presentation;
  VoidCallback? _onClose;
  VoidCallback? _onConvert;
  VoidCallback? _onExpand;
  VoidCallback? _onCollapse;
  void Function(double size)? _onAnimateTo;
  ScrollController? _scrollController;
  double _currentSize = 0;

  // ── 状态读取 ──

  AdaptivePagePresentation get presentation => _presentation;

  /// Sheet 是否处于半屏紧凑模式（原名 [isCompact]）。
  bool get isSheet => _presentation == AdaptivePagePresentation.compact;

  /// Sheet 是否处于全页模式（原名 [isFull]）。
  bool get isPage => _presentation == AdaptivePagePresentation.full;

  /// @deprecated 请使用 [isSheet]。
  @Deprecated('Use isSheet instead.')
  bool get isCompact => isSheet;

  /// @deprecated 请使用 [isPage]。
  @Deprecated('Use isPage instead.')
  bool get isFull => isPage;

  bool get canConvertToPage => config.canConvertToPage;

  ScrollController? get scrollController => _scrollController;

  /// 当前 Sheet 高度占比（仅 draggable 模式有意义）。
  /// 值域 [0, 1]，非 draggable 模式时始终为 0。
  double get currentSize => _currentSize;

  // ── 动作 ──

  void close() => _onClose?.call();

  void toPage() {
    if (canConvertToPage) _onConvert?.call();
  }

  void expandSheet() => _onExpand?.call();
  void collapseSheet() => _onCollapse?.call();

  /// 将 Sheet 动画到指定高度比例 [size]，范围 [minChildSize, maxChildSize]。
  /// 非 draggable 模式或未 attach 时无操作。
  void animateTo(double size) => _onAnimateTo?.call(size);

  /// 关闭并携带返回值 [result]，等同于在 builder 里调用
  /// `Navigator.pop(context, result)`。
  void onResult<T>(T result) {
    _onClose?.call();
    // 结果通过 Future<T?> 的 completer 传递；这里只记录供外部读取。
    _lastResult = result;
    notifyListeners();
  }

  Object? _lastResult;

  /// 最近一次通过 [onResult] 提交的返回值。
  Object? get lastResult => _lastResult;

  // ── 内部绑定（由 Host Widget 调用）──

  void bindActions({
    VoidCallback? close,
    VoidCallback? convert,
    VoidCallback? expand,
    VoidCallback? collapse,
    void Function(double size)? animateTo,
  }) {
    _onClose = close;
    _onConvert = convert;
    _onExpand = expand;
    _onCollapse = collapse;
    _onAnimateTo = animateTo;
  }

  void setPresentation(AdaptivePagePresentation value) {
    if (_presentation == value) return;
    _presentation = value;
    notifyListeners();
  }

  void setSheetScrollController(ScrollController? value) {
    _scrollController = value;
  }

  void setCurrentSize(double value) {
    if (_currentSize == value) return;
    _currentSize = value;
    notifyListeners();
  }
}
