import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/chat_controller.dart';
import '../../data/models/chat_message.dart';

/// Displays a voice message, including download and playback state.
class VoiceMessageContent extends ConsumerWidget {
  const VoiceMessageContent({
    required this.message,
    required this.onOpened,
    super.key,
  });

  final ChatMessage message;
  final Future<void> Function() onOpened;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seconds = (message.audioDuration.inMilliseconds / 1000).ceil();
    final playback = ref.watch(audioPlaybackServiceProvider);
    final playing = playback.isMessagePlaying(message.localId);
    final downloading = playback.downloadingMessageId == message.localId;
    final progress =
        playback.activeMessageId == message.localId &&
                playback.duration.inMilliseconds > 0
            ? playback.position.inMilliseconds /
                playback.duration.inMilliseconds
            : 0.0;
    final playedProgress = progress.clamp(0.0, 1.0);
    final colorScheme = Theme.of(context).colorScheme;
    final baseColor =
        message.isMine
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest;
    final playedColor =
        message.isMine
            ? colorScheme.primary.withValues(alpha: .22)
            : colorScheme.primaryContainer.withValues(alpha: .78);
    return InkWell(
      onTap:
          message.state == 'sending'
              ? null
              : () async {
                try {
                  await playback.toggle(
                    messageId: message.localId,
                    localPath: message.localFilePath,
                    url: message.audioUrl,
                    mimeType: message.content['contentType']?.toString(),
                  );
                  if (playback.isMessagePlaying(message.localId)) {
                    await onOpened();
                  }
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('语音播放失败：$error')));
                  }
                }
              },
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: (96.0 + seconds.clamp(0, 30) * 3).clamp(96.0, 186.0),
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned(
              left: -13,
              top: -9,
              right: -13,
              bottom: -9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ColoredBox(
                  color: baseColor,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: playedProgress,
                      child: ColoredBox(color: playedColor),
                    ),
                  ),
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children:
                      message.isMine
                          ? <Widget>[
                            if (message.state == 'sending')
                              const SizedBox.square(
                                dimension: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.8,
                                ),
                              ),
                            Expanded(
                              child: Text(
                                seconds <= 0 ? '语音' : '$seconds″',
                                textAlign: TextAlign.right,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Transform.flip(
                              flipX: true,
                              child:
                                  downloading
                                      ? const _VoiceDownloadIndicator()
                                      : _VoicePlaybackIcon(playing: playing),
                            ),
                          ]
                          : <Widget>[
                            downloading
                                ? const _VoiceDownloadIndicator()
                                : _VoicePlaybackIcon(playing: playing),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(seconds <= 0 ? '语音' : '$seconds″'),
                            ),
                            if (message.state == 'sending')
                              const SizedBox.square(
                                dimension: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.8,
                                ),
                              ),
                          ],
                ),
                if (!message.isOpened && !message.isMine)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(top: 3),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceDownloadIndicator extends StatelessWidget {
  const _VoiceDownloadIndicator();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 24,
    child: Padding(
      padding: EdgeInsets.all(3),
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
  );
}

class _VoicePlaybackIcon extends StatefulWidget {
  const _VoicePlaybackIcon({required this.playing});
  final bool playing;

  @override
  State<_VoicePlaybackIcon> createState() => _VoicePlaybackIconState();
}

class _VoicePlaybackIconState extends State<_VoicePlaybackIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _VoicePlaybackIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing == oldWidget.playing) return;
    if (widget.playing) {
      _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder:
        (context, _) => CustomPaint(
          size: const Size(24, 24),
          painter: _PlaybackWavePainter(
            color:
                IconTheme.of(context).color ??
                Theme.of(context).colorScheme.onSurface,
            waveCount: widget.playing ? (_controller.value * 3).floor() + 1 : 3,
          ),
        ),
  );
}

class _PlaybackWavePainter extends CustomPainter {
  const _PlaybackWavePainter({required this.color, required this.waveCount});
  final Color color;
  final int waveCount;

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
    canvas.drawCircle(
      Offset(5, size.height / 2),
      1.8,
      paint..style = PaintingStyle.fill,
    );
    paint.style = PaintingStyle.stroke;
    for (var index = 0; index < waveCount.clamp(1, 3); index++) {
      final radius = 5.0 + index * 4;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(5, size.height / 2), radius: radius),
        -0.72,
        1.44,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PlaybackWavePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.waveCount != waveCount;
}
