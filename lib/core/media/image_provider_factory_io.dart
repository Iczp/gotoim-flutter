import 'dart:io';
import 'package:flutter/widgets.dart';

ImageProvider createImageProvider(String source) {
  final uri = Uri.tryParse(source);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    return NetworkImage(source);
  }
  final path = uri?.scheme == 'file' ? uri!.toFilePath() : source;
  return FileImage(File(path));
}
