import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import 'social_identity_controller.dart';
import '../../user/data/models/profile_subject.dart';
import '../data/social_repository.dart';

typedef SocialProfileTarget = ({int? chatObjectId});

/// A session's destination or a group member's owner is the target, never the
/// current session owner, nickname or a guessed Social Actor ID.
SocialProfileTarget socialTargetForProfile(ProfileSubject subject) {
  final raw = subject.raw;
  final nested =
      subject.kind == ProfileKind.member
          ? raw['owner']
          : subject.kind == ProfileKind.friend
          ? raw['destination']
          : null;
  final target = nested is Map ? Map<String, dynamic>.from(nested) : raw;
  final candidate =
      nested is Map
          ? target['id']
          : subject.kind == ProfileKind.friend
          ? raw['destinationId'] ?? raw['id']
          : raw['id'];
  final id = int.tryParse((candidate ?? subject.id).toString());
  return (chatObjectId: id != null && id > 0 ? id : null);
}

class SocialProfilePreview {
  const SocialProfilePreview({
    this.actor,
    this.viewerActorId,
    this.posts = const [],
  });
  final SocialActor? actor;
  final String? viewerActorId;
  final List<SocialPost> posts;
}

final socialProfilePreviewProvider = FutureProvider.autoDispose
    .family<SocialProfilePreview, SocialProfileTarget>((ref, target) async {
      ref.watch(
        authControllerProvider.select(
          (auth) => (auth.status, auth.currentUser?.id),
        ),
      );
      final repository = ref.watch(socialRepositoryProvider);
      final viewer = ref.watch(
        socialIdentityProvider.select(
          (identity) => (identity.chatObjectId, identity.actor),
        ),
      );
      if (target.chatObjectId == null) return const SocialProfilePreview();
      final actor = await repository.getChatObjectActor(
        target.chatObjectId!,
        viewerActorId: viewer.$2?.id,
      );
      if (actor == null) return const SocialProfilePreview();
      final page = await repository.getActorPosts(
        actorId: actor.id,
        viewerActorId: viewer.$2?.id,
        pageSize: 3,
      );
      return SocialProfilePreview(
        actor: actor,
        viewerActorId: viewer.$2?.id,
        posts: page.items.take(3).toList(growable: false),
      );
    });
