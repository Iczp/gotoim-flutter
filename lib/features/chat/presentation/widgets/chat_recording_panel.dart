import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 语音录制全屏浮层面板组件（ChatRecordingPanel）
///
/// 核心职责：
/// 1. 实时展示麦克风录音动态声波柱状图 [VoiceWavePainter]；
/// 2. 录音计时展示（正常计时 / 剩余 5 秒倒计时提示）；
/// 3. 手势上滑取消状态（背景变红、文字提示切换为“松开手指，取消发送”）。
class ChatRecordingPanel extends StatelessWidget {
  const ChatRecordingPanel({
    required this.levelPercentages,
    required this.visualConfig,
    required this.duration,
    required this.cancelling,
    super.key,
  });

  /// 实时声波柱状高度百分比滑动窗口列表（24 个采样点）
  final List<double> levelPercentages;

  /// 声波可视化过滤与映射配置
  final VoiceWaveVisualConfig visualConfig;

  /// 当前已录制时长
  final Duration duration;

  /// 手势是否上滑处于“取消录音”状态
  final bool cancelling;


  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final seconds = duration.inSeconds;
    return Container(
      height: 142,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 12),
      decoration: BoxDecoration(
        color:
            cancelling
                ? colorScheme.errorContainer.withValues(alpha: 0.96)
                : colorScheme.inverseSurface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Colors.black26,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          Expanded(
            child: CustomPaint(
              painter: VoiceWavePainter(
                levelPercentages: levelPercentages,
                visualConfig: visualConfig,
                color:
                    cancelling
                        ? colorScheme.error
                        : colorScheme.onInverseSurface,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            cancelling
                ? '松开手指，取消发送'
                : seconds >= 55
                ? '还可以说 ${60 - seconds} 秒'
                : '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
                    '${(seconds % 60).toString().padLeft(2, '0')}  上滑取消',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color:
                  cancelling
                      ? colorScheme.onErrorContainer
                      : colorScheme.onInverseSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for voice input waveform bars.
class VoiceWavePainter extends CustomPainter {
  const VoiceWavePainter({
    required this.levelPercentages,
    required this.visualConfig,
    required this.color,
  });

  final List<double> levelPercentages;
  final VoiceWaveVisualConfig visualConfig;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (levelPercentages.isEmpty || size.isEmpty) return;
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round;
    final step = size.width / levelPercentages.length;
    final center = size.height / 2;
    for (var index = 0; index < levelPercentages.length; index++) {
      final normalized = (levelPercentages[index] / 100).clamp(0.0, 1.0);
      final minHeight = visualConfig.idleBarHeight;
      final maxHeight = math.min(
        visualConfig.peakBarHeight,
        size.height * 0.98,
      );
      final height = minHeight + normalized * (maxHeight - minHeight);
      final x = step * (index + 0.5);
      canvas.drawLine(
        Offset(x, center - height / 2),
        Offset(x, center + height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(VoiceWavePainter oldDelegate) => true;
}

/// Configuration for voice waveform animation scaling.
class VoiceWaveVisualConfig {
  const VoiceWaveVisualConfig({
    required this.inputFloorPercent,
    required this.inputPeakPercent,
    this.idleBarHeight = 5,
    this.peakBarHeight = 80,
  }) : assert(inputFloorPercent >= 0),
       assert(inputPeakPercent > inputFloorPercent),
       assert(inputPeakPercent <= 100),
       assert(idleBarHeight > 0),
       assert(peakBarHeight >= idleBarHeight);

  final double inputFloorPercent;
  final double inputPeakPercent;
  final double idleBarHeight;
  final double peakBarHeight;

  double mapInput(double inputPercent) => ((inputPercent - inputFloorPercent) /
          (inputPeakPercent - inputFloorPercent) *
          100)
      .clamp(0.0, 100.0);
}
