import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/realtime/signalr_gateway.dart';
import 'package:flutter/services.dart';
import 'package:gotoim_flutter/core/native_window/desktop_profile_card_view.dart';
import 'package:gotoim_flutter/features/auth/application/auth_controller.dart';
import 'package:gotoim_flutter/features/auth/domain/auth_repository.dart';
import 'package:gotoim_flutter/features/social/application/social_identity_controller.dart';
import 'package:gotoim_flutter/features/session/application/friend_presence_store.dart';
import 'package:gotoim_flutter/features/social/application/social_profile_preview.dart';
import 'package:gotoim_flutter/features/social/data/social_repository.dart';
import 'package:gotoim_flutter/features/user/data/models/profile_subject.dart';
import 'package:gotoim_flutter/features/user/presentation/desktop_profile_card_dialog.dart';
import 'package:gotoim_flutter/features/user/presentation/profile_detail_page.dart';
import 'package:gotoim_flutter/features/user/presentation/widgets/profile_social_preview.dart';

const _targetUser = '11111111-1111-1111-1111-111111111111';
const _otherUser = '22222222-2222-2222-2222-222222222222';
const _subject = ProfileSubject(
  kind: ProfileKind.friend,
  id: 'session-unit-id',
  name: 'Alice',
  avatarUrl: '',
  raw: {
    'destination': {'id': 42, 'appUserId': _targetUser, 'code': 'alice'},
    'owner': {'id': 7, 'appUserId': _otherUser},
  },
);
final _preview = SocialProfilePreview(
  actor: const SocialActor(
    id: 'target-actor',
    name: 'Alice',
    handle: 'alice',
    followingCount: 12,
    followersCount: 34,
    isFollowing: true,
  ),
  viewerActorId: 'viewer',
  posts: List.generate(
    4,
    (i) => SocialPost(id: 'post-$i', content: '真实动态 ${i + 1}'),
  ),
);

void main() {
  setUpAll(() => dotenv.loadFromString(envString: 'APP_NAME=Test'));
  test(
    'friend resolves destination and member resolves owner, never session id or nickname',
    () {
      expect(socialTargetForProfile(_subject), (chatObjectId: 42));
      const member = ProfileSubject(
        kind: ProfileKind.member,
        id: 'unit',
        name: 'Member',
        avatarUrl: '',
        raw: {
          'owner': {'id': 9, 'appUserId': _otherUser},
        },
      );
      expect(socialTargetForProfile(member), (chatObjectId: 9));
      const indexed = ProfileSubject(
        kind: ProfileKind.friend,
        id: 'unit-guid',
        name: 'Alice',
        avatarUrl: '',
        raw: {'id': 'unit-guid', 'destinationId': 42},
      );
      expect(socialTargetForProfile(indexed), (chatObjectId: 42));
    },
  );
  for (final bound in [true, false]) {
    test(
      'target preview resolves verified identity and respects binding=$bound',
      () async {
        final repo = _Social()..bound = bound;

        final auth = AuthController(
          _Auth(),
          _SignalR(),
          minSplashDuration: Duration.zero,
        );
        await Future<void>.delayed(Duration.zero);
        final container = ProviderContainer(
          overrides: [
            friendPresenceStoreProvider.overrideWith((ref) => _Presence()),
            authControllerProvider.overrideWith((ref) => auth),
            socialRepositoryProvider.overrideWithValue(repo),
            socialIdentityProvider.overrideWith(
              (ref) => SocialIdentityController(
                  repo,
                  chatObjectId: 7,
                  name: 'Viewer',
                )
                ..actor = const SocialActor(
                  id: 'viewer-actor',
                  name: 'Me',
                  handle: 'me',
                ),
            ),
          ],
        );
        addTearDown(container.dispose);
        final target =
            bound ? socialTargetForProfile(_subject) : (chatObjectId: 42);
        final value = await container.read(
          socialProfilePreviewProvider(target).future,
        );
        expect(repo.resolvedChatId, 42);

        if (bound) {
          expect(repo.requestedActor, 'target-actor');
          expect(repo.requestedViewer, 'viewer-actor');
          expect(repo.pageSize, 3);
          expect(value.posts.length, 3);
        } else {
          expect(value.actor, isNull);
          expect(repo.myActorCalls, 0);
          expect(repo.requestedActor, isNull);
        }
      },
    );
  }
  for (final full in [false, true]) {
    testWidgets(
      '${full ? 'full profile' : 'compact preview'} displays latest three posts inline',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              friendPresenceStoreProvider.overrideWith((ref) => _Presence()),
              socialProfilePreviewProvider(
                socialTargetForProfile(_subject),
              ).overrideWith((ref) async => _preview),
            ],
            child: MaterialApp(
              home:
                  full
                      ? const ProfileDetailPage(subject: _subject)
                      : const Scaffold(
                        body: ProfileSocialPreview(subject: _subject),
                      ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        if (full) await tester.ensureVisible(find.byType(ProfileSocialPreview));
        for (var i = 1; i <= 3; i++) {
          expect(find.text('真实动态 $i'), findsOneWidget);
        }
        expect(find.text('真实动态 4'), findsNothing);
        expect(find.text('关注 12'), findsOneWidget);
        expect(find.text('粉丝 34'), findsOneWidget);
        expect(find.text('已关注'), findsOneWidget);
        expect(find.text('查看朋友圈'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'desktop card scrolls recent posts in a small window without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(800, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            friendPresenceStoreProvider.overrideWith((ref) => _Presence()),
            socialProfilePreviewProvider(
              socialTargetForProfile(_subject),
            ).overrideWith((ref) async => _preview),
          ],
          child: const MaterialApp(
            home: Scaffold(body: DesktopProfileCardDialog(subject: _subject)),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.ensureVisible(find.text('真实动态 3'));
      expect(find.text('真实动态 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'unlinked and empty profiles differ, groups have no personal preview',
    (tester) async {
      for (final data in [
        const SocialProfilePreview(),
        const SocialProfilePreview(
          actor: SocialActor(id: 'actor', name: 'Alice', handle: 'alice'),
        ),
      ]) {
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              friendPresenceStoreProvider.overrideWith((ref) => _Presence()),
              socialProfilePreviewProvider(
                socialTargetForProfile(_subject),
              ).overrideWith((ref) async => data),
            ],
            child: const MaterialApp(
              home: Scaffold(body: ProfileSocialPreview(subject: _subject)),
            ),
          ),
        );
        await tester.pump();
        expect(
          find.text(data.actor == null ? '尚未关联 Social 身份' : '暂无可见动态'),
          findsOneWidget,
        );
      }
      const group = ProfileSubject(
        kind: ProfileKind.group,
        id: 'group',
        name: 'Group',
        avatarUrl: '',
        raw: {},
      );
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: ProfileSocialPreview(subject: group)),
          ),
        ),
      );
      expect(find.text('动态'), findsNothing);
    },
  );

  testWidgets(
    'native profile window shows latest three and follow facts, hides stale data during update',
    (tester) async {
      tester.view.physicalSize = const Size(380, 420);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Future<dynamic> Function(MethodCall)? handler;
      final pending = Completer<Map<String, dynamic>>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            friendPresenceStoreProvider.overrideWith((ref) => _Presence()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: DesktopProfileCardView(
                initialSubject: _subject,
                onRegisterMethodHandler: (callback) => handler = callback,
                readSocialPreview:
                    (subject) async =>
                        socialTargetForProfile(subject).chatObjectId == 42
                            ? {
                              'actorLinked': true,
                              'followingCount': 12,
                              'followersCount': 34,
                              'isFollowing': true,
                              'posts':
                                  _preview.posts
                                      .map((post) => post.toWindowPayload())
                                      .toList(),
                            }
                            : pending.future,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('真实动态 1'), findsOneWidget);
      expect(find.text('真实动态 3'), findsOneWidget);
      expect(find.text('真实动态 4'), findsNothing);
      expect(find.text('关注 12'), findsOneWidget);
      expect(find.text('粉丝 34'), findsOneWidget);
      expect(find.text('已关注'), findsOneWidget);
      const other = ProfileSubject(
        kind: ProfileKind.friend,
        id: 'other',
        name: 'Bob',
        avatarUrl: '',
        raw: {
          'destination': {'id': 99, 'code': 'bob'},
        },
      );
      await handler!(MethodCall('update_profile', other.toMap()));
      await tester.pump();
      expect(find.text('真实动态 1'), findsNothing);
      pending.complete({
        'actorLinked': true,
        'followingCount': 1,
        'followersCount': 2,
        'isFollowing': false,
        'posts': [
          const SocialPost(id: 'other', content: 'Bob 的动态').toWindowPayload(),
        ],
      });
      await tester.pump();
      await tester.pump();
      expect(find.text('Bob 的动态'), findsOneWidget);
      expect(find.text('未关注'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Social implements SocialRepository {
  bool bound = true;
  int? resolvedChatId;
  String? requestedActor;
  String? requestedViewer;
  int? pageSize;
  int myActorCalls = 0;
  @override
  Future<SocialActor?> getChatObjectActor(
    int chatObjectId, {
    String? viewerActorId,
  }) async {
    resolvedChatId = chatObjectId;
    return bound ? _preview.actor : null;
  }

  @override
  Future<SocialActor> getMyActor() async {
    myActorCalls++;
    return const SocialActor(id: 'viewer-actor', name: 'Me', handle: 'me');
  }

  @override
  Future<SocialFeedPage> getActorPosts({
    required String actorId,
    String? viewerActorId,
    int pageSize = 3,
    String? cursor,
  }) async {
    requestedActor = actorId;
    requestedViewer = viewerActorId;
    this.pageSize = pageSize;
    return SocialFeedPage(items: _preview.posts);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth implements AuthRepository {
  @override
  Future<bool> restoreSession() async => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SignalR implements SignalRGateway {
  @override
  Future<void> disconnect() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Presence extends ChangeNotifier implements FriendPresenceStore {
  @override
  List<String> deviceTypesForChatObjectId(int? id) => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
