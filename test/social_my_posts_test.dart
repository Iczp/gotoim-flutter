import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/features/social/application/social_identity_controller.dart';
import 'package:gotoim_flutter/features/social/data/social_repository.dart';
import 'package:gotoim_flutter/features/social/presentation/social_my_posts_page.dart';

class _Api extends Fake implements ApiClient {
  String? path;
  Map<String, Object?>? query;
  @override
  Future<T> delete<T>(String path, {Map<String, Object?>? query}) async {
    this.path = path;
    this.query = query;
    return null as T;
  }
}

class _Repo extends Fake implements SocialRepository {
  String? deleted;
  @override
  Future<SocialFeedPage> getActorPosts({
    required String actorId,
    String? viewerActorId,
    int pageSize = 3,
    String? cursor,
  }) async => const SocialFeedPage(
    items: [
      SocialPost(id: 'p', content: '我的内容'),
      SocialPost(id: 'r', content: '我的回复', parentId: 'p'),
    ],
  );
  @override
  Future<void> deletePost(String actorId, String postId) async {
    deleted = '$actorId/$postId';
  }
}

void main() {
  test('delete uses the documented Social endpoint and actor', () async {
    final api = _Api();
    await SocialRepository(api).deletePost('actor', 'post');
    expect(api.path, '/api/social/post');
    expect(api.query, {'actorId': 'actor', 'postId': 'post'});
  });
  testWidgets('shows own posts and replies and confirms deletion', (
    tester,
  ) async {
    final repo = _Repo();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          socialRepositoryProvider.overrideWithValue(repo),
          socialIdentityProvider.overrideWith(
            (ref) => SocialIdentityController(
              repo,
              chatObjectId: 1,
              name: 'Me',
            )..actor = const SocialActor(id: 'actor', name: 'Me', handle: 'me'),
          ),
        ],
        child: const MaterialApp(home: SocialMyPostsPage()),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('我的内容'), findsOneWidget);
    expect(find.text('我的回复'), findsOneWidget);
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    expect(find.text('删除回复？'), findsOneWidget);
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    expect(repo.deleted, 'actor/r');
    expect(find.text('我的回复'), findsNothing);
  });
}
