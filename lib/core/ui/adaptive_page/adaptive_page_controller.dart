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
  ScrollController? _scrollController;

  AdaptivePagePresentation get presentation => _presentation;
  bool get isCompact => _presentation == AdaptivePagePresentation.compact;
  bool get isFull => _presentation == AdaptivePagePresentation.full;
  bool get canConvertToPage => config.canConvertToPage;
  ScrollController? get scrollController => _scrollController;

  void close() => _onClose?.call();
  void toPage() {
    if (canConvertToPage) _onConvert?.call();
  }

  void expandSheet() => _onExpand?.call();
  void collapseSheet() => _onCollapse?.call();

  void bindActions({
    VoidCallback? close,
    VoidCallback? convert,
    VoidCallback? expand,
    VoidCallback? collapse,
  }) {
    _onClose = close;
    _onConvert = convert;
    _onExpand = expand;
    _onCollapse = collapse;
  }

  void setPresentation(AdaptivePagePresentation value) {
    if (_presentation == value) return;
    _presentation = value;
    notifyListeners();
  }

  void setSheetScrollController(ScrollController? value) {
    _scrollController = value;
  }
}
