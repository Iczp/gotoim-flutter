import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/logging/console_color.dart';

void main() {
  group('ConsoleColor tests', () {
    test('colorizeMessage colors errors and failures red', () {
      final res1 = colorizeMessage('[AppUpdateApi] getLatestVersion failed: network timeout');
      expect(res1.startsWith(ansiRed), isTrue);
      expect(res1.endsWith(ansiReset), isTrue);

      final res2 = colorizeMessage('Unhandled Exception: SocketException');
      expect(res2.startsWith(ansiRed), isTrue);

      final res3 = colorizeMessage('请求发生错误，连接已被重置');
      expect(res3.startsWith(ansiRed), isTrue);
    });

    test('colorizeMessage colors warnings yellow', () {
      final res1 = colorizeMessage('Warning: high memory consumption');
      expect(res1.startsWith(ansiYellow), isTrue);
      expect(res1.endsWith(ansiReset), isTrue);

      final res2 = colorizeMessage('[MiniApp:WARN] deprecated feature used');
      expect(res2.startsWith(ansiYellow), isTrue);
    });

    test('colorizeMessage colors success green', () {
      final res1 = colorizeMessage('[SignalR] Hub connected successfully');
      expect(res1.startsWith(ansiGreen), isTrue);
      expect(res1.endsWith(ansiReset), isTrue);
    });

    test('colorizeMessage leaves ordinary logs unchanged', () {
      const normalMsg = 'Navigating to session list page';
      final res = colorizeMessage(normalMsg);
      expect(res, equals(normalMsg));
    });
  });
}
