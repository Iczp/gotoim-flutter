import 'package:flutter/material.dart';

/// GotoIM 专属科技感品牌 Logo 组件
///
/// 融合流线型对话气泡、量子互联星轨与多层呼吸微动自发光。
/// 支持全分辨率自适应缩放、深浅色模式自发光调和与动画暂停/恢复。
class GotoImLogo extends StatefulWidget {
  const GotoImLogo({
    super.key,
    this.size = 120.0,
    this.enableBreathing = true,
    this.glowColor,
    this.heroTag = 'app_brand_logo',
    this.onTap,
  });

  /// Logo 直径或方块边长
  final double size;

  /// 是否开启科技感呼吸微动光晕
  final bool enableBreathing;

  /// 自定义发光色（默认为电光青与极光蓝渐变高光）
  final Color? glowColor;

  /// Hero 动画标签（为 null 则禁用 Hero）
  final String? heroTag;

  /// 点击回调
  final VoidCallback? onTap;

  @override
  State<GotoImLogo> createState() => _GotoImLogoState();
}

class _GotoImLogoState extends State<GotoImLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _glowAnimation;
  late final Animation<double> _pulseScaleAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    _glowAnimation = Tween<double>(begin: 0.35, end: 0.85).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOutSine),
    );

    _pulseScaleAnimation = Tween<double>(begin: 0.98, end: 1.03).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOutSine),
    );

    if (widget.enableBreathing) {
      _animController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant GotoImLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enableBreathing != oldWidget.enableBreathing) {
      if (widget.enableBreathing) {
        _animController.repeat(reverse: true);
      } else {
        _animController.stop();
        _animController.value = 0.5;
      }
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryGlow =
        widget.glowColor ??
        (isDark ? const Color(0xFF00E5FF) : const Color(0xFF0091EA));
    final secondaryGlow =
        isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);

    Widget content = SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _animController,
        builder: (context, child) {
          final glowVal = widget.enableBreathing ? _glowAnimation.value : 0.6;
          final scaleVal =
              widget.enableBreathing ? _pulseScaleAnimation.value : 1.0;

          return Transform.scale(
            scale: scaleVal,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // 1. 底层大气弥散发光 (Ambient Diffuse Glow)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: primaryGlow.withValues(
                            alpha: isDark ? 0.28 * glowVal : 0.16 * glowVal,
                          ),
                          blurRadius: widget.size * 0.45,
                          spreadRadius: widget.size * 0.08 * glowVal,
                        ),
                        BoxShadow(
                          color: secondaryGlow.withValues(
                            alpha: isDark ? 0.20 * glowVal : 0.12 * glowVal,
                          ),
                          blurRadius: widget.size * 0.25,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),

                // 2. 核心透明高精度全息 Logo 图像
                Image.asset(
                  'assets/images/splash_logo.png',
                  width: widget.size,
                  height: widget.size,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (context, error, stackTrace) {
                    return _FallbackTechEmblem(size: widget.size);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );

    if (widget.heroTag != null) {
      content = Hero(tag: widget.heroTag!, child: content);
    }

    if (widget.onTap != null) {
      content = GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: content,
      );
    }

    return content;
  }
}

/// 当位图资源加载失败时的纯代码高保真矢量备选方案
class _FallbackTechEmblem extends StatelessWidget {
  const _FallbackTechEmblem({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xFF00E5FF), Color(0xFF0284C7), Color(0xFF0F172A)],
        ),
        border: Border.all(color: const Color(0xFF38BDF8), width: 2.0),
      ),
      child: Center(
        child: Icon(Icons.hub_rounded, size: size * 0.52, color: Colors.white),
      ),
    );
  }
}
