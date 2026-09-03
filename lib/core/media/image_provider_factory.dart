import 'package:flutter/widgets.dart';

import 'image_provider_factory_stub.dart'
    if (dart.library.io) 'image_provider_factory_io.dart'
    as platform;

/// 根据给定的媒体来源（本地文件绝对路径或远程网络 URL）创建对应的 [ImageProvider]。
ImageProvider createImageProvider(String source) =>
    platform.createImageProvider(source);
