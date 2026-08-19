import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/platform_facade.dart';
import 'image_code_decoder.dart';
import 'scan_code_camera_view.dart';
import 'scan_code_controller.dart';
import 'scan_code_models.dart';

/// Full-screen, reusable scanner UI with a camera frame, animated scan line,
/// album recognition and torch controls.
class ScanCodePage extends ConsumerStatefulWidget {
  const ScanCodePage({super.key, required this.request});

  final ScanCodeRequest request;

  @override
  ConsumerState<ScanCodePage> createState() => _ScanCodePageState();
}

class _ScanCodePageState extends ConsumerState<ScanCodePage>
    with SingleTickerProviderStateMixin {
  late final ScanCodeController _controller;
  late final AnimationController _lineAnimation;

  @override
  void initState() {
    super.initState();
    _controller = ScanCodeController(
      request: widget.request,
      platform: ref.read(platformFacadeProvider),
      onResult: _finish,
      imageCodeService: ref.read(imageCodeServiceProvider),
    )..addListener(_onChanged);
    _lineAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onChanged)
      ..dispose();
    _lineAnimation.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _finish(ScanCodeResult result) {
    if (mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          ScanCodeCameraView(controller: _controller),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scanSize = math.min(constraints.maxWidth * .72, 300.0);
                return Stack(
                  children: [
                    _ScannerOverlay(size: scanSize),
                    Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              color: Colors.white,
                              tooltip: '关闭',
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            Text(widget.request.title,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 18)),
                            const SizedBox(width: 48),
                          ],
                        ),
                      ),
                    ),
                    Center(
                      child: SizedBox(
                        width: scanSize,
                        height: scanSize,
                        child: AnimatedBuilder(
                          animation: _lineAnimation,
                          builder: (context, child) => Stack(
                            children: [
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  border:
                                      Border.all(color: Colors.white, width: 2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              Positioned(
                                top: (scanSize - 3) * _lineAnimation.value,
                                left: 10,
                                right: 10,
                                child: Container(
                                  height: 3,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF22D38A),
                                    boxShadow: [
                                      BoxShadow(
                                          color: Color(0xCC22D38A),
                                          blurRadius: 12)
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment(
                          0, (scanSize / constraints.maxHeight) + .15),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          _controller.error ?? widget.request.tip,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: _controller.error == null
                                  ? Colors.white
                                  : Colors.redAccent),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 38),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.request.allowAlbum)
                              _ActionButton(
                                icon: Icons.photo_outlined,
                                label:
                                    _controller.supportsCamera ? '相册' : '上传图片',
                                loading: _controller.busy,
                                onTap: _controller.scanFromAlbum,
                              ),
                            if (_controller.supportsCamera &&
                                widget.request.allowAlbum &&
                                widget.request.allowTorch)
                              const SizedBox(width: 64),
                            if (_controller.supportsCamera &&
                                widget.request.allowTorch)
                              _ActionButton(
                                icon: _controller.torchEnabled
                                    ? Icons.flash_on
                                    : Icons.flash_off,
                                label: _controller.torchEnabled
                                    ? '关闭闪光灯'
                                    : '打开闪光灯',
                                onTap: _controller.toggleTorch,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.loading = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: loading ? null : onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            loading
                ? const SizedBox(
                    width: 30,
                    height: 30,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : Icon(icon, color: Colors.white, size: 30),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(color: Colors.white)),
          ],
        ),
      );
}

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(painter: _ScannerOverlayPainter(size)),
      );
}

class _ScannerOverlayPainter extends CustomPainter {
  const _ScannerOverlayPainter(this.size);

  final double size;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final hole = Rect.fromCenter(
      center: canvasSize.center(Offset.zero),
      width: size,
      height: size,
    );
    final overlay = Path()
      ..addRect(Offset.zero & canvasSize)
      ..addRRect(RRect.fromRectAndRadius(hole, const Radius.circular(10)));
    canvas.drawPath(
        overlay,
        Paint()
          ..color = const Color(0x99000000)
          ..blendMode = BlendMode.srcOut);
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) =>
      oldDelegate.size != size;
}
