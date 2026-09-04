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

  testWidgets(
    'SearchPage limits items to 3 and enters categorized search on view more',
    (tester) async {
      final fakeRepo = _MockSearchRepository();
      fakeRepo.mockContacts = [
        for (var i = 1; i <= 5; i++)
          SearchContactItem(
            id: 'unit-$i',
            ownerId: 2,
            title: '测试好友$i',
            subtitle: '1380000000$i',
          ),
      ];
      fakeRepo.mockMessages = [
        const SearchMessageItem(
          id: 'msg-1',
          sessionUnitId: 'unit-msg-1',
          contentSnippet: '包含测试的聊天记录',
          matchedKeyword: '测试',
          sessionTitle: '测试群聊',
        ),
      ];

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(body: Text('HomePageMock')),
          ),
          GoRoute(
            path: '/search',
            builder: (context, state) => const SearchPage(),
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

      router.push('/search');
      await tester.pumpAndSettle();

      // 输入搜索关键词
      await tester.enterText(find.byType(TextField), '测试');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      Finder findRich(String text) => find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText().contains(text),
          );

      // 1. 全部模式下：仅展示前 3 个联系人
      expect(findRich('测试好友1'), findsOneWidget);
      expect(findRich('测试好友2'), findsOneWidget);
      expect(findRich('测试好友3'), findsOneWidget);
      expect(findRich('测试好友4'), findsNothing);
      expect(findRich('测试好友5'), findsNothing);

      // 2. 存在“查看更多联系人 (共5条)”
      expect(find.text('查看更多联系人 (共5条)'), findsOneWidget);

      // 3. 聊天记录也展示
      expect(find.text('聊天记录'), findsOneWidget);
      expect(find.text('测试群聊'), findsOneWidget);

      // 4. 点击“查看更多联系人 (共5条)” -> 进入分类搜索模式
      await tester.tap(find.text('查看更多联系人 (共5条)'));
      await tester.pumpAndSettle();

      // 分类搜索模式下：展示全部 5 个联系人，不截断
      expect(findRich('测试好友1'), findsOneWidget);
      expect(findRich('测试好友2'), findsOneWidget);
      expect(findRich('测试好友3'), findsOneWidget);
      expect(findRich('测试好友4'), findsOneWidget);
      expect(findRich('测试好友5'), findsOneWidget);
      // “查看更多” 不再展示
      expect(find.text('查看更多联系人 (共5条)'), findsNothing);
      // 聊天记录被隐藏
      expect(find.text('测试群聊'), findsNothing);

      // 5. 点击 AppBar 返回按钮 -> 退出分类搜索，返回全部结果模式
      final backButtonFinder = find.byIcon(Icons.arrow_back_ios_new_rounded);
      expect(backButtonFinder, findsOneWidget);
      await tester.tap(backButtonFinder);
      await tester.pumpAndSettle();

      // 页面未退出到首页
      expect(find.text('HomePageMock'), findsNothing);
      // 恢复全部模式：又截断为3条，并展示“查看更多”
      expect(findRich('测试好友1'), findsOneWidget);
      expect(findRich('测试好友2'), findsOneWidget);
      expect(findRich('测试好友3'), findsOneWidget);
      expect(findRich('测试好友4'), findsNothing);
      expect(find.text('查看更多联系人 (共5条)'), findsOneWidget);
      expect(find.text('测试群聊'), findsOneWidget);

      // 6. 再次点击返回按钮 -> 退出搜索页，回到首页
      await tester.tap(backButtonFinder);
      await tester.pumpAndSettle();
      expect(find.text('HomePageMock'), findsOneWidget);
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
