import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../../app/application_providers.dart';
import '../../../../core/config/app_environment.dart';
import '../../../auth/application/auth_controller.dart';
import '../../application/social_identity_controller.dart';

/// Streams Social media with the viewer's bearer token only to the Social origin.
class SocialVideoPlayer extends ConsumerStatefulWidget {
  const SocialVideoPlayer({super.key, required this.url, required this.active});
  final String url;
  final bool active;
  @override
  ConsumerState<SocialVideoPlayer> createState() => _SocialVideoPlayerState();
}

class _SocialVideoPlayerState extends ConsumerState<SocialVideoPlayer>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _controller?.pause();
  }

  @override
  void didUpdateWidget(SocialVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _initialize();
    } else if (!widget.active) {
      _controller?.pause();
    }
  }

  Future<void> _initialize() async {
    final generation = ++_generation;
    final previous = _controller;
    _controller = null;
    _error = null;
    if (mounted) setState(() {});
    await previous?.dispose();
    VideoPlayerController? controller;
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
        throw UnsupportedError('当前 Linux 版本暂不支持视频播放。');
      }
      final base = Uri.parse(ref.read(appEnvironmentProvider).socialApiBaseUrl);
      final raw = Uri.parse(widget.url.trim());
      var uri = base.resolveUri(raw);
      if (!['http', 'https'].contains(uri.scheme) || uri.host.isEmpty) {
        throw const FormatException();
      }
      final isSocial =
          uri.origin == base.origin &&
          uri.path.startsWith('/api/social/media-assets/download/');
      final headers = <String, String>{};
      if (isSocial) {
        if (kIsWeb) throw UnsupportedError('网页版暂不支持需要身份验证的视频播放。');
        final identity = ref.read(socialIdentityProvider);
        final actor = identity.actor?.id;
        if (identity.chatObjectId != null && actor != null) {
          // Use the existing authenticated transport to refresh an expired token
          // before handing it to the native streaming player.
          await ref
              .read(socialApiClientProvider)
              .get<dynamic>(
                '/api/social/actor/for-chat-object',
                query: {'chatObjectId': identity.chatObjectId},
              );
        }
        if (actor != null) {
          uri = uri.replace(
            queryParameters: {...uri.queryParameters, 'viewerActorId': actor},
          );
        }
        final token = await ref.read(tokenStorageProvider).readAccessToken();
        if (token != null && token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        }
      }
      if (!mounted || generation != _generation) return;
      controller = VideoPlayerController.networkUrl(uri, httpHeaders: headers);
      await controller.initialize();
      if (!mounted || generation != _generation) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      if (widget.active) await controller.play();
    } catch (error) {
      await controller?.dispose();
      if (mounted && generation == _generation) {
        setState(() {
          _controller = null;
          _error =
              error is UnsupportedError
                  ? error.message?.toString()
                  : '视频加载失败，请重试。';
        });
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      socialIdentityProvider.select(
        (value) => (value.chatObjectId, value.actor?.id),
      ),
      (previous, next) {
        if (previous != next) _initialize();
      },
    );
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.white)),
            TextButton(onPressed: _initialize, child: const Text('重试')),
          ],
        ),
      );
    }
    final controller = _controller;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
          VideoProgressIndicator(controller, allowScrubbing: true),
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: controller,
            builder:
                (context, value, _) => IconButton(
                  color: Colors.white,
                  tooltip: value.isPlaying ? '暂停' : '播放',
                  onPressed:
                      () =>
                          value.isPlaying
                              ? controller.pause()
                              : controller.play(),
                  icon: Icon(
                    value.isPlaying ? Icons.pause_circle : Icons.play_circle,
                  ),
                ),
          ),
        ],
      ),
    );
  }
}
