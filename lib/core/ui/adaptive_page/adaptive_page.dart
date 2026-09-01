import 'package:flutter/material.dart';

import '../../../app/app_navigation.dart';
import 'adaptive_page_config.dart';
import 'adaptive_page_controller.dart';
import 'adaptive_page_presentation.dart';

typedef AdaptivePageBuilder = Widget Function(
    BuildContext context, AdaptivePageController controller);

abstract class AdaptivePage {
  /// 根据屏幕宽度自适应打开：宽屏走全页路由，其余以 Sheet 打开。
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
      return page<T>(effectiveContext, config: config, builder: builder);
    }
    return sheet<T>(effectiveContext, config: config, builder: builder);
  }

  /// 强制以 Sheet 打开，忽略 [AdaptivePageConfig.fullPageMinWidth]。
  static Future<T?> sheet<T>(
    BuildContext context, {
    required AdaptivePageConfig config,
    required AdaptivePageBuilder builder,
  }) {
    final controller = AdaptivePageController(
      config,
      presentation: AdaptivePagePresentation.compact,
    );
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: config.useRootNavigator,
      isScrollControlled: true,
      useSafeArea: false,
      isDismissible: config.isDismissible,
      enableDrag: config.enableDrag,
      backgroundColor: Colors.transparent,
      barrierColor: config.barrierColor,
      sheetAnimationStyle: config.animationStyle,
      routeSettings: config.routeSettings,
      builder: (sheetContext) => _AdaptiveSheetHost(
        controller: controller,
        builder: builder,
        onConvert: () {
          FocusManager.instance.primaryFocus?.unfocus();
          Navigator.of(sheetContext).pop();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final target = rootNavigatorKey.currentContext ?? context;
            if (!target.mounted) return;
            page<void>(
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

  /// 强制以全页路由打开（原 [push]，现保留为别名）。
  static Future<T?> page<T>(
    BuildContext context, {
    required AdaptivePageConfig config,
    required AdaptivePageBuilder builder,
    AdaptivePageController? controller,
  }) {
    return push<T>(context, config: config, builder: builder, controller: controller);
  }

  /// 推入一个全页路由。
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
        settings: config.routeSettings ??
            RouteSettings(name: '/adaptive/${config.title}'),
        builder: (pageContext) =>
            _AdaptiveFullHost(controller: pageController, builder: builder),
      ),
    );
  }
}

// ── Sheet Host ──────────────────────────────────────────────────────────────

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
  void initState() {
    super.initState();
    _sheetController.addListener(_onSheetSizeChanged);
  }

  void _onSheetSizeChanged() {
    if (_sheetController.isAttached) {
      widget.controller.setCurrentSize(_sheetController.size);
    }
  }

  @override
  void dispose() {
    _sheetController.removeListener(_onSheetSizeChanged);
    _sheetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.controller.config;
    final surface =
        config.backgroundColor ?? Theme.of(context).colorScheme.surface;

    widget.controller.bindActions(
      close: () => Navigator.of(context).pop(),
      convert: widget.onConvert,
      expand: () => _animate(config.maxChildSize),
      collapse: () => _animate(config.minChildSize),
      animateTo: _animate,
    );

    Widget sheetContent;

    if (config.sheetSizingMode == AdaptiveSheetSizingMode.draggable) {
      sheetContent = DraggableScrollableSheet(
        controller: _sheetController,
        initialChildSize: config.initialChildSize,
        minChildSize: config.minChildSize,
        maxChildSize: config.maxChildSize,
        builder: (_, scrollController) {
          widget.controller.setSheetScrollController(scrollController);
          return _SheetMaterial(
            color: surface,
            borderRadius: config.sheetBorderRadius,
            child: Column(
              children: [
                _buildHeader(context),
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
    } else {
      widget.controller.setSheetScrollController(null);
      sheetContent = FractionallySizedBox(
        heightFactor: config.maxContentHeightFactor,
        alignment: Alignment.bottomCenter,
        child: _SheetMaterial(
          color: surface,
          borderRadius: config.sheetBorderRadius,
          child: Column(
            children: [
              _buildHeader(context),
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

    // maxWidth constraint
    final maxWidth = config.maxWidth;
    if (maxWidth != null) {
      sheetContent = Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: sheetContent,
        ),
      );
    }

    return sheetContent;
  }

  Widget _buildHeader(BuildContext context) {
    final config = widget.controller.config;
    if (config.headerBuilder != null) {
      return config.headerBuilder!(context, widget.controller);
    }
    return _AdaptiveHeader(controller: widget.controller);
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

// ── Full-page Host ───────────────────────────────────────────────────────────

class _AdaptiveFullHost extends StatelessWidget {
  const _AdaptiveFullHost({required this.controller, required this.builder});
  final AdaptivePageController controller;
  final AdaptivePageBuilder builder;
  @override
  Widget build(BuildContext context) {
    final config = controller.config;
    controller.bindActions(close: () => Navigator.of(context).pop());
    return Scaffold(
      backgroundColor: config.backgroundColor,
      appBar: AppBar(
        title: Text(config.title),
        actions: [
          ...config.trailingActions,
        ],
        leading: config.leadingAction,
      ),
      body: builder(context, controller),
    );
  }
}

// ── Sheet Material ───────────────────────────────────────────────────────────

class _SheetMaterial extends StatelessWidget {
  const _SheetMaterial({
    required this.child,
    required this.color,
    required this.borderRadius,
  });
  final Widget child;
  final Color color;
  final double borderRadius;

  @override
  Widget build(BuildContext context) => Material(
        color: color,
        borderRadius: BorderRadius.vertical(top: Radius.circular(borderRadius)),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
}

// ── Adaptive Header ──────────────────────────────────────────────────────────

class _AdaptiveHeader extends StatelessWidget {
  const _AdaptiveHeader({required this.controller});
  final AdaptivePageController controller;

  @override
  Widget build(BuildContext context) {
    final config = controller.config;
    final showConvert =
        config.showConvertButton ?? config.canConvertToPage;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 拖拽指示条
        if (config.showDragHandle)
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        // 标题栏
        Row(
          children: [
            // 左侧：自定义 leading 或占位
            if (config.leadingAction != null)
              config.leadingAction!
            else
              const SizedBox(width: 48),
            // 标题（居中）
            Expanded(
              child: Text(
                config.title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            // 右侧：额外 actions
            ...config.trailingActions,
            // 右侧：转换按钮
            if (showConvert && controller.canConvertToPage)
              IconButton(
                tooltip: '打开完整页面',
                onPressed: controller.toPage,
                icon: const Icon(Icons.open_in_full),
              ),
            // 右侧：关闭按钮
            if (config.showCloseButton)
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
}

// ── Keyboard Aware Body ──────────────────────────────────────────────────────

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
