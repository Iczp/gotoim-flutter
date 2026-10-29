import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:typed_data';

import '../../../app/application_providers.dart';
import '../../../core/network/api_client.dart';
import '../application/social_identity_controller.dart';

final socialRepositoryProvider = Provider<SocialRepository>(
  (ref) => SocialRepository(ref.watch(socialApiClientProvider)),
);

final socialMediaBytesProvider = FutureProvider.autoDispose
    .family<Uint8List, ({String path, String? actorId})>((ref, request) async {
  // Dispose authenticated images when the selected social identity changes.
  ref.watch(socialIdentityProvider.select((value) => value.actor?.id));
  final uri = Uri.parse(request.path);
  final query = <String, String>{...uri.queryParameters};
  if (request.actorId != null) query['viewerActorId'] = request.actorId!;
  final path = uri.replace(queryParameters: query.isEmpty ? null : query).toString();
  return Uint8List.fromList(await ref.watch(socialApiClientProvider).getBytes(path));
});

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
    this.isVerified = false,
  });
  factory SocialActor.fromJson(Map<String, dynamic> json) => SocialActor(
    id: json['id'] as String,
    name: json['displayName'] as String? ?? json['name'] as String? ?? '',
    handle: json['handle'] as String? ?? '',
    avatarUrl: json['avatarUrl'] as String?,
    followingCount: (json['followingCount'] as num?)?.toInt() ?? 0,
    followersCount: (json['followersCount'] as num?)?.toInt() ?? 0,
    postsCount: (json['postsCount'] as num?)?.toInt() ?? 0,
    isFollowing: json['isFollowing'] as bool?,
    isVerified: json['isVerified'] == true || (json['isOfficial'] == true),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': name,
    'handle': handle,
    'avatarUrl': avatarUrl,
    'followingCount': followingCount,
    'followersCount': followersCount,
    'postsCount': postsCount,
    'isFollowing': isFollowing,
    'isVerified': isVerified,
  };
  final String id;
  final String name;
  final String handle;
  final String? avatarUrl;
  final int followingCount;
  final int followersCount;
  final int postsCount;
  final bool? isFollowing;
  final bool isVerified;
}

class SocialPostMedia {
  const SocialPostMedia({
    required this.id,
    required this.url,
    this.thumbnailUrl,
    this.mediaType = 0, // 0: Image, 1: Video, 2: Audio
    this.width,
    this.height,
    this.durationSeconds,
    this.altText,
    this.sortOrder = 0,
  });

  factory SocialPostMedia.fromJson(Map<String, dynamic> json) =>
      SocialPostMedia(
        id: json['id']?.toString() ?? '',
        url: json['url'] as String? ?? '',
        thumbnailUrl: json['thumbnailUrl'] as String?,
        mediaType: (json['mediaType'] as num?)?.toInt() ?? 0,
        width: (json['width'] as num?)?.toInt(),
        height: (json['height'] as num?)?.toInt(),
        durationSeconds: (json['durationSeconds'] as num?)?.toInt(),
        altText: json['altText'] as String?,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'thumbnailUrl': thumbnailUrl,
    'mediaType': mediaType,
    'width': width,
    'height': height,
    'durationSeconds': durationSeconds,
    'altText': altText,
    'sortOrder': sortOrder,
  };

  final String id;
  final String url;
  final String? thumbnailUrl;
  final int mediaType;
  final int? width;
  final int? height;
  final int? durationSeconds;
  final String? altText;
  final int sortOrder;

  bool get isVideo => mediaType == 1;
}

class SocialPost {
  const SocialPost({
    required this.id,
    required this.content,
    this.author,
    this.publishedAt,
    this.likes = 0,
    this.replies = 0,
    this.reposts = 0,
    this.views = 0,
    this.mediaCount = 0,
    this.medias = const [],
    this.isLiked = false,
    this.isBookmarked = false,
    this.parentId,
    this.rootPostId,
    this.replyToActorId,
    this.replyToAuthorName,
    this.visibility = 0,
  });

  factory SocialPost.fromJson(Map<String, dynamic> json) {
    final mediaList =
        (json['medias'] as List?)
            ?.map((m) => SocialPostMedia.fromJson(m as Map<String, dynamic>))
            .toList() ??
        const [];
    return SocialPost(
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
      reposts: (json['repostsCount'] as num?)?.toInt() ?? 0,
      views: (json['viewsCount'] as num?)?.toInt() ?? 0,
      mediaCount:
          mediaList.isNotEmpty
              ? mediaList.length
              : (json['mediaCount'] as num?)?.toInt() ?? 0,
      medias: mediaList,
      isLiked: json['isLiked'] == true,
      isBookmarked: json['isBookmarked'] == true,
      parentId: json['parentId'] as String?,
      rootPostId: json['rootPostId'] as String?,
      replyToActorId: json['replyToActorId'] as String?,
      replyToAuthorName: json['replyToAuthorName'] as String?,
      visibility: (json['visibility'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String content;
  final SocialActor? author;
  final DateTime? publishedAt;
  final int likes;
  final int replies;
  final int reposts;
  final int views;
  final int mediaCount;
  final List<SocialPostMedia> medias;
  final bool isLiked;
  final bool isBookmarked;
  final String? parentId;
  final String? rootPostId;
  final String? replyToActorId;
  final String? replyToAuthorName;
  final int visibility;

  SocialPost copyWith({
    String? id,
    String? content,
    SocialActor? author,
    DateTime? publishedAt,
    int? likes,
    int? replies,
    int? reposts,
    int? views,
    int? mediaCount,
    List<SocialPostMedia>? medias,
    bool? isLiked,
    bool? isBookmarked,
    String? parentId,
    String? rootPostId,
    String? replyToActorId,
    String? replyToAuthorName,
    int? visibility,
  }) => SocialPost(
    id: id ?? this.id,
    content: content ?? this.content,
    author: author ?? this.author,
    publishedAt: publishedAt ?? this.publishedAt,
    likes: likes ?? this.likes,
    replies: replies ?? this.replies,
    reposts: reposts ?? this.reposts,
    views: views ?? this.views,
    mediaCount: mediaCount ?? this.mediaCount,
    medias: medias ?? this.medias,
    isLiked: isLiked ?? this.isLiked,
    isBookmarked: isBookmarked ?? this.isBookmarked,
    parentId: parentId ?? this.parentId,
    rootPostId: rootPostId ?? this.rootPostId,
    replyToActorId: replyToActorId ?? this.replyToActorId,
    replyToAuthorName: replyToAuthorName ?? this.replyToAuthorName,
    visibility: visibility ?? this.visibility,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'publishedTime': publishedAt?.toIso8601String(),
    'likesCount': likes,
    'repliesCount': replies,
    'repostsCount': reposts,
    'viewsCount': views,
    'mediaCount': mediaCount,
    'medias': medias.map((m) => m.toJson()).toList(),
    'isLiked': isLiked,
    'isBookmarked': isBookmarked,
    'parentId': parentId,
    'rootPostId': rootPostId,
    'replyToActorId': replyToActorId,
    'replyToAuthorName': replyToAuthorName,
    'visibility': visibility,
    if (author != null) 'author': author!.toJson(),
  };

  /// Small display-only payload for native-window IPC; never carries credentials.
  Map<String, dynamic> toWindowPayload() => {
    'id': id,
    'content': content,
    'publishedTime': publishedAt?.toIso8601String(),
    'likesCount': likes,
    'repliesCount': replies,
    'repostsCount': reposts,
    'viewsCount': views,
    'mediaCount': mediaCount,
    'medias': medias.map((m) => m.toJson()).toList(),
    'isLiked': isLiked,
    'isBookmarked': isBookmarked,
    if (author != null)
      'author': {
        'id': author!.id,
        'displayName': author!.name,
        'handle': author!.handle,
        'avatarUrl': author!.avatarUrl,
        'isVerified': author!.isVerified,
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
    return json == null || json == ''
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
    return json == null || json == ''
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
    List<Map<String, dynamic>>? medias,
  }) => createPost(
    actorId: actorId,
    content: content,
    clientRequestId: clientRequestId,
    visibility: visibility,
    medias: medias,
  );

  Future<Map<String, dynamic>> uploadMedia(
    String actorId,
    MultipartUploadFile file, {
    void Function(int sent, int total)? onProgress,
  }) => _api.postMultipart<Map<String, dynamic>>(
    "/api/social/media-assets/upload",
    file: file,
    onProgress: onProgress,
    extraFields: {"ownerActorId": actorId, "mediaType": 0},
  );

  Future<SocialPost> createPost({
    required String actorId,
    required String content,
    required String clientRequestId,
    int visibility = 0,
    List<Map<String, dynamic>>? medias,
    String? parentId,
    String? replyToActorId,
  }) async => SocialPost.fromJson(
    await _api.post<Map<String, dynamic>>(
      '/api/social/post',
      data: {
        'actorId': actorId,
        'content': content,
        'clientRequestId': clientRequestId,
        'postType': parentId != null ? 3 : 0,
        'visibility': visibility,
        'replyPolicy': 0,
        if (parentId != null) 'parentId': parentId,
        if (replyToActorId != null) 'replyToActorId': replyToActorId,
        if (medias != null && medias.isNotEmpty) 'medias': medias,
      },
    ),
  );

  Future<void> likePost(String actorId, String postId) async {
    await _api.post<dynamic>(
      '/api/social/post/$postId/like',
      query: {'actorId': actorId},
    );
  }

  Future<void> unlikePost(String actorId, String postId) async {
    await _api.post<dynamic>(
      '/api/social/post/$postId/unlike',
      query: {'actorId': actorId},
    );
  }

  Future<void> bookmarkPost(String actorId, String postId) async {
    await _api.post<dynamic>(
      '/api/social/post/$postId/bookmark',
      query: {'actorId': actorId},
    );
  }

  Future<void> unbookmarkPost(String actorId, String postId) async {
    await _api.post<dynamic>(
      '/api/social/post/$postId/unbookmark',
      query: {'actorId': actorId},
    );
  }

  Future<SocialFeedPage> getReplies({
    required String postId,
    String? viewerActorId,
    int pageSize = 20,
    String? cursor,
  }) async => SocialFeedPage.fromJson(
    await _api.get<Map<String, dynamic>>(
      '/api/social/post/replies',
      query: {
        'PostId': postId,
        if (viewerActorId != null) 'ViewerActorId': viewerActorId,
        'PageSize': pageSize,
        if (cursor != null) 'Cursor': cursor,
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
