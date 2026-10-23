import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/native_window/desktop_window_loading.dart';

void main() {
  testWidgets('show preparation waits for native raster acknowledgement', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final raster = Completer<bool>();
    final methods = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('gotoim/window'), (
      call,
    ) async {
      methods.add(call.method);
      return raster.future;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('gotoim/window'),
        null,
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(home: DesktopWindowLoading(message: '正在打开窗口…')),
    );
    var ready = false;
    final preparation = prepareDesktopWindowFrame().then((_) => ready = true);
    await tester.pump();
    expect(find.text('正在打开窗口…'), findsOneWidget);
    expect(methods, ['prepareFrame']);
    expect(ready, isFalse);
    raster.complete(true);
    await tester.pump();
    await preparation;
    expect(ready, isTrue);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
}
