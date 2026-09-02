import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:gotoim_flutter/core/widgets/target_picker/target_picker.dart';
import 'package:gotoim_flutter/features/session/data/models/session_summary.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => dotenv.loadFromString(envString: 'APP_NAME=Test\nAPI_BASE_URL=https://api.test.com'));

  final mockItems = [
    const TargetPickerItem<String>(
      id: 'item-1',
      title: 'Alice',
      subtitle: 'Frontend Lead',
      category: 'Contacts',
      data: 'user-alice',
    ),
    const TargetPickerItem<String>(
      id: 'item-2',
      title: 'Bob',
      subtitle: 'Backend Architect',
      category: 'Contacts',
      data: 'user-bob',
    ),
    const TargetPickerItem<String>(
      id: 'item-3',
      title: 'Charlie (Disabled)',
      subtitle: 'QA',
      category: 'Contacts',
      disabled: true,
      disabledReason: 'Already in group',
      data: 'user-charlie',
    ),
    const TargetPickerItem<String>(
      id: 'group-1',
      title: 'Flutter Team',
      subtitle: 'Active discussion',
      badge: 'Group',
      category: 'Groups',
      data: 'group-flutter',
    ),
  ];

  Widget buildTestHost(Widget child) {
    return ProviderScope(
      overrides: [
        appEnvironmentProvider.overrideWithValue(
          AppEnvironment.fromDotEnv(AppFlavor.development),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(body: child),
      ),
    );
  }

  group('TargetPickerItem & Options Models', () {
    test('constructs from SessionSummary correctly', () {
      final session = SessionSummary.fromJson({
        'id': 'session-123',
        'displayName': 'Dev Group',
        'lastMessage': {'content': {'text': 'Hello world'}},
        'session': {'type': 2},
      });

      final item = TargetPickerItem.fromSessionSummary(session);
      expect(item.id, 'session-123');
      expect(item.title, 'Dev Group');
      expect(item.subtitle, 'Hello world');
      expect(item.badge, '群聊');
      expect(item.data, session);
    });

    test('options compute effectiveShowConfirmButton and minCount correctly', () {
      const defaultSingle = TargetPickerOptions(multiple: false);
      expect(defaultSingle.effectiveShowConfirmButton, isFalse);
      expect(defaultSingle.effectiveMinCount, 0);

      const defaultMulti = TargetPickerOptions(multiple: true);
      expect(defaultMulti.effectiveShowConfirmButton, isTrue);
      expect(defaultMulti.effectiveMinCount, 1);

      const explicitSingle = TargetPickerOptions(
        multiple: false,
        showConfirmButton: true,
        minCount: 1,
      );
      expect(explicitSingle.effectiveShowConfirmButton, isTrue);
      expect(explicitSingle.effectiveMinCount, 1);
    });
  });

  group('TargetPickerView Widget Tests', () {
    testWidgets('Single-select mode without confirm button confirms immediately on tap',
        (tester) async {
      List<TargetPickerItem<String>>? result;

      await tester.pumpWidget(
        buildTestHost(
          TargetPickerView<String>(
            items: mockItems,
            options: const TargetPickerOptions(
              multiple: false,
              showConfirmButton: false,
            ),
            onConfirm: (selected) => result = selected,
          ),
        ),
      );

      // Verify list items rendered
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);

      // Tap Alice
      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.length, 1);
      expect(result!.first.id, 'item-1');
      expect(result!.first.data, 'user-alice');
    });

    testWidgets('Disabled items cannot be selected and show disabled reason',
        (tester) async {
      List<TargetPickerItem<String>>? result;

      await tester.pumpWidget(
        buildTestHost(
          TargetPickerView<String>(
            items: mockItems,
            options: const TargetPickerOptions(
              multiple: false,
              showConfirmButton: false,
            ),
            onConfirm: (selected) => result = selected,
          ),
        ),
      );

      // Tap Charlie (Disabled)
      await tester.tap(find.text('Charlie (Disabled)'));
      await tester.pumpAndSettle();

      // Callback should not be called
      expect(result, isNull);
      expect(find.text('Already in group'), findsOneWidget);
    });

    testWidgets('Multi-select mode allows toggling items and respects maxCount limit',
        (tester) async {
      List<TargetPickerItem<String>>? result;

      await tester.pumpWidget(
        buildTestHost(
          TargetPickerView<String>(
            items: mockItems,
            options: const TargetPickerOptions(
              multiple: true,
              showConfirmButton: true,
              maxCount: 2,
              minCount: 1,
            ),
            onConfirm: (selected) => result = selected,
          ),
        ),
      );

      // Tap Alice
      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();

      // Tap Bob
      await tester.tap(find.text('Bob'));
      await tester.pumpAndSettle();

      // Tap Flutter Team (should exceed maxCount 2)
      await tester.tap(find.text('Flutter Team'));
      await tester.pumpAndSettle();

      // Confirm button label should show (2/2)
      expect(find.text('确定 (2/2)'), findsOneWidget);

      // Click Confirm
      await tester.tap(find.text('确定 (2/2)'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.length, 2);
      expect(result!.map((e) => e.id), containsAll(['item-1', 'item-2']));
    });

    testWidgets('Search query filters candidate list dynamically',
        (tester) async {
      await tester.pumpWidget(
        buildTestHost(
          TargetPickerView<String>(
            items: mockItems,
            options: const TargetPickerOptions(
              enableSearch: true,
            ),
          ),
        ),
      );

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Flutter Team'), findsOneWidget);

      // Enter search text 'Flutter'
      await tester.enterText(find.byType(TextField), 'Flutter');
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsNothing);
      expect(find.text('Bob'), findsNothing);
      expect(find.text('Flutter Team'), findsOneWidget);
    });
  });
}
