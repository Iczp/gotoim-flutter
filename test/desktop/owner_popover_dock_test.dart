import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/app/router/app_router.dart';
import 'package:gotoim_flutter/features/session/application/session_list_controller.dart';
import 'package:gotoim_flutter/features/session/presentation/desktop_chat_owner_popover.dart';

class _UnusedController implements SessionListController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('opening identity popover keeps docked browser visible', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final visibility = <bool>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('gotoim/window'), (
      call,
    ) async {
      if (call.method == 'setBrowserDockVisible') {
        visibility.add((call.arguments as Map)['visible'] as bool);
      }
      return true;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('gotoim/window'),
        null,
      ),
    );
    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [DesktopDockRouteObserver()],
        home: Builder(
          builder: (context) {
            pageContext = context;
            return const Scaffold();
          },
        ),
      ),
    );
    await tester.pump();
    expect(visibility, [true]);
    // Inspect the actual route pushed by show(), before its account UI builds.
    final closed = DesktopChatOwnerPopover.show(
      pageContext,
      controller: _UnusedController(),
    );
    await tester.idle();
    expect(visibility, [true]);
    Navigator.of(pageContext).pop();
    await closed;
    await tester.pumpAndSettle();
    expect(visibility, [true]);

    // Real modal dialogs still hide the native pane and restore it on close.
    final dialog = showDialog<void>(
      context: pageContext,
      builder: (_) => const AlertDialog(title: Text('确认')),
    );
    await tester.pumpAndSettle();
    expect(visibility, [true, false]);
    final nested = DesktopChatOwnerPopover.show(
      pageContext,
      controller: _UnusedController(),
    );
    await tester.idle();
    expect(visibility, [true, false]);
    Navigator.of(pageContext).pop();
    await nested;
    await tester.pumpAndSettle();
    expect(visibility, [true, false]);
    Navigator.of(pageContext).pop();
    await dialog;
    await tester.pumpAndSettle();
    expect(visibility, [true, false, true]);
    debugDefaultTargetPlatformOverride = null;
  });
}
