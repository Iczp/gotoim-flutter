import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:gotoim_flutter/core/database/unified_database.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/features/contact/data/contact_api.dart';
import 'package:gotoim_flutter/features/search/data/search_repository.dart';
import 'package:gotoim_flutter/features/search/domain/search_models.dart';
import 'package:gotoim_flutter/features/search/presentation/search_page.dart';

void main() {
  setUpAll(() => dotenv.loadFromString(envString: 'APP_NAME=Test'));

  testWidgets(
    'SearchPage shows Friend contacts ranked first and taps directly to chat',
    (tester) async {
      final fakeRepo = _MockSearchRepository();
      fakeRepo.mockContacts = [
        const SearchContactItem(
          id: 'unit-friend-88',
          ownerId: 2,
          title: '张三 (Friend)',
          subtitle: '你好，周末有空吗？',
          isRoom: false,
        ),
      ];
      fakeRepo.mockMessages = [
        const SearchMessageItem(
          id: 'msg-1',
          sessionUnitId: 'unit-msg-99',
          contentSnippet: '包含张三的聊天记录片段',
          matchedKeyword: '张三',
          sessionTitle: '群聊讨论',
        ),
      ];

      String? pushedRoute;
      final router = GoRouter(
        initialLocation: '/search',
        routes: [
          GoRoute(
            path: '/search',
            builder: (context, state) => const SearchPage(),
          ),
          GoRoute(
            path: '/chat/:sessionUnitId',
            builder: (context, state) {
              pushedRoute = state.uri.toString();
              return const Scaffold(body: Text('ChatPageMock'));
            },
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appEnvironmentProvider.overrideWithValue(
              AppEnvironment.fromDotEnv(AppFlavor.development),
            ),
            searchRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );

      // 验证搜索框和初始状态
      expect(find.byType(TextField), findsOneWidget);

      // 输入搜索关键词
      await tester.enterText(find.byType(TextField), '张三');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 验证 Friend 联系人排在首位，分类为「联系人」
      expect(find.text('联系人'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('张三 (Friend)')),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('你好，周末有空吗？')),
        findsOneWidget,
      );

      // 验证聊天记录排在联系人下方
      expect(find.text('聊天记录'), findsOneWidget);

      // 点击 Friend 联系人直接进入聊天
      await tester.tap(
        find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('张三 (Friend)')),
      );
      await tester.pumpAndSettle();

      // 验证正确跳转至 /chat/:sessionUnitId 路由且携带正确的 ownerId 和 title
      expect(pushedRoute, isNotNull);
      expect(pushedRoute, startsWith('/chat/unit-friend-88'));
      expect(pushedRoute, contains('ownerId=2'));
      expect(pushedRoute, contains('title='));
      expect(find.text('ChatPageMock'), findsOneWidget);
    },
  );
}

class _MockSearchRepository extends SearchRepository {
  _MockSearchRepository()
      : super(
          database: _UnusedDatabase(),
          contactApi: _UnusedContactApi(),
        );

  List<String> history = [];
  List<SearchContactItem> mockContacts = [];
  List<SearchMessageItem> mockMessages = [];
  List<SearchRemoteContactItem> mockRemote = [];

  @override
  Future<List<String>> getSearchHistory() async => List.of(history);

  @override
  Future<List<String>> addSearchHistory(String keyword) async {
    history = [keyword, ...history.where((k) => k != keyword)];
    return List.of(history);
  }

  @override
  Future<List<String>> deleteSearchHistory(String keyword) async {
    history = history.where((k) => k != keyword).toList();
    return List.of(history);
  }

  @override
  Future<void> clearSearchHistory() async {
    history = [];
  }

  @override
  Future<List<SearchContactItem>> searchLocalContacts({
    required int ownerId,
    required String keyword,
  }) async => mockContacts;

  @override
  Future<List<SearchMessageItem>> searchLocalMessages({
    required int ownerId,
    required String keyword,
  }) async => mockMessages;

  @override
  Future<List<SearchRemoteContactItem>> searchRemoteContacts({
    required int ownerId,
    required String keyword,
  }) async => mockRemote;
}

class _UnusedDatabase implements UnifiedDatabase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedContactApi extends ContactApi {
  _UnusedContactApi() : super(_UnusedApiClient());
}

class _UnusedApiClient implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
