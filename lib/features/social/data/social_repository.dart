import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/application_providers.dart';
import '../../../core/network/api_client.dart';

final socialRepositoryProvider = Provider<SocialRepository>(
  (ref) => SocialRepository(ref.watch(socialApiClientProvider)),
);

class SocialActor {
  const SocialActor({
    required this.id,
    required this.name,
    required this.handle,
    this.avatarUrl,
    this.followingCount = 0,
    this.followersCount = 0,
    this.postsCount = 0,
    this.isFollowing,
  });
  factory SocialActor.fromJson(Map<String, dynamic> json) => SocialActor(
    id: json['id'] as String,
    name: json['displayName'] as String? ?? '',
    handle: json['handle'] as String? ?? '',
    avatarUrl: json['avatarUrl'] as String?,
    followingCount: (json['followingCount'] as num?)?.toInt() ?? 0,
    followersCount: (json['followersCount'] as num?)?.toInt() ?? 0,
    postsCount: (json['postsCount'] as num?)?.toInt() ?? 0,
    isFollowing: json['isFollowing'] as bool?,
  );
  final String id;
  final String name;
  final String handle;
  final String? avatarUrl;
  final int followingCount;
  final int followersCount;
  final int postsCount;
  final bool? isFollowing;
}

class SocialPost {
  const SocialPost({
    required this.id,
    required this.content,
    this.author,
    this.publishedAt,
    this.likes = 0,
    this.replies = 0,
    this.mediaCount = 0,
  });
  factory SocialPost.fromJson(Map<String, dynamic> json) => SocialPost(
    id: json['id'] as String,
    content: json['content'] as String? ?? '',
    author:
        json['author'] is Map<String, dynamic>
            ? SocialActor.fromJson(json['author'] as Map<String, dynamic>)
            : null,
    publishedAt: DateTime.tryParse(
      (json['publishedTime'] ?? json['creationTime'] ?? '').toString(),
    ),
    likes: (json['likesCount'] as num?)?.toInt() ?? 0,
    replies: (json['repliesCount'] as num?)?.toInt() ?? 0,
    mediaCount:
        (json['medias'] as List?)?.length ??
        (json['mediaCount'] as num?)?.toInt() ??
        0,
  );
  final String id;
  final String content;
  final SocialActor? author;
  final DateTime? publishedAt;
  final int likes;
  final int replies;
  final int mediaCount;

  /// Small display-only payload for native-window IPC; never carries credentials.
  Map<String, dynamic> toWindowPayload() => {
    'id': id,
    'content': content,
    'publishedTime': publishedAt?.toIso8601String(),
    'likesCount': likes,
    'repliesCount': replies,
    'mediaCount': mediaCount,
    if (author != null)
      'author': {
        'id': author!.id,
        'displayName': author!.name,
        'handle': author!.handle,
        'avatarUrl': author!.avatarUrl,
      },
  };
}

class SocialFeedPage {
  const SocialFeedPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
    this.isPartial = false,
  });
  factory SocialFeedPage.fromJson(Map<String, dynamic> json) {
    final info = json['pageInfo'] as Map<String, dynamic>? ?? const {};
    return SocialFeedPage(
      items:
          (json['items'] as List? ?? const [])
              .map((item) => SocialPost.fromJson(item as Map<String, dynamic>))
              .toList(),
      nextCursor: info['nextCursor'] as String?,
      hasMore: info['hasMore'] == true,
      isPartial: info['isPartial'] == true,
    );
  }
  final List<SocialPost> items;
  final String? nextCursor;
  final bool hasMore;
  final bool isPartial;
}

/// Uses Social's dedicated authenticated transport and /api/social routes.
class SocialRepository {
  SocialRepository(this._api);
  final ApiClient _api;

  Future<SocialActor?> getChatObjectActor(
    int chatObjectId, {
    String? viewerActorId,
  }) async {
    final json = await _api.get<dynamic>(
      '/api/social/actor/for-chat-object',
      query: {
        'chatObjectId': chatObjectId,
        if (viewerActorId != null) 'viewerActorId': viewerActorId,
      },
    );
    return json == null
        ? null
        : SocialActor.fromJson(json as Map<String, dynamic>);
  }

  Future<SocialActor?> resolveChatObject(
    int chatObjectId, {
    bool create = false,
  }) async {
    final json = await _api.post<dynamic>(
      '/api/social/actor/resolve-chat-object',
      data: {'chatObjectId': chatObjectId, 'createIfMissing': create},
    );
    return json == null
        ? null
        : SocialActor.fromJson(json as Map<String, dynamic>);
  }

  Future<SocialFeedPage> getActorPosts({
    required String actorId,
    String? viewerActorId,
    int pageSize = 3,
    String? cursor,
  }) async => SocialFeedPage.fromJson(
    await _api.get<Map<String, dynamic>>(
      '/api/social/post/actor-posts',
      query: {
        'ActorId': actorId,
        if (viewerActorId != null) 'ViewerActorId': viewerActorId,
        if (viewerActorId == null) 'PublicOnly': true,
        'PageSize': pageSize,
        if (cursor != null) 'Cursor': cursor,
      },
    ),
  );

  Future<int> getUnreadCount(String actorId) =>
      _api.get<int>('/api/social/notification/unread-count/$actorId');

  Future<SocialNotificationPage> getNotifications(
    String actorId, {
    String? cursor,
  }) async => SocialNotificationPage.fromJson(
    await _api.get<Map<String, dynamic>>(
      '/api/social/notification',
      query: {
        'RecipientActorId': actorId,
        'PageSize': 20,
        if (cursor != null) 'Cursor': cursor,
      },
    ),
  );

  Future<void> markNotificationRead(String id) async {
    await _api.post<dynamic>('/api/social/notification/$id/mark-as-read');
  }

  Future<void> markAllNotificationsRead(String actorId) async {
    await _api.post<dynamic>(
      '/api/social/notification/mark-all-as-read/$actorId',
    );
  }

  Future<SocialPost> getPost(String id, String? actorId) async =>
      SocialPost.fromJson(
        await _api.get<Map<String, dynamic>>(
          '/api/social/post/$id',
          query: {
            if (actorId != null) 'viewerActorId': actorId,
            if (actorId == null) 'publicOnly': true,
          },
        ),
      );

  Future<SocialPost> publish({
    required String actorId,
    required String content,
    required String clientRequestId,
    int visibility = 0,
  }) async => SocialPost.fromJson(
    await _api.post<Map<String, dynamic>>(
      '/api/social/post',
      data: {
        'actorId': actorId,
        'content': content,
        'clientRequestId': clientRequestId,
        'postType': 0,
        'visibility': visibility,
        'replyPolicy': 0,
      },
    ),
  );

  Future<SocialActor> getMyActor() async => SocialActor.fromJson(
    await _api.get<Map<String, dynamic>>('/api/social/actor/my-actor'),
  );

  Future<SocialFeedPage> getFeed({
    required String actorId,
    required bool following,
    required String clientRequestId,
    String? cursor,
    int pageSize = 20,
  }) async => SocialFeedPage.fromJson(
    await _api.get<Map<String, dynamic>>(
      '/api/social/feed/${following ? 'following-feed' : 'for-you-feed'}',
      query: {
        'ViewerActorId': actorId,
        'PageSize': pageSize,
        if (!following) 'ClientRequestId': clientRequestId,
        if (cursor != null) 'Cursor': cursor,
      },
    ),
  );
}

class SocialNotification {
  const SocialNotification({
    required this.id,
    required this.type,
    required this.isRead,
    this.postId,
    this.content,
    this.createdAt,
  });
  factory SocialNotification.fromJson(Map<String, dynamic> json) =>
      SocialNotification(
        id: json['id'] as String,
        type: (json['notificationType'] as num).toInt(),
        isRead: json['isRead'] == true,
        postId: json['postId'] as String?,
        content: json['commentContent'] as String?,
        createdAt: DateTime.tryParse(json['creationTime']?.toString() ?? ''),
      );
  final String id;
  final int type;
  final bool isRead;
  final String? postId;
  final String? content;
  final DateTime? createdAt;
  String get title => switch (type) {
    1 => '有人关注了你',
    2 => '有人赞了你的动态',
    3 => '你收到了新回复',
    4 => '有人引用了你的动态',
    5 => '有人转发了你的动态',
    6 => '有人提到了你',
    _ => '新的社交通知',
  };
  SocialNotification read() => SocialNotification(
    id: id,
    type: type,
    isRead: true,
    postId: postId,
    content: content,
    createdAt: createdAt,
  );
}

class SocialNotificationPage {
  const SocialNotificationPage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });
  factory SocialNotificationPage.fromJson(Map<String, dynamic> json) {
    final info = json['pageInfo'] as Map<String, dynamic>? ?? const {};
    return SocialNotificationPage(
      items:
          (json['items'] as List? ?? [])
              .map(
                (item) =>
                    SocialNotification.fromJson(item as Map<String, dynamic>),
              )
              .toList(),
      nextCursor: info['nextCursor'] as String?,
      hasMore: info['hasMore'] == true,
    );
  }
  final List<SocialNotification> items;
  final String? nextCursor;
  final bool hasMore;
}
