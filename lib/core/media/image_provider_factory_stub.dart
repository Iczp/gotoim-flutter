import 'dart:convert';
import 'package:flutter/widgets.dart';

ImageProvider createImageProvider(String source) {
  final trimmed = source.trim();
  if (trimmed.startsWith('data:image/')) {
    final commaIndex = trimmed.indexOf(',');
    if (commaIndex != -1) {
      try {
        final bytes = base64Decode(trimmed.substring(commaIndex + 1));
        return MemoryImage(bytes);
      } catch (_) {}
    }
  }
  if (trimmed.startsWith('assets/') || trimmed.startsWith('packages/')) {
    return AssetImage(trimmed);
  }
  return NetworkImage(trimmed);
}
