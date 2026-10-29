import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/features/social/application/social_notifications_controller.dart';
import 'package:gotoim_flutter/features/social/application/social_identity_controller.dart';
import 'package:gotoim_flutter/features/social/application/social_publish_controller.dart';
import 'package:gotoim_flutter/features/social/data/social_repository.dart';
import 'package:gotoim_flutter/features/social/presentation/social_publish_page.dart';
import 'package:gotoim_flutter/features/social/presentation/social_notifications_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'notification and publish repository uses actual Swagger routes and command body',
    () async {
      final api = _Transport();
      final repo = SocialRepository(api);
      expect(await repo.getUnreadCount('actor'), 3);
      expect(api.path, '/api/social/notification/unread-count/actor');
      final page = await repo.getNotifications('actor', cursor: 'signed');
      expect(api.query, {
        'RecipientActorId': 'actor',
        'PageSize': 20,
        'Cursor': 'signed',
      });
      expect(page.items.single.title, '你收到了新回复');
      expect(page.nextCursor, 'next');
      await repo.markNotificationRead('notice');
      expect(api.path, '/api/social/notification/notice/mark-as-read');
      await repo.markAllNotificationsRead('actor');
      expect(api.path, '/api/social/notification/mark-all-as-read/actor');
      await repo.publish(
        actorId: 'actor',
        content: 'text',
        clientRequestId: 'command',
        visibility: 3,
      );
      expect(api.data, {
        'actorId': 'actor',
        'content': 'text',
        'clientRequestId': 'command',
        'postType': 0,
        'visibility': 3,
        'replyPolicy': 0,
      });
    },
  );

  test(
    'unread count changes alert only once and errors preserve badge',
    () async {
      final repo = _Repository()..unread = 2;
      final state = SocialNotificationsController(
        repo,
        actor: const SocialActor(id: 'actor', name: 'Name', handle: 'name'),
      );
      addTearDown(state.dispose);
      await state.refreshUnread();
      expect(state.unreadCount, 2);
      expect(state.newMessageVersion, 0);
      repo.unread = 3;
      await state.refreshUnread();
      await state.refreshUnread();
      expect(state.newMessageVersion, 1);
      repo.failCount = true;
      await state.refreshUnread();
      expect(state.unreadCount, 3);
      expect(state.unreadError, isNotNull);
    },
  );

  testWidgets(
    'polling stops in background and resumes immediately without overlap',
    (tester) async {
      final repo = _Repository();
      final state = SocialNotificationsController(
        repo,
        actor: const SocialActor(id: 'actor', name: 'Name', handle: 'name'),
        pollInterval: const Duration(seconds: 2),
      );
      state.start();
      state.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(repo.countCalls, 1);
      await tester.pump(const Duration(seconds: 2));
      expect(repo.countCalls, 2);
      state.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 10));
      expect(repo.countCalls, 2);
      state.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(repo.countCalls, 3);
      state.dispose();
      await tester.pump(const Duration(seconds: 5));
      expect(repo.countCalls, 3);
    },
  );

  test(
    'concurrent count calls share a request and late responses after disposal are ignored',
    () async {
      final repo = _Repository()..pendingCount = Completer<int>();
      final state = SocialNotificationsController(
        repo,
        actor: const SocialActor(id: 'actor', name: 'Name', handle: 'name'),
      );
      final first = state.refreshUnread();
      final second = state.refreshUnread();
      await Future<void>.delayed(Duration.zero);
      expect(repo.countCalls, 1);
      state.dispose();
      repo.pendingCount!.complete(10);
      await Future.wait([first, second]);
      expect(state.unreadCount, 0);
    },
  );

  test(
    'read failure retains unread state and successful read refreshes canonical count',
    () async {
      final repo = _Repository()..unread = 1;
      final state = SocialNotificationsController(
        repo,
        actor: const SocialActor(id: 'actor', name: 'Name', handle: 'name'),
      );
      addTearDown(state.dispose);
      await state.load();
      await state.refreshUnread();
      repo.failRead = true;
      expect(await state.markRead(id: 'notice'), isFalse);
      expect(state.items.single.isRead, isFalse);
      expect(state.unreadCount, 1);
      repo.failRead = false;
      expect(await state.markRead(id: 'notice'), isTrue);
      expect(state.items.single.isRead, isTrue);
      expect(state.unreadCount, 0);
    },
  );

  test(
    'publish validates input, prevents concurrent submits and retries same command',
    () async {
      final repo = _Repository();
      final state = SocialPublishController(
        repo,
        actor: const SocialActor(id: 'actor', name: 'Name', handle: 'name'),
      );
      addTearDown(state.dispose);
      expect(await state.publish('   '), isNull);
      expect(await state.publish('a' * 2001), isNull);
      expect(repo.commands, isEmpty);
      repo.pendingPost = Completer<SocialPost>();
      final first = state.publish('hello');
      await Future<void>.delayed(Duration.zero);
      expect(await state.publish('hello'), isNull);
      expect(repo.commands.length, 1);
      repo.pendingPost!.completeError(StateError('timeout'));
      expect(await first, isNull);
      repo.pendingPost = null;
      expect(await state.publish('hello'), isNotNull);
      expect(repo.commands[0], repo.commands[1]);
      await state.publish('edited');
      expect(repo.commands[2], isNot(repo.commands[1]));
    },
  );

  testWidgets(
    'publish page exposes text and visibility controls and reports success only after server response',
    (tester) async {
      final repo = _Repository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            socialRepositoryProvider.overrideWithValue(repo),
            socialIdentityProvider.overrideWith(
              (ref) => SocialIdentityController(
                  repo,
                  chatObjectId: 7,
                  name: 'Current',
                )
                ..actor = const SocialActor(
                  id: 'actor',
                  name: 'Name',
                  handle: 'name',
                ),
            ),
          ],
          child: const MaterialApp(home: SocialPublishPage()),
        ),
      );
      await tester.enterText(find.byType(TextField), 'my post');
      await tester.tap(find.text('发布'));
      await tester.pump();
      expect(repo.publishedContents, ['my post']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'notification inbox shows unread items and marks them on opening',
    (tester) async {
      final state = SocialNotificationsController(
        _Repository()..unread = 1,
        actor: const SocialActor(id: 'actor', name: 'Name', handle: 'name'),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [socialNotificationsProvider.overrideWith((ref) => state)],
          child: const MaterialApp(home: SocialNotificationsPage()),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('你收到了新回复'), findsOneWidget);
      await tester.tap(find.text('你收到了新回复'));
      await tester.pump();
      await tester.pump();
      expect(state.items.single.isRead, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Repository implements SocialRepository {
  int unread = 0;
  int countCalls = 0;
  bool failCount = false;
  bool failRead = false;
  Completer<int>? pendingCount;
  Completer<SocialPost>? pendingPost;
  final commands = <String>[];
  final publishedContents = <String>[];
  @override
  Future<SocialActor> getMyActor() async =>
      const SocialActor(id: 'actor', name: 'Name', handle: 'name');
  @override
  Future<int> getUnreadCount(String actorId) async {
    countCalls++;
    if (failCount) throw StateError('offline');
    return pendingCount?.future ?? unread;
  }

  @override
  Future<SocialNotificationPage> getNotifications(
    String actorId, {
    String? cursor,
  }) async => const SocialNotificationPage(
    items: [
      SocialNotification(
        id: 'notice',
        type: 3,
        isRead: false,
        content: 'reply',
      ),
    ],
  );
  @override
  Future<void> markNotificationRead(String id) async {
    if (failRead) throw StateError('offline');
    unread = 0;
  }

  @override
  Future<void> markAllNotificationsRead(String actorId) =>
      markNotificationRead('all');
  @override
  Future<SocialPost> publish({
    required String actorId,
    required String content,
    required String clientRequestId,
    int visibility = 0,
    List<Map<String, dynamic>>? medias,
  }) async {
    commands.add(clientRequestId);
    publishedContents.add(content);
    return pendingPost?.future ??
        const SocialPost(id: 'published', content: 'posted');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Transport implements ApiClient {
  String? path;
  Map<String, Object?>? query;
  Object? data;
  @override
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    bool retryOnUnauthorized = true,
  }) async {
    this.path = path;
    this.query = query;
    if (path.contains('unread-count')) return 3 as T;
    return <String, dynamic>{
          'items': [
            {'id': 'notice', 'notificationType': 3, 'isRead': false},
          ],
          'pageInfo': {'hasMore': true, 'nextCursor': 'next'},
        }
        as T;
  }

  @override
  Future<T> post<T>(
    String path, {
    Map<String, Object?>? query,
    Object? data,
    Map<String, String>? headers,
    bool retryOnUnauthorized = true,
  }) async {
    this.path = path;
    this.data = data;
    return <String, dynamic>{'id': 'post', 'content': 'text'} as T;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
