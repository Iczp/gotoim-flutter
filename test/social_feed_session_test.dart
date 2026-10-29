import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
import 'package:gotoim_flutter/features/social/presentation/widgets/social_post_card.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/core/network/api_exception.dart';
import 'package:gotoim_flutter/features/social/application/social_feed_controller.dart';
import 'package:gotoim_flutter/features/social/data/social_repository.dart';

class Transport extends Fake implements ApiClient {
  final calls = <Map<String, Object?>>[];
  bool reject = false;
  @override
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    bool retryOnUnauthorized = true,
  }) async {
    calls.add({'path': path, ...?query});
    if (reject) {
      throw const ApiException(
        'limit',
        statusCode: 429,
        retryAfter: Duration(milliseconds: 1),
      );
    }
    return {
          'items': [
            {'id': path, 'content': 'hello'},
          ],
          'pageInfo': {'hasMore': false},
        }
        as T;
  }
}

void main() {
  test(
    'switching and reselection reuse saved feed, refresh uses same recommendation session',
    () async {
      final api = Transport();
      final state = SocialFeedController(
        SocialRepository(api),
        actor: const SocialActor(id: 'a', name: 'a', handle: 'a'),
      );
      addTearDown(state.dispose);
      await state.refresh();
      final request = api.calls.single['ClientRequestId'];
      await state.refresh(followingFeed: false);
      expect(api.calls.length, 1);
      await state.refresh(followingFeed: true);
      expect(api.calls.length, 2);
      await state.refresh(followingFeed: false);
      expect(api.calls.length, 2);
      expect(state.items.single.content, 'hello');
      await state.refresh();
      expect(api.calls.length, 3);
      expect(api.calls.last['ClientRequestId'], request);
    },
  );
  test('429 retry keeps the same request and old content', () async {
    final api = Transport();
    final state = SocialFeedController(
      SocialRepository(api),
      actor: const SocialActor(id: 'a', name: 'a', handle: 'a'),
    );
    addTearDown(state.dispose);
    await state.refresh();
    final request = api.calls.single['ClientRequestId'];
    api.reject = true;
    await state.refresh();
    expect(state.items.single.content, 'hello');
    expect(api.calls.last['ClientRequestId'], request);
    api.reject = false;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await state.retry();
    expect(api.calls.last['ClientRequestId'], request);
  });
  test('429 when switching tabs retains previous visible posts', () async {
    final api = Transport();
    final state = SocialFeedController(
      SocialRepository(api),
      actor: const SocialActor(id: 'a', name: 'a', handle: 'a'),
    );
    addTearDown(state.dispose);
    await state.refresh();
    api.reject = true;
    await state.refresh(followingFeed: true);
    expect(state.items.single.content, 'hello');
    expect(state.showingPreviousFeed, isTrue);
    expect(state.error, isNotNull);
    await state.refresh(followingFeed: false);
    expect(state.items.single.content, 'hello');
    expect(state.showingPreviousFeed, isFalse);
  });
  testWidgets('tapping post body opens detail with post', (tester) async {
    dotenv.loadFromString(envString: 'API_BASE_URL=https://gateway.test');
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder:
              (_, __) => const Scaffold(
                body: SocialPostCard(
                  post: SocialPost(id: 'post-1', content: 'Hello #world'),
                ),
              ),
        ),
        GoRoute(
          path: '/social/detail/:id',
          builder:
              (_, state) => Scaffold(
                body: Text(
                  'detail ${state.pathParameters['id']} ${(state.extra as SocialPost).content}',
                ),
              ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.tap(find.text('Hello #world'));
    await tester.pumpAndSettle();
    expect(find.text('detail post-1 Hello #world'), findsOneWidget);
  });
}
