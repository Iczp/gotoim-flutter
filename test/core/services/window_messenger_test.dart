import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/services/window_messenger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WindowMessenger Tests (Electron Mitt-style)', () {
    late DefaultWindowMessenger mainMessenger;
    late DefaultWindowMessenger subMessenger;

    setUp(() {
      mainMessenger = DefaultWindowMessenger(isMainWindow: true, currentWindowId: 0);
      subMessenger = DefaultWindowMessenger(isMainWindow: false, currentWindowId: 1);
    });

    tearDown(() {
      mainMessenger.dispose();
      subMessenger.dispose();
    });

    test('Initial window state', () {
      expect(mainMessenger.isMainWindow, isTrue);
      expect(subMessenger.isMainWindow, isFalse);
      expect(mainMessenger.currentWindowId, 0);
      expect(subMessenger.currentWindowId, 1);
    });

    test('on, emit, and off locally within window', () async {
      final received = <dynamic>[];
      void handler(dynamic data) => received.add(data);

      mainMessenger.on(WindowEvents.chatMessageReceived, handler);
      await mainMessenger.emit(WindowEvents.chatMessageReceived, {'id': 'msg_1', 'text': 'Hello'});

      expect(received.length, 1);
      expect(received.first, {'id': 'msg_1', 'text': 'Hello'});

      // Test off
      mainMessenger.off(WindowEvents.chatMessageReceived, handler);
      await mainMessenger.emit(WindowEvents.chatMessageReceived, {'id': 'msg_2'});

      expect(received.length, 1); // Not called again
    });

    test('Sub-window register, broadcast, and unregister', () async {
      mainMessenger.registerSubWindow(1);
      mainMessenger.registerSubWindow(2);

      final events = <dynamic>[];
      mainMessenger.on(WindowEvents.sessionUpdated, events.add);

      await mainMessenger.broadcast(WindowEvents.sessionUpdated, {'ownerId': 13});
      expect(events.length, 1);

      mainMessenger.unregisterSubWindow(1);
    });
  });
}
