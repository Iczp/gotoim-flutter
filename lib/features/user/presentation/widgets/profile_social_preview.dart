import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../social/application/social_profile_preview.dart';
import '../../../social/data/social_repository.dart';
import '../../../social/presentation/social_page.dart';
import '../../data/models/profile_subject.dart';

/// Shared real-data preview for compact, full-page and desktop profile cards.
class ProfileSocialPreview extends ConsumerWidget {
  const ProfileSocialPreview({required this.subject, super.key});
  final ProfileSubject subject;

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    SocialPost post,
    String? viewer,
  ) async {
    final request = ref.read(socialRepositoryProvider).getPost(post.id, viewer);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder:
          (context) => SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .7,
              child: FutureBuilder<SocialPost>(
                future: request,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(child: Text('动态已不可用或无权查看。'));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return SingleChildScrollView(
                    child: SocialPostCard(post: snapshot.data!),
                  );
                },
              ),
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (subject.kind == ProfileKind.group) return const SizedBox.shrink();
    final target = socialTargetForProfile(subject);
    final preview = ref.watch(socialProfilePreviewProvider(target));
    return Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.dynamic_feed_outlined, size: 18),
                const SizedBox(width: 8),
                Text('动态', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                const Text('最近三条'),
                IconButton(
                  tooltip: '刷新动态',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed:
                      () =>
                          ref.invalidate(socialProfilePreviewProvider(target)),
                ),
              ],
            ),
            preview.when(
              skipLoadingOnRefresh: false,
              skipLoadingOnReload: false,
              loading: () => const LinearProgressIndicator(),
              error:
                  (error, stack) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(error is ApiException ? error.message : '动态加载失败'),
                      TextButton(
                        onPressed:
                            () => ref.invalidate(
                              socialProfilePreviewProvider(target),
                            ),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
              data: (data) {
                if (data.actor == null) {
                  return const Text(
                    '尚未关联 Social 身份',
                    style: TextStyle(fontSize: 12),
                  );
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          Text('关注 ${data.actor!.followingCount}'),
                          Text('粉丝 ${data.actor!.followersCount}'),
                          Text(
                            data.viewerActorId == data.actor!.id
                                ? '当前社区身份'
                                : data.actor!.isFollowing == true
                                ? '已关注'
                                : data.actor!.isFollowing == false
                                ? '未关注'
                                : '尚未选择社区身份',
                          ),
                        ],
                      ),
                    ),
                    if (data.posts.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('暂无可见动态', style: TextStyle(fontSize: 12)),
                      ),
                    for (final post in data.posts.take(3))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(
                          post.content.isNotEmpty
                              ? post.content
                              : post.mediaCount > 0
                              ? '包含 ${post.mediaCount} 个媒体附件'
                              : '动态',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          [
                            if (post.publishedAt != null)
                              post.publishedAt!
                                  .toLocal()
                                  .toString()
                                  .split('.')
                                  .first,
                            '赞 ${post.likes}',
                            '回复 ${post.replies}',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right, size: 16),
                        onTap:
                            () => _open(context, ref, post, data.viewerActorId),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
