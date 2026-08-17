import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class ClipboardService {
  Future<void> copy(String value);
}

class SystemClipboardService implements ClipboardService {
  @override
  Future<void> copy(String value) =>
      Clipboard.setData(ClipboardData(text: value));
}

final clipboardServiceProvider =
    Provider<ClipboardService>((ref) => SystemClipboardService());
