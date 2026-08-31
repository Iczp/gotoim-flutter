import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:gotoim_flutter/features/user/presentation/profile_page.dart';

const _friend = ProfileSubject(
  kind: ProfileKind.friend,
  id: 'friend-1',
  name: '小明',
  avatarUrl: '',
  subtitle: '好友',
  raw: <String, dynamic>{'code': 'xiaoming'},
);

void main() {
  setUpAll(() => dotenv.loadFromString(envString: 'APP_NAME=Test'));

  Widget launcher(Size size) => ProviderScope(
    overrides: [
      appEnvironmentProvider.overrideWithValue(
        AppEnvironment.fromDotEnv(AppFlavor.development),
      ),
    ],
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Builder(
          builder:
              (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => openProfilePage(context, subject: _friend),
                    child: const Text('打开资料'),
                  ),
                ),
              ),
        ),
      ),
    ),
  );

  testWidgets('tablet and desktop open a full formal profile page', (
    tester,
  ) async {
    await tester.pumpWidget(launcher(const Size(900, 700)));
    await tester.tap(find.text('打开资料'));
    await tester.pumpAndSettle();

    expect(find.text('好友资料'), findsOneWidget);
    expect(find.text('小明'), findsOneWidget);
    expect(find.text('xiaoming'), findsOneWidget);
    expect(find.byTooltip('打开完整页面'), findsNothing);
  });

  testWidgets('phone opens a convertible half profile page', (tester) async {
    await tester.pumpWidget(launcher(const Size(390, 800)));
    await tester.tap(find.text('打开资料'));
    await tester.pumpAndSettle();

    expect(find.text('好友资料'), findsOneWidget);
    expect(find.byTooltip('打开完整页面'), findsOneWidget);
  });
}
