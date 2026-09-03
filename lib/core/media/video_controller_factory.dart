import 'package:video_player/video_player.dart';

import 'video_controller_factory_stub.dart'
    if (dart.library.io) 'video_controller_factory_io.dart'
    as platform;

/// 根据给定的媒体来源（本地文件绝对路径或远程网络 URL）创建对应的 [VideoPlayerController]。
VideoPlayerController createVideoController(String source) =>
    platform.createVideoController(source);
