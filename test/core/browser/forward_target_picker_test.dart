import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:gotoim_flutter/core/widgets/target_picker/forward_target_picker.dart';
import 'package:gotoim_flutter/features/session/data/models/session_summary.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => dotenv.loadFromString(
      envString: 'APP_NAME=Test\nAPI_BASE_URL=https://api.test.com'));

  group('ForwardTargetPicker', () {
    testWidgets('pickSingleTarget returns the tapped session without sending any message',
        (tester) async {
      final sessionA = SessionSummary.fromJson(const {
        'id': 'unit-1',
        'title': '测试好友A',
      });
      final sessionB = SessionSummary.fromJson(const {
        'id': 'unit-2',
        'title': '测试群聊B',
      });

      SessionSummary? pickedResult;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appEnvironmentProvider.overrideWithValue(
              AppEnvironment.fromDotEnv(AppFlavor.development),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () async {
                      pickedResult = await ForwardTargetPicker.pickSingleTarget(
                        context: context,
                        sessions: [sessionA, sessionB],
                        title: '选择转发',
                      );
                    },
                    child: const Text('打开选择器'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开选择器'));
      await tester.pumpAndSettle();

      // Selector sheet is visible
      expect(find.text('测试好友A'), findsOneWidget);
      expect(find.text('测试群聊B'), findsOneWidget);

      // Tap on item
      await tester.tap(find.text('测试好友A'));
      await tester.pumpAndSettle();

      // Target is selected and returned directly
      expect(pickedResult, isNotNull);
      expect(pickedResult!.id, 'unit-1');
      expect(pickedResult!.title, '测试好友A');
    });

    testWidgets('pickTargets filters out excludeSessionUnitId', (tester) async {
      final sessionA = SessionSummary.fromJson(const {
        'id': 'unit-1',
        'title': '当前聊天',
      });
      final sessionB = SessionSummary.fromJson(const {
        'id': 'unit-2',
        'title': '其他聊天',
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appEnvironmentProvider.overrideWithValue(
              AppEnvironment.fromDotEnv(AppFlavor.development),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () {
                      ForwardTargetPicker.pickTargets(
                        context: context,
                        sessions: [sessionA, sessionB],
                        excludeSessionUnitId: 'unit-1',
                      );
                    },
                    child: const Text('排除当前'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('排除当前'));
      await tester.pumpAndSettle();

      expect(find.text('当前聊天'), findsNothing);
      expect(find.text('其他聊天'), findsOneWidget);
    });
  });
}
