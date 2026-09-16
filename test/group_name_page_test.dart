import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:gotoim_flutter/core/database/unified_database.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/features/chat_settings/application/chat_settings_controller.dart';
import 'package:gotoim_flutter/features/chat_settings/data/datasources/chat_member_api.dart';
import 'package:gotoim_flutter/features/chat_settings/data/datasources/chat_member_dao.dart';
import 'package:gotoim_flutter/features/chat_settings/data/repositories/chat_settings_repository.dart';
import 'package:gotoim_flutter/features/chat_settings/presentation/group_name_page.dart';
import 'package:gotoim_flutter/features/session/application/session_list_controller.dart';
import 'package:gotoim_flutter/features/session/data/datasources/ai_api.dart';
import 'package:gotoim_flutter/features/session/data/datasources/session_unit_api.dart';
import 'package:gotoim_flutter/features/session/data/datasources/session_dao.dart';
import 'package:gotoim_flutter/features/session/data/models/session_summary.dart';
import 'package:gotoim_flutter/features/session/data/repositories/session_repository.dart';
import 'package:gotoim_flutter/features/session/data/session_change_bus.dart';

class _FakeApiClient implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() => dotenv.loadFromString(envString: 'APP_NAME=Test'));

  testWidgets('GroupNamePage renders initial title, helper text, and input box', (
    tester,
  ) async {
    final database = UnifiedDatabase(
      DatabaseConnection(NativeDatabase.memory()),
    );
    addTearDown(database.close);

    final sessionDao = SessionDao(database);
    await sessionDao.upsertAll(<SessionSummary>[
      SessionSummary.fromJson(<String, dynamic>{
        'id': 'session-group-1',
        'ownerId': 10,
        'score': 1,
        'destination': <String, dynamic>{
          'name': '测试产品研发群',
          'objectType': 2,
        },
      }),
    ]);

    final client = _FakeApiClient();
    final settingsRepo = ChatSettingsRepository(
      api: ChatMemberApi(client),
      dao: ChatMemberDao(database),
    );
    final sessionRepo = SessionRepository(
      api: SessionUnitApi(client),
      aiApi: AiApi(client),
      dao: sessionDao,
      changeBus: SessionChangeBus(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appEnvironmentProvider.overrideWithValue(
            AppEnvironment.fromDotEnv(AppFlavor.development),
          ),
          sessionRepositoryProvider.overrideWithValue(sessionRepo),
          chatSettingsRepositoryProvider.overrideWithValue(settingsRepo),
        ],
        child: const MaterialApp(
          home: GroupNamePage(
            ownerId: 10,
            sessionUnitId: 'session-group-1',
            initialTitle: '测试产品研发群',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify main components
    expect(find.text('修改群名称'), findsWidgets);
    expect(find.text('修改群名称后,将在群内通知其他成员'), findsOneWidget);
    expect(find.text('名称:'), findsOneWidget);
    expect(find.text('完成'), findsWidgets);

    // Verify initial input text
    final textField = find.byType(TextField);
    expect(textField, findsOneWidget);
    expect(find.text('测试产品研发群'), findsWidgets);

    // Input new title
    await tester.enterText(textField, '极客交流核心群');
    await tester.pump();
    expect(find.text('极客交流核心群'), findsOneWidget);
  });
}
