import 'dart:async';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/app/application_providers.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/features/social/application/social_feed_controller.dart';
import 'package:gotoim_flutter/features/social/application/social_notifications_controller.dart';
import 'package:gotoim_flutter/features/social/data/social_repository.dart';
import 'package:gotoim_flutter/features/social/presentation/social_page.dart';

void main() {
  testWidgets('Social page renders API content and switches to following', (
    tester,
  ) async {
    dotenv.loadFromString(envString: 'API_BASE_URL=https://gateway.test');
    final api = _Api();
    final controller = SocialFeedController(
      SocialRepository(api),
      actor: const SocialActor(id: 'actor', name: 'Name', handle: 'name'),
    );
    await controller.refresh();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          socialNotificationsProvider.overrideWith(
            (ref) => SocialNotificationsController(
              SocialRepository(api),
              actor: const SocialActor(
                id: 'actor',
                name: 'Name',
                handle: 'name',
              ),
            ),
          ),
          socialFeedControllerProvider(false).overrideWith((ref) => controller),
        ],
        child: const MaterialApp(home: SocialPage()),
      ),
    );
    expect(find.text('Social 社交'), findsOneWidget);
    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('赞 2'), findsOneWidget);
    await tester.tap(find.text('正在关注'));
    await tester.pump();
    await tester.pump();
    expect(api.path, '/api/social/feed/following-feed');
    expect(tester.takeException(), isNull);
  });
  test('Social owns a dedicated Dio endpoint and repository transport', () async {
    dotenv.loadFromString(
      envString:
          'API_BASE_URL=https://chat.test\nSOCIAL_API_BASE_URL=https://social.test',
    );
    final api = _Api();
    final container = ProviderContainer(
      overrides: [
        appEnvironmentProvider.overrideWithValue(
          AppEnvironment.fromDotEnv(AppFlavor.development),
        ),
        apiClientProvider.overrideWith(
          (_) => throw StateError('Chat must not be read'),
        ),
        socialApiClientProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    expect(
      container.read(socialDioProvider).options.baseUrl,
      'https://social.test',
    );
    final repo = container.read(socialRepositoryProvider);
    expect((await repo.getMyActor()).id, 'actor');
    expect(
      (await repo.getChatObjectActor(123, viewerActorId: 'viewer'))!.id,
      'actor',
    );
    expect(api.path, '/api/social/actor/for-chat-object');
    expect(api.query, {'chatObjectId': 123, 'viewerActorId': 'viewer'});
    final page = await repo.getFeed(
      actorId: 'actor',
      following: false,
      clientRequestId: 'request-id',
      cursor: 'signed-cursor',
      pageSize: 10,
    );
    expect(api.path, '/api/social/feed/for-you-feed');
    expect(api.query, {
      'ViewerActorId': 'actor',
      'PageSize': 10,
      'ClientRequestId': 'request-id',
      'Cursor': 'signed-cursor',
    });
    expect(page.items.single.content, 'Hello');
    expect(page.nextCursor, 'next');
    expect(page.hasMore, isTrue);
    expect(page.isPartial, isTrue);
    await repo.getFeed(
      actorId: 'actor',
      following: true,
      clientRequestId: 'unused',
    );
    expect(api.path, '/api/social/feed/following-feed');
    expect(api.query!.containsKey('ClientRequestId'), isFalse);
  });

  test(
    'unset Social endpoint uses gateway without sharing the Chat client',
    () {
      dotenv.loadFromString(envString: 'API_BASE_URL=https://gateway.test');
      expect(
        AppEnvironment.fromDotEnv(AppFlavor.development).socialApiBaseUrl,
        'https://gateway.test',
      );
    },
  );

  test(
    'tab changes ignore stale pages, reuse actor and deduplicate cursors',
    () async {
      final repo = _Repository();
      final state = SocialFeedController(
        repo,
        actor: const SocialActor(id: 'actor', name: 'Name', handle: 'name'),
      );
      addTearDown(state.dispose);
      final first = state.refresh();
      await Future<void>.delayed(Duration.zero);
      final second = state.refresh(followingFeed: true);
      await Future<void>.delayed(Duration.zero);
      repo.pages[1].complete(
        const SocialFeedPage(
          items: [SocialPost(id: 'new', content: 'new')],
          nextCursor: 'cursor',
          hasMore: true,
        ),
      );
      await second;
      repo.pages[0].complete(
        const SocialFeedPage(items: [SocialPost(id: 'old', content: 'old')]),
      );
      await first;
      expect(state.items.map((p) => p.id), ['new']);
      expect(repo.actorCalls, 0);
      final more = state.loadMore();
      await Future<void>.delayed(Duration.zero);
      expect(repo.cursors.last, 'cursor');
      repo.pages.last.complete(
        const SocialFeedPage(
          items: [SocialPost(id: 'new', content: 'duplicate')],
          nextCursor: 'cursor',
          hasMore: true,
        ),
      );
      await more;
      expect(state.items.length, 1);
      expect(state.hasMore, isFalse);
    },
  );

  test(
    'retry preserves recommendation request identity and disposal ignores response',
    () async {
      final repo = _Repository();
      final state = SocialFeedController(
        repo,
        actor: const SocialActor(id: 'actor', name: 'Name', handle: 'name'),
      );
      final first = state.refresh();
      await Future<void>.delayed(Duration.zero);
      repo.pages.last.completeError(StateError('offline'));
      await first;
      expect(state.error, isNotNull);
      final retry = state.retry();
      await Future<void>.delayed(Duration.zero);
      expect(repo.requestIds.toSet().length, 1);
      state.dispose();
      repo.pages.last.complete(const SocialFeedPage(items: []));
      await retry;
    },
  );
}

class _Api implements ApiClient {
  String? path;
  Map<String, Object?>? query;
  @override
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    bool retryOnUnauthorized = true,
  }) async {
    this.path = path;
    this.query = query;
    final result =
        (path.endsWith('my-actor') || path.endsWith('for-chat-object'))
            ? <String, dynamic>{
              'id': 'actor',
              'displayName': 'Name',
              'handle': 'name',
            }
            : <String, dynamic>{
              'items': [
                {
                  'id': 'post',
                  'content': 'Hello',
                  'author': {
                    'id': 'actor',
                    'displayName': 'Name',
                    'handle': 'name',
                  },
                  'likesCount': 2,
                  'medias': [],
                },
              ],
              'pageInfo': {
                'nextCursor': 'next',
                'hasMore': true,
                'isPartial': true,
              },
            };
    return result as T;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repository implements SocialRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  int actorCalls = 0;
  final pages = <Completer<SocialFeedPage>>[];
  final cursors = <String?>[];
  final requestIds = <String>[];
  @override
  Future<SocialActor> getMyActor() async {
    actorCalls++;
    return const SocialActor(id: 'actor', name: 'Name', handle: 'name');
  }

  @override
  Future<SocialFeedPage> getFeed({
    required String actorId,
    required bool following,
    required String clientRequestId,
    String? cursor,
    int pageSize = 20,
  }) {
    cursors.add(cursor);
    requestIds.add(clientRequestId);
    final pending = Completer<SocialFeedPage>();
    pages.add(pending);
    return pending.future;
  }
}
