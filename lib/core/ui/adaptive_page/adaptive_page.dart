import 'package:flutter/material.dart';

import '../../../app/app_navigation.dart';
import 'adaptive_page_config.dart';
import 'adaptive_page_controller.dart';
import 'adaptive_page_presentation.dart';

typedef AdaptivePageBuilder = Widget Function(
    BuildContext context, AdaptivePageController controller);

abstract class AdaptivePage {
  static Future<T?> open<T>(
    BuildContext context, {
    required AdaptivePageConfig config,
    required AdaptivePageBuilder builder,
  }) {
    final effectiveContext = (rootNavigatorKey.currentContext?.mounted == true)
        ? rootNavigatorKey.currentContext!
        : context;
    final fullPageMinWidth = config.fullPageMinWidth;
    if (fullPageMinWidth != null &&
        MediaQuery.sizeOf(effectiveContext).width >= fullPageMinWidth) {
      return push<T>(effectiveContext, config: config, builder: builder);
    }
    final controller = AdaptivePageController(
      config,
      presentation: AdaptivePagePresentation.compact,
    );
    return showModalBottomSheet<T>(
      context: effectiveContext,
      useRootNavigator: config.useRootNavigator,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _AdaptiveSheetHost(
        controller: controller,
        builder: builder,
        onConvert: () {
          FocusManager.instance.primaryFocus?.unfocus();
          Navigator.of(sheetContext).pop();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final target = rootNavigatorKey.currentContext ?? context;
            if (!target.mounted) return;
            push<void>(
              target,
              config: config,
              builder: builder,
              controller: controller,
            );
          });
        },
      ),
    );
  }

  static Future<T?> push<T>(
    BuildContext context, {
    required AdaptivePageConfig config,
    required AdaptivePageBuilder builder,
    AdaptivePageController? controller,
  }) {
    final pageController = controller ??
        AdaptivePageController(
          config,
          presentation: AdaptivePagePresentation.full,
        );
    pageController.setPresentation(AdaptivePagePresentation.full);
    final navigator = rootNavigatorKey.currentState ??
        Navigator.of(context, rootNavigator: config.useRootNavigator);
    return navigator.push<T>(
      MaterialPageRoute<T>(
        settings: RouteSettings(name: '/adaptive/${config.title}'),
        builder: (pageContext) =>
            _AdaptiveFullHost(controller: pageController, builder: builder),
      ),
    );
  }
}

class _AdaptiveSheetHost extends StatefulWidget {
  const _AdaptiveSheetHost({
    required this.controller,
    required this.builder,
    required this.onConvert,
  });
  final AdaptivePageController controller;
  final AdaptivePageBuilder builder;
  final VoidCallback onConvert;
  @override
  State<_AdaptiveSheetHost> createState() => _AdaptiveSheetHostState();
}

class _AdaptiveSheetHostState extends State<_AdaptiveSheetHost> {
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  @override
  void dispose() {
    _sheetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.controller.config;
    widget.controller.bindActions(
      close: () => Navigator.of(context).pop(),
      convert: widget.onConvert,
      expand: () => _animate(config.maxChildSize),
      collapse: () => _animate(config.minChildSize),
    );
    final surface = Theme.of(context).colorScheme.surface;
    if (config.sheetSizingMode == AdaptiveSheetSizingMode.draggable) {
      return DraggableScrollableSheet(
        controller: _sheetController,
        initialChildSize: config.initialChildSize,
        minChildSize: config.minChildSize,
        maxChildSize: config.maxChildSize,
        builder: (_, scrollController) {
          widget.controller.setSheetScrollController(scrollController);
          return _SheetMaterial(
            color: surface,
            child: Column(
              children: [
                _AdaptiveHeader(controller: widget.controller),
                Expanded(
                  child: _KeyboardAwareBody(
                    child: widget.builder(context, widget.controller),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }
    widget.controller.setSheetScrollController(null);
    return FractionallySizedBox(
      heightFactor: config.maxContentHeightFactor,
      alignment: Alignment.bottomCenter,
      child: _SheetMaterial(
        color: surface,
        child: Column(
          children: [
            _AdaptiveHeader(controller: widget.controller),
            Expanded(
              child: _KeyboardAwareBody(
                child: widget.builder(context, widget.controller),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _animate(double size) {
    if (_sheetController.isAttached) {
      _sheetController.animateTo(
        size,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }
}

class _SheetMaterial extends StatelessWidget {
  const _SheetMaterial({required this.child, required this.color});
  final Widget child;
  final Color color;
  @override
  Widget build(BuildContext context) => Material(
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
}

class _AdaptiveFullHost extends StatelessWidget {
  const _AdaptiveFullHost({required this.controller, required this.builder});
  final AdaptivePageController controller;
  final AdaptivePageBuilder builder;
  @override
  Widget build(BuildContext context) {
    controller.bindActions(close: () => Navigator.of(context).pop());
    return Scaffold(
      appBar: AppBar(title: Text(controller.config.title)),
      body: builder(context, controller),
    );
  }
}

class _AdaptiveHeader extends StatelessWidget {
  const _AdaptiveHeader({required this.controller});
  final AdaptivePageController controller;
  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          Row(
            children: [
              const SizedBox(width: 48),
              Expanded(
                child: Text(
                  controller.config.title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (controller.canConvertToPage)
                IconButton(
                  tooltip: '打开完整页面',
                  onPressed: controller.toPage,
                  icon: const Icon(Icons.open_in_full),
                ),
              IconButton(
                tooltip: '关闭',
                onPressed: controller.close,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ],
      );
}

class _KeyboardAwareBody extends StatelessWidget {
  const _KeyboardAwareBody({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: child,
      );
}
