import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/widgets/gotoim_logo.dart';

/// 沉浸式科技感 Splash 启动/鉴权检查页面
///
/// 具备 100% 满屏穿透（穿透系统状态栏与底部手势条）、
/// 赛博微光星网背景、自发光量子对话 Logo、阶段式科技感加载状态和超时逃生通道。
class AuthLoadingPage extends ConsumerStatefulWidget {
  const AuthLoadingPage({super.key, this.isDiagnosticsPreview = false});

  /// 是否为诊断中心内的预览模式
  final bool isDiagnosticsPreview;

  @override
  ConsumerState<AuthLoadingPage> createState() => _AuthLoadingPageState();
}

class _AuthLoadingPageState extends ConsumerState<AuthLoadingPage>
    with TickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;

  late final AnimationController _pulseProgressController;

  bool _showEscapeOptions = false;
  Timer? _escapeTimer;
  Timer? _stepTimer;
  int _currentStepIndex = 0;

  static const List<String> _loadingSteps = [
    '正在建立安全加密网络...',
    '初始化端侧本地数据引擎...',
    '验证通信凭证与会话状态...',
    '智能同步就绪，即刻开启...',
  ];

  @override
  void initState() {
    super.initState();
    if (!widget.isDiagnosticsPreview) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        FlutterNativeSplash.remove();
      });
    }

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutCubic,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeIn,
    );
    _entranceController.forward();

    _pulseProgressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _stepTimer = Timer.periodic(const Duration(milliseconds: 1100), (timer) {
      if (mounted && _currentStepIndex < _loadingSteps.length - 1) {
        setState(() => _currentStepIndex++);
      }
    });

    _escapeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _showEscapeOptions = true);
      }
    });
  }

  @override
  void dispose() {
    _escapeTimer?.cancel();
    _stepTimer?.cancel();
    _entranceController.dispose();
    _pulseProgressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    final mediaQuery = MediaQuery.of(context);
    String appName = 'Goto IM';
    String appVersion = '1.0.0';
    try {
      final env = ref.watch(appEnvironmentProvider);
      if (env.appName.isNotEmpty) appName = env.appName;
      if (env.appVersion.isNotEmpty) appVersion = env.appVersion;
    } catch (_) {}

    // 1. 全屏科技背景渐变
    final bgGradient =
        isDark
            ? const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF050811), // 顶部近黑深空
                Color(0xFF080E1C),
                Color(0xFF0A1224), // 中部微光沉浸
                Color(0xFF050811), // 底部深空收尾
              ],
              stops: [0.0, 0.35, 0.70, 1.0],
            )
            : const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFF8FAFC),
                Color(0xFFEDF2F9),
                Color(0xFFE2EAF5),
                Color(0xFFF8FAFC),
              ],
              stops: [0.0, 0.35, 0.75, 1.0],
            );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF050811) : const Color(0xFFF8FAFC),
        body: SizedBox.expand(
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: bgGradient),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // ── A. 赛博微光星网与网格粒子画布 (完全满屏物理穿透) ───────────────
                CustomPaint(
                  painter: _TechSplashBackgroundPainter(isDark: isDark),
                  size: Size.infinite,
                ),

                // ── B. 氛围光晕散布 (Top-Left & Bottom-Right) ───────────────────
                Positioned(
                  top: -60,
                  left: -60,
                  child: Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (isDark
                                  ? const Color(0xFF00E5FF)
                                  : const Color(0xFF0284C7))
                              .withValues(alpha: isDark ? 0.16 : 0.09),
                          blurRadius: 130,
                          spreadRadius: 40,
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  bottom: -80,
                  right: -80,
                  child: Container(
                    width: 320,
                    height: 320,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (isDark
                                  ? const Color(0xFF6366F1)
                                  : const Color(0xFF38BDF8))
                              .withValues(alpha: isDark ? 0.15 : 0.08),
                          blurRadius: 150,
                          spreadRadius: 45,
                        ),
                      ],
                    ),
                  ),
                ),

                // ── C. 核心主内容区 (自适应垂直居中) ─────────────────────────────
                Center(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: math.max(32, mediaQuery.padding.top + 20),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 1. 全息量子科技 Logo
                          ScaleTransition(
                            scale: _scaleAnimation,
                            child: FadeTransition(
                              opacity: _fadeAnimation,
                              child: const GotoImLogo(
                                size: 140,
                                enableBreathing: true,
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),

                          // 2. 品牌字型与科技副标
                          FadeTransition(
                            opacity: _fadeAnimation,
                            child: Column(
                              children: [
                                Text(
                                  appName,
                                  style: theme.textTheme.headlineLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 2.2,
                                        color:
                                            isDark
                                                ? Colors.white
                                                : const Color(0xFF0F172A),
                                      ),
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    color: (isDark
                                            ? const Color(0xFF00E5FF)
                                            : colorScheme.primary)
                                        .withValues(
                                          alpha: isDark ? 0.10 : 0.07,
                                        ),
                                    border: Border.all(
                                      color: (isDark
                                              ? const Color(0xFF00E5FF)
                                              : colorScheme.primary)
                                          .withValues(alpha: 0.22),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    '跨平台即时通讯 · 智能互联',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color:
                                          isDark
                                              ? const Color(0xFF38BDF8)
                                              : colorScheme.primary,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 52),

                          // 3. 科技感光流脉冲进度条
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 220),
                            child: AnimatedBuilder(
                              animation: _pulseProgressController,
                              builder: (context, child) {
                                final pulse = _pulseProgressController.value;
                                return Container(
                                  height: 3.5,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(3),
                                    color:
                                        isDark
                                            ? const Color(0xFF1E293B)
                                            : const Color(0xFFE2E8F0),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: FractionallySizedBox(
                                    alignment: Alignment(
                                      -1.0 + (pulse * 2.0),
                                      0.0,
                                    ),
                                    widthFactor: 0.45,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(3),
                                        gradient: LinearGradient(
                                          colors: [
                                            (isDark
                                                    ? const Color(0xFF00E5FF)
                                                    : colorScheme.primary)
                                                .withValues(alpha: 0.2),
                                            isDark
                                                ? const Color(0xFF00E5FF)
                                                : colorScheme.primary,
                                            isDark
                                                ? const Color(0xFF38BDF8)
                                                : const Color(0xFF0284C7),
                                            (isDark
                                                    ? const Color(0xFF00E5FF)
                                                    : colorScheme.primary)
                                                .withValues(alpha: 0.2),
                                          ],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: (isDark
                                                    ? const Color(0xFF00E5FF)
                                                    : colorScheme.primary)
                                                .withValues(alpha: 0.6),
                                            blurRadius: 6,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 18),

                          // 4. 动态阶段文字提示
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 350),
                            transitionBuilder: (child, animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0.0, 0.3),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              );
                            },
                            child: Text(
                              _loadingSteps[_currentStepIndex],
                              key: ValueKey<int>(_currentStepIndex),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color:
                                    isDark
                                        ? const Color(0xFF64748B)
                                        : const Color(0xFF94A3B8),
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),

                          // 5. 超时逃生通道 (超过 3 秒未跳转时优雅淡入)
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 500),
                            child:
                                _showEscapeOptions
                                    ? Padding(
                                      key: const ValueKey('escape_actions'),
                                      padding: const EdgeInsets.only(top: 36),
                                      child: Column(
                                        children: [
                                          FilledButton.tonal(
                                            style: FilledButton.styleFrom(
                                              backgroundColor: (isDark
                                                      ? const Color(0xFF1E293B)
                                                      : const Color(0xFFE2E8F0))
                                                  .withValues(alpha: 0.8),
                                              foregroundColor:
                                                  isDark
                                                      ? Colors.white
                                                      : const Color(0xFF0F172A),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 26,
                                                    vertical: 12,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                              ),
                                            ),
                                            onPressed: () {
                                              if (widget.isDiagnosticsPreview) {
                                                Navigator.of(context).pop();
                                              } else {
                                                context.go('/login');
                                              }
                                            },
                                            child: Text(
                                              widget.isDiagnosticsPreview
                                                  ? '返回诊断中心'
                                                  : '前往登录页',
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          if (!widget.isDiagnosticsPreview)
                                            TextButton.icon(
                                              onPressed:
                                                  () => context.go(
                                                    '/diagnostics',
                                                  ),
                                              icon: const Icon(
                                                Icons.build_circle_outlined,
                                                size: 17,
                                              ),
                                              label: const Text('打开开发诊断中心'),
                                              style: TextButton.styleFrom(
                                                foregroundColor:
                                                    isDark
                                                        ? const Color(
                                                          0xFF94A3B8,
                                                        )
                                                        : const Color(
                                                          0xFF64748B,
                                                        ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    )
                                    : const SizedBox.shrink(
                                      key: ValueKey('empty_escape'),
                                    ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── D. 底部安全通信标志 (吸附底部手势安全区) ─────────────────────
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: math.max(16, mediaQuery.padding.bottom + 8),
                  child: Center(
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            size: 13,
                            color:
                                isDark
                                    ? const Color(0xFF475569)
                                    : const Color(0xFF94A3B8),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '$appName · 端到端安全加密通信  v$appVersion',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color:
                                  isDark
                                      ? const Color(0xFF475569)
                                      : const Color(0xFF94A3B8),
                              fontSize: 11.5,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 赛博科技微光星网与节点拓扑背景绘制器
class _TechSplashBackgroundPainter extends CustomPainter {
  const _TechSplashBackgroundPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint =
        Paint()
          ..color = (isDark ? const Color(0xFF00E5FF) : const Color(0xFF0284C7))
              .withValues(alpha: isDark ? 0.035 : 0.025)
          ..strokeWidth = 0.8
          ..style = PaintingStyle.stroke;

    const double step = 48.0;

    // 1. 细密矩阵坐标网格
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // 2. 拓扑数据微节点
    final nodePaint =
        Paint()
          ..color = (isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7))
              .withValues(alpha: isDark ? 0.20 : 0.12)
          ..style = PaintingStyle.fill;

    // 固定伪随机节点群（避免每帧随机计算）
    final nodes = [
      Offset(size.width * 0.15, size.height * 0.18),
      Offset(size.width * 0.28, size.height * 0.24),
      Offset(size.width * 0.82, size.height * 0.16),
      Offset(size.width * 0.75, size.height * 0.28),
      Offset(size.width * 0.12, size.height * 0.72),
      Offset(size.width * 0.25, size.height * 0.82),
      Offset(size.width * 0.85, size.height * 0.75),
      Offset(size.width * 0.72, size.height * 0.85),
    ];

    for (final node in nodes) {
      canvas.drawCircle(node, 2.2, nodePaint);
    }

    // 3. 节点互联数据线
    final linePaint =
        Paint()
          ..color = (isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7))
              .withValues(alpha: isDark ? 0.07 : 0.04)
          ..strokeWidth = 0.9;

    canvas.drawLine(nodes[0], nodes[1], linePaint);
    canvas.drawLine(nodes[2], nodes[3], linePaint);
    canvas.drawLine(nodes[4], nodes[5], linePaint);
    canvas.drawLine(nodes[6], nodes[7], linePaint);
  }

  @override
  bool shouldRepaint(covariant _TechSplashBackgroundPainter oldDelegate) {
    return oldDelegate.isDark != isDark;
  }
}
