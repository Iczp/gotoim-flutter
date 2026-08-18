import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class ClipboardService {
  Future<void> copy(String value);

  Future<String?> read();
}

class SystemClipboardService implements ClipboardService {
  @override
  Future<void> copy(String value) =>
      Clipboard.setData(ClipboardData(text: value));

  @override
  Future<String?> read() async => (await Clipboard.getData('text/plain'))?.text;
}

final clipboardServiceProvider =
    Provider<ClipboardService>((ref) => SystemClipboardService());
