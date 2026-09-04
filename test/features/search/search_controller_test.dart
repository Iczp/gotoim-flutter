import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/database/unified_database.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/features/contact/data/contact_api.dart';
import 'package:gotoim_flutter/features/search/application/search_controller.dart';
import 'package:gotoim_flutter/features/search/data/search_repository.dart';
import 'package:gotoim_flutter/features/search/domain/search_models.dart';

void main() {
  group('SearchController tests', () {
    late _FakeSearchRepository fakeRepo;
    late ProviderContainer container;

    setUp(() {
      fakeRepo = _FakeSearchRepository();
      container = ProviderContainer(
        overrides: [
          searchRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );
      container.listen(globalSearchControllerProvider, (_, __) {});
    });

    tearDown(() {
      container.dispose();
    });

    test('initializes and loads search history', () async {
      fakeRepo.history = ['Flutter', 'GotoIM'];
      final controller = container.read(globalSearchControllerProvider);
      await controller.loadHistory();

      final state = controller.state;
      expect(state.history, ['Flutter', 'GotoIM']);
      expect(state.isEmptyQuery, isTrue);
    });

    test('records keyword and updates state history', () async {
      final controller = container.read(globalSearchControllerProvider);
      await controller.recordKeyword('TestKeyword');

      final state = controller.state;
      expect(state.history, contains('TestKeyword'));
    });

    test('deletes keyword and clears history', () async {
      fakeRepo.history = ['Alpha', 'Beta'];
      final controller = container.read(globalSearchControllerProvider);
      await controller.loadHistory();

      await controller.deleteHistoryItem('Alpha');
      expect(controller.state.history, ['Beta']);

      await controller.clearAllHistory();
      expect(controller.state.history, isEmpty);
    });

    test('onQueryChanged empty resets results', () {
      final controller = container.read(globalSearchControllerProvider);
      controller.onQueryChanged('   ');

      final state = controller.state;
      expect(state.keyword, isEmpty);
      expect(state.localContacts, isEmpty);
      expect(state.localMessages, isEmpty);
      expect(state.remoteContacts, isEmpty);
    });

    test('onQueryChanged executes local search immediately and remote search after debounce', () async {
      fakeRepo.mockContacts = [
        const SearchContactItem(id: 'unit-1', title: '张三'),
      ];
      fakeRepo.mockMessages = [
        const SearchMessageItem(
          id: 'msg-1',
          sessionUnitId: 'unit-1',
          contentSnippet: '你好张三',
          matchedKeyword: '张三',
        ),
      ];
      fakeRepo.mockRemote = [
        const SearchRemoteContactItem(id: 'remote-1', name: '张三(线上)'),
      ];

      final controller = container.read(globalSearchControllerProvider);
      controller.onQueryChanged('张三');

      // 本地检索应迅速返回
      await pumpEventQueue();
      final intermediateState = controller.state;
      expect(intermediateState.localContacts.length, 1);
      expect(intermediateState.localContacts.first.title, '张三');
      expect(intermediateState.localMessages.length, 1);

      // 等待防抖计时器（350ms）并等待异步任务完成
      for (var i = 0; i < 20 && controller.state.remoteContacts.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await pumpEventQueue();
      }

      final finalState = controller.state;
      expect(finalState.remoteContacts.length, 1);
      expect(finalState.remoteContacts.first.name, '张三(线上)');
    });
  });
}

class _FakeSearchRepository extends SearchRepository {
  _FakeSearchRepository()
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
  _UnusedContactApi() : super(_FakeApiClient());
}

class _FakeApiClient implements ApiClient {
  @override
  Future<T> get<T>(String path, {Map<String, Object?>? query, bool retryOnUnauthorized = true}) =>
      throw UnimplementedError();
  @override
  Future<T> post<T>(String path, {Map<String, Object?>? query, Object? data, Map<String, String>? headers, bool retryOnUnauthorized = true}) =>
      throw UnimplementedError();
  @override
  Future<T> postMultipart<T>(String path, {Map<String, Object?>? query, Map<String, Object?>? extraFields, required MultipartUploadFile file, String fieldName = 'file', void Function(int sent, int total)? onProgress, bool retryOnUnauthorized = true}) =>
      throw UnimplementedError();
  @override
  Future<void> cancelByTag(Object tag) async {}
  @override
  Future<List<int>> getBytes(String path, {Object? cancelTag, void Function(int received, int total)? onProgress}) =>
      throw UnimplementedError();
}
