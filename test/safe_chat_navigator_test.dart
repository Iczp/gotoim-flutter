import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gotoim_flutter/app/app_navigation.dart';

void main() {
  setUp(() {
    SafeChatNavigator.resetThrottle();
  });

  testWidgets('SafeChatNavigator pushes chat route successfully', (tester) async {
    String? pushedLocation;
    final router = GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  SafeChatNavigator.pushChat(
                    context,
                    '/chat/session-123?ownerId=1&title=Test',
                  );
                },
                child: const Text('Open Chat'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/chat/:sessionUnitId',
          builder: (context, state) {
            pushedLocation = state.uri.toString();
            return Scaffold(
              appBar: AppBar(title: const Text('Chat Mock')),
              body: const Text('Chat Page Content'),
            );
          },
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('Open Chat'), findsOneWidget);
    expect(find.text('Chat Page Content'), findsNothing);

    // Tap to open chat
    await tester.tap(find.text('Open Chat'));
    await tester.pumpAndSettle();

    expect(find.text('Chat Page Content'), findsOneWidget);
    expect(pushedLocation, '/chat/session-123?ownerId=1&title=Test');
  });

  testWidgets('SafeChatNavigator throttles rapid taps within 400ms', (tester) async {
    var pushCount = 0;
    final router = GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  SafeChatNavigator.pushChat(
                    context,
                    '/chat/session-123',
                  );
                },
                child: const Text('Open Chat'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/chat/:sessionUnitId',
          builder: (context, state) {
            pushCount++;
            return const Scaffold(body: Text('Chat Mock'));
          },
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    // Fast double tap
    await tester.tap(find.text('Open Chat'));
    await tester.tap(find.text('Open Chat'));
    await tester.pumpAndSettle();

    // Only one push should have occurred
    expect(pushCount, 1);
  });

  testWidgets('SafeChatNavigator allows next navigation after pop without deadlocking', (tester) async {
    final router = GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  SafeChatNavigator.pushChat(
                    context,
                    '/chat/session-123',
                  );
                },
                child: const Text('Open Chat'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/chat/:sessionUnitId',
          builder: (context, state) => Scaffold(
            body: Column(
              children: [
                const Text('Chat Mock'),
                ElevatedButton(
                  onPressed: () => context.pop(),
                  child: const Text('Back'),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    // 1st open
    await tester.tap(find.text('Open Chat'));
    await tester.pumpAndSettle();
    expect(find.text('Chat Mock'), findsOneWidget);

    // Pop back
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Open Chat'), findsOneWidget);

    // Wait past throttle
    SafeChatNavigator.resetThrottle();

    // 2nd open must succeed (verifies no permanent lock!)
    await tester.tap(find.text('Open Chat'));
    await tester.pumpAndSettle();
    expect(find.text('Chat Mock'), findsOneWidget);
  });
}
