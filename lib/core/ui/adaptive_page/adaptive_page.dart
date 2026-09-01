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
      useSafeArea: config.useSafeArea,
      isDismissible: config.isDismissible,
      enableDrag: config.enableDrag,
      backgroundColor: Colors.transparent,
      barrierColor: config.barrierColor,
      elevation: config.elevation,
      shape: config.shape,
      clipBehavior: config.clipBehavior,
      constraints: config.constraints,
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
            shape: config.shape,
            elevation: config.elevation,
            clipBehavior: config.clipBehavior,
            child: Column(
              children: [
                _buildHeader(context),
                Expanded(
                  child: _KeyboardAwareBody(
                    behavior: config.keyboardBehavior,
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
      final heightFactor = config.maxContentHeightFactor;

      if (heightFactor != null) {
        // 固定高度比例模式
        sheetContent = FractionallySizedBox(
          heightFactor: heightFactor,
          alignment: Alignment.bottomCenter,
          child: _SheetMaterial(
            color: surface,
            borderRadius: config.sheetBorderRadius,
            shape: config.shape,
            elevation: config.elevation,
            clipBehavior: config.clipBehavior,
            child: Column(
              children: [
                _buildHeader(context),
                Expanded(
                  child: _KeyboardAwareBody(
                    behavior: config.keyboardBehavior,
                    child: widget.builder(context, widget.controller),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        // 自适应内容高度模式 (Wrap Content)
        sheetContent = _SheetMaterial(
          color: surface,
          borderRadius: config.sheetBorderRadius,
          shape: config.shape,
          elevation: config.elevation,
          clipBehavior: config.clipBehavior,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(context),
              _KeyboardAwareBody(
                behavior: config.keyboardBehavior,
                child: widget.builder(context, widget.controller),
              ),
            ],
          ),
        );
      }
    }

    // 尺寸约束 (constraints 优先，其次 maxWidth)
    if (config.constraints != null) {
      sheetContent = Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: config.constraints!,
          child: sheetContent,
        ),
      );
    } else if (config.maxWidth != null) {
      sheetContent = Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: config.maxWidth!),
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
    this.shape,
    this.elevation,
    this.clipBehavior = Clip.antiAlias,
  });
  final Widget child;
  final Color color;
  final double borderRadius;
  final ShapeBorder? shape;
  final double? elevation;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final effectiveShape = shape ??
        RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(borderRadius)),
        );

    return Material(
      color: color,
      shape: effectiveShape,
      elevation: elevation ?? 0.0,
      clipBehavior: clipBehavior,
      child: child,
    );
  }
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
    final handleSize = config.dragHandleSize ?? const Size(36, 4);
    final handleColor = config.dragHandleColor ??
        Theme.of(context).colorScheme.outlineVariant;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 拖拽指示条
        if (config.showDragHandle)
          Container(
            width: handleSize.width,
            height: handleSize.height,
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            decoration: BoxDecoration(
              color: handleColor,
              borderRadius: BorderRadius.circular(handleSize.height),
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
  const _KeyboardAwareBody({
    required this.child,
    required this.behavior,
  });
  final Widget child;
  final AdaptiveKeyboardBehavior behavior;

  @override
  Widget build(BuildContext context) {
    if (behavior == AdaptiveKeyboardBehavior.overlay) {
      return child;
    }
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: child,
    );
  }
}
