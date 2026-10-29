import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/features/social/application/social_identity_controller.dart';
import 'package:gotoim_flutter/features/social/data/social_repository.dart';
import 'package:gotoim_flutter/features/social/presentation/social_identity_gate.dart';

void main() {
  test(
    'startup checks are read-only and never create default-user actors',
    () async {
      final repo = _Social();
      final identity = SocialIdentityController(
        repo,
        chatObjectId: 1,
        name: 'First',
      );
      addTearDown(identity.dispose);
      await identity.load();
      expect(identity.actor, isNull);
      expect(repo.reads, [1]);
      expect(repo.creates, isEmpty);
      await identity.enter();
      expect(repo.creates, [false]);
      expect(identity.actor, isNull);
    },
  );

  test(
    'a late response cannot restore a disposed previous ChatObject identity',
    () async {
      final repo = _Social()..pending = Completer<SocialActor?>();
      final old = SocialIdentityController(
        repo,
        chatObjectId: 1,
        name: 'First',
      );
      final pending = old.enter(create: true);
      old.dispose();
      repo.pending!.complete(
        const SocialActor(id: 'old', name: 'First', handle: 'first'),
      );
      await pending;
      expect(old.actor, isNull);
      repo.pending = null;
      final next = SocialIdentityController(
        repo,
        chatObjectId: 2,
        name: 'Second',
      );
      addTearDown(next.dispose);
      await next.enter(create: true);
      expect(next.actor!.id, 'chat-2');
      expect(repo.ids, [1, 2]);
    },
  );

  test(
    'revalidating the same identity keeps actor until result arrives',
    () async {
      final repo = _Social();
      final identity = SocialIdentityController(
        repo,
        chatObjectId: 1,
        name: 'First',
      );
      addTearDown(identity.dispose);
      await identity.enter(create: true);
      expect(identity.actor?.id, 'chat-1');
      repo.pending = Completer<SocialActor?>();
      final pending = identity.enter();
      expect(identity.actor?.id, 'chat-1');
      repo.pending!.complete(
        const SocialActor(id: 'chat-1', name: 'First', handle: 'first'),
      );
      await pending;
      expect(identity.actor?.id, 'chat-1');
    },
  );

  for (final accept in [false, true]) {
    testWidgets('entry asks before creating; consent=$accept', (tester) async {
      final repo = _Social();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            socialIdentityProvider.overrideWith(
              (ref) => SocialIdentityController(
                repo,
                chatObjectId: 1,
                name: 'First',
              ),
            ),
          ],
          child: const MaterialApp(
            home: SocialIdentityGate(child: Text('社区内容')),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('创建 Social 身份？'), findsOneWidget);
      expect(repo.creates, [false]);
      await tester.tap(find.text(accept ? '确认创建' : '暂不创建'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(repo.creates, accept ? [false, true] : [false]);
      expect(find.text('社区内容'), accept ? findsOneWidget : findsNothing);
    });
  }

  testWidgets(
    'main identity switch removes old community and prompts for the new ChatObject',
    (tester) async {
      final repo =
          _Social()
            ..actors[1] = const SocialActor(
              id: 'chat-1',
              name: 'First',
              handle: 'first',
            );
      var selected = 1;
      final container = ProviderContainer(
        overrides: [
          socialCurrentChatObjectProvider.overrideWith(
            (ref) => (id: selected, name: 'Identity $selected'),
          ),
          socialIdentityProvider.overrideWith((ref) {
            final chat = ref.watch(socialCurrentChatObjectProvider);
            return SocialIdentityController(
              repo,
              chatObjectId: chat.id,
              name: chat.name!,
            );
          }),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: SocialIdentityGate(
              child: Consumer(
                builder:
                    (context, ref, _) => Text(
                      '社区 ${ref.watch(socialIdentityProvider).actor?.id}',
                    ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('社区 chat-1'), findsOneWidget);
      selected = 2;
      container.invalidate(socialCurrentChatObjectProvider);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('社区 chat-1'), findsNothing);
      expect(find.text('创建 Social 身份？'), findsOneWidget);
      expect(find.textContaining('Identity 2'), findsWidgets);
      await tester.tap(find.text('确认创建'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('社区 chat-2'), findsOneWidget);
      expect(repo.ids.last, 2);
    },
  );

  testWidgets(
    'switching while confirmation is open cannot create the old ChatObject',
    (tester) async {
      final repo = _Social();
      var selected = 1;
      final container = ProviderContainer(
        overrides: [
          socialCurrentChatObjectProvider.overrideWith(
            (ref) => (id: selected, name: 'Identity $selected'),
          ),
          socialIdentityProvider.overrideWith((ref) {
            final chat = ref.watch(socialCurrentChatObjectProvider);
            return SocialIdentityController(
              repo,
              chatObjectId: chat.id,
              name: chat.name!,
            );
          }),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: SocialIdentityGate(child: Text('社区内容')),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      selected = 2;
      container.invalidate(socialCurrentChatObjectProvider);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Identity 1'), findsNothing);
      expect(find.textContaining('Identity 2'), findsWidgets);
      await tester.tap(find.text('确认创建'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(repo.actors.containsKey(1), isFalse);
      expect(repo.actors.containsKey(2), isTrue);
    },
  );
}

class _Social implements SocialRepository {
  final actors = <int, SocialActor>{};
  final reads = <int>[];
  final ids = <int>[];
  final creates = <bool>[];
  Completer<SocialActor?>? pending;
  @override
  Future<SocialActor?> getChatObjectActor(
    int chatObjectId, {
    String? viewerActorId,
  }) async {
    reads.add(chatObjectId);
    return actors[chatObjectId];
  }

  @override
  Future<SocialActor?> resolveChatObject(
    int chatObjectId, {
    bool create = false,
  }) async {
    ids.add(chatObjectId);
    creates.add(create);
    if (pending != null) return pending!.future;
    if (create) {
      actors.putIfAbsent(
        chatObjectId,
        () => SocialActor(
          id: 'chat-$chatObjectId',
          name: 'Chat $chatObjectId',
          handle: 'chat_$chatObjectId',
        ),
      );
    }
    return actors[chatObjectId];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
