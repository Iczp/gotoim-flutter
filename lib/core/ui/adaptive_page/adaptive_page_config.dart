import 'package:flutter/material.dart';

import 'adaptive_page_presentation.dart';

@immutable
class AdaptivePageConfig {
  const AdaptivePageConfig({
    required this.title,
    this.canConvertToPage = true,
    this.sheetSizingMode = AdaptiveSheetSizingMode.content,
    this.maxContentHeightFactor = .75,
    this.initialChildSize = .60,
    this.minChildSize = .40,
    this.maxChildSize = .95,
    this.useRootNavigator = true,
    this.fullPageMinWidth,
  })  : assert(maxContentHeightFactor > 0 && maxContentHeightFactor <= 1),
        assert(initialChildSize > 0 && initialChildSize <= 1),
        assert(minChildSize > 0 && minChildSize <= initialChildSize),
        assert(maxChildSize >= initialChildSize && maxChildSize <= 1);

  final String title;
  final bool canConvertToPage;
  final AdaptiveSheetSizingMode sheetSizingMode;
  final double maxContentHeightFactor;
  final double initialChildSize;
  final double minChildSize;
  final double maxChildSize;
  final bool useRootNavigator;

  /// At or above this width [AdaptivePage.open] uses a regular page route.
  /// Smaller layouts still begin as a half page and can be expanded manually.
  final double? fullPageMinWidth;
}
