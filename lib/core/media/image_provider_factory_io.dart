import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

ImageProvider createImageProvider(String source) {
  final uri = Uri.tryParse(source);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    return CachedNetworkImageProvider(source);
  }
  final path = uri?.scheme == 'file' ? uri!.toFilePath() : source;
  return FileImage(File(path));
}
