import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/network/api_exception.dart';
import 'package:gotoim_flutter/features/social/application/social_identity_controller.dart';
import 'package:gotoim_flutter/features/social/data/social_repository.dart';
import 'package:gotoim_flutter/features/social/presentation/social_detail_page.dart';
import 'package:gotoim_flutter/features/social/presentation/social_identity_gate.dart';

class _Repository extends Fake implements SocialRepository {
  final post = Completer<SocialPost>();
  final replies = Completer<SocialFeedPage>();
  bool repliesRequested = false;

  @override
  Future<SocialPost> getPost(String id, String? actorId) => post.future;

  @override
  Future<SocialFeedPage> getReplies({
    required String postId,
    String? viewerActorId,
    int pageSize = 20,
    String? cursor,
  }) {
    repliesRequested = true;
    return replies.future;
  }
}

void main() {
  testWidgets(
    'cached post is shown immediately and refreshed with replies in parallel',
    (tester) async {
      final repo = _Repository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            socialRepositoryProvider.overrideWithValue(repo),
            socialIdentityProvider.overrideWith(
              (ref) => SocialIdentityController(
                repo,
                chatObjectId: 1,
                name: 'Me',
              )..actor = const SocialActor(id: 'me', name: 'Me', handle: 'me'),
            ),
          ],
          child: const MaterialApp(
            home: SocialIdentityGate(
              useExistingActor: true,
              child: SocialDetailPage(
                postId: '1',
                initialPost: SocialPost(id: '1', content: 'cached'),
              ),
            ),
          ),
        ),
      );
      expect(find.text('cached'), findsOneWidget);
      expect(find.text('Social 社交'), findsNothing);
      expect(repo.repliesRequested, isTrue);
      repo.post.complete(const SocialPost(id: '1', content: 'updated'));
      repo.replies.complete(const SocialFeedPage(items: []));
      await tester.pump();
      expect(find.text('updated'), findsOneWidget);
      expect(find.text('cached'), findsNothing);
    },
  );

  testWidgets(
    'uncached post uses skeleton and revoked cached post is removed',
    (tester) async {
      final repo = _Repository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            socialRepositoryProvider.overrideWithValue(repo),
            socialIdentityProvider.overrideWith(
              (ref) =>
                  SocialIdentityController(repo, chatObjectId: 1, name: 'Me'),
            ),
          ],
          child: const MaterialApp(home: SocialDetailPage(postId: '1')),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      repo.post.complete(const SocialPost(id: '1', content: 'loaded'));
      repo.replies.complete(const SocialFeedPage(items: []));
      await tester.pump();
      expect(find.text('loaded'), findsOneWidget);
    },
  );

  testWidgets('forbidden response removes cached post', (tester) async {
    final repo = _Repository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          socialRepositoryProvider.overrideWithValue(repo),
          socialIdentityProvider.overrideWith(
            (ref) =>
                SocialIdentityController(repo, chatObjectId: 1, name: 'Me'),
          ),
        ],
        child: const MaterialApp(
          home: SocialDetailPage(
            postId: '1',
            initialPost: SocialPost(id: '1', content: 'cached'),
          ),
        ),
      ),
    );
    repo.post.completeError(const ApiException('forbidden', statusCode: 403));
    repo.replies.complete(const SocialFeedPage(items: []));
    await tester.pump();
    expect(find.text('cached'), findsNothing);
    expect(find.text('动态已不可用或无权查看。'), findsOneWidget);
  });
}
