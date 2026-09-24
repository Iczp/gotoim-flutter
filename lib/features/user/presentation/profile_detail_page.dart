import 'package:flutter/material.dart';

import '../../../core/theme/app_theme_tokens.dart';
import '../../../core/widgets/cell_group.dart';
import '../../../core/widgets/glass_container.dart';
import '../../session/presentation/chat_object_avatar.dart';
import '../data/models/profile_subject.dart';
import 'widgets/profile_action_sheets.dart';
import 'widgets/profile_gender_badge.dart';
import 'widgets/profile_media_thumbnails.dart';

/// 真正的资料卡详情页（ProfileDetailPage）
/// 全屏完整排版，包含朋友资料、朋友圈动态、视频号、扩展签名与全套操作。
class ProfileDetailPage extends StatelessWidget {
  const ProfileDetailPage({
    required this.subject,
    this.onSendMessage,
    super.key,
  });

  final ProfileSubject subject;
  final VoidCallback? onSendMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.appTokens;
    final data = ProfileData(subject);

    return Scaffold(
      appBar: AppBar(
        title: const Text('详细资料'),
        centerTitle: true,
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.more_horiz_rounded),
            tooltip: '更多选项',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('更多资料设置'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: tokens.pagePaddingHorizontal,
          vertical: tokens.pagePaddingVertical,
        ),
        children: <Widget>[
          // ── 1. 头部个人大卡片 ──
          GlassCard(
            margin: EdgeInsets.only(bottom: tokens.pagePaddingVertical),
            padding: EdgeInsets.all(tokens.pagePaddingHorizontal),
            borderRadius: BorderRadius.circular(tokens.cardRadius),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(tokens.cardRadius),
                  child: SizedBox(
                    width: 62,
                    height: 62,
                    child: ChatObjectAvatar(
                      name: data.displayName,
                      imageUrl:
                          subject.avatarUrl.isEmpty ? null : subject.avatarUrl,
                      radius: 31,
                      chatObjectId: data.chatObjectId,
                    ),
                  ),
                ),
                SizedBox(width: tokens.pagePaddingHorizontal),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              data.displayName,
                              style: const TextStyle(
                                fontSize: 18.5,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (data.gender != 0) ...[
                            const SizedBox(width: 6),
                            ProfileGenderBadge(gender: data.gender),
                          ],
                        ],
                      ),
                      const SizedBox(height: 5),
                      if (data.showNickname) ...[
                        Text(
                          '昵称: ${data.originalNickname}',
                          style: TextStyle(
                            fontSize: 13.0,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.75),
                            height: 1.25,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                      ],
                      Row(
                        children: <Widget>[
                          Text(
                            '微信号: ',
                            style: TextStyle(
                              fontSize: 13.0,
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.75),
                              height: 1.25,
                            ),
                          ),
                          Flexible(
                            child: Text(
                              data.accountCode.isEmpty ? '-' : data.accountCode,
                              style: TextStyle(
                                fontSize: 13.0,
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.75),
                                height: 1.25,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '地区: ${data.region.isEmpty ? '中国' : data.region}',
                        style: TextStyle(
                          fontSize: 13.0,
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.75),
                          height: 1.25,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── 2. 朋友资料分组（设置备注和标签、电话） ──
          CellGroup(
            margin: EdgeInsets.only(bottom: tokens.pagePaddingVertical),
            borderRadius: BorderRadius.circular(tokens.cardRadius),
            children: <Widget>[
              Cell(
                title: '朋友资料',
                showArrow: true,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('朋友资料与标签设置'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
              Cell(
                title: '电话',
                valueWidget: Text(
                  data.phone.isNotEmpty ? data.phone : '未填写',
                  style: TextStyle(
                    fontSize: 14.5,
                    color:
                        data.phone.isNotEmpty
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.6,
                            ),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                trailing:
                    data.phone.isNotEmpty
                        ? Icon(
                          Icons.phone_outlined,
                          size: 19,
                          color: theme.colorScheme.primary,
                        )
                        : null,
                onTap:
                    data.phone.isNotEmpty
                        ? () => showPhoneActionSheet(context, data.phone)
                        : null,
              ),
            ],
          ),

          // ── 3. 朋友圈动态分组（与本项目统一风格的缩略矩阵） ──
          CellGroup(
            margin: EdgeInsets.only(bottom: tokens.pagePaddingVertical),
            borderRadius: BorderRadius.circular(tokens.cardRadius),
            children: <Widget>[
              Cell(
                title: '朋友圈',
                showArrow: true,
                valueWidget: SizedBox(
                  height: 38,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      ProfileMomentThumbnail(
                        color: theme.colorScheme.primaryContainer,
                        icon: Icons.image_rounded,
                        tokens: tokens,
                      ),
                      const SizedBox(width: 5),
                      ProfileMomentThumbnail(
                        color: theme.colorScheme.secondaryContainer,
                        icon: Icons.play_arrow_rounded,
                        isVideo: true,
                        tokens: tokens,
                      ),
                      const SizedBox(width: 5),
                      ProfileMomentThumbnail(
                        color: theme.colorScheme.tertiaryContainer,
                        icon: Icons.camera_alt_outlined,
                        tokens: tokens,
                      ),
                    ],
                  ),
                ),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('查看朋友圈'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
            ],
          ),

          // ── 4. 视频号分组（与本项目统一多媒体封面风格） ──
          CellGroup(
            margin: EdgeInsets.only(bottom: tokens.pagePaddingVertical),
            borderRadius: BorderRadius.circular(tokens.cardRadius),
            children: <Widget>[
              Cell(
                title: '视频号',
                showArrow: true,
                subtitleWidget: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: <Widget>[
                      ProfileVideoThumbnail(
                        color: theme.colorScheme.surfaceContainerHighest,
                        tokens: tokens,
                      ),
                      const SizedBox(width: 6),
                      ProfileVideoThumbnail(
                        color: theme.colorScheme.surfaceContainerHighest,
                        tokens: tokens,
                      ),
                      const SizedBox(width: 6),
                      ProfileVideoThumbnail(
                        color: theme.colorScheme.surfaceContainerHighest,
                        tokens: tokens,
                      ),
                    ],
                  ),
                ),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('查看视频号'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
            ],
          ),

          // ── 5. 个性签名分组 ──
          if (data.description.isNotEmpty)
            CellGroup(
              margin: EdgeInsets.only(bottom: tokens.pagePaddingVertical),
              borderRadius: BorderRadius.circular(tokens.cardRadius),
              children: <Widget>[
                Cell(
                  title: '个性签名',
                  subtitle: data.description,
                  showArrow: false,
                ),
              ],
            ),

          const SizedBox(height: 6),

          // ── 6. 底部双操作栏（发消息与音视频通话） ──
          GlassCard(
            margin: EdgeInsets.only(
              bottom:
                  MediaQuery.paddingOf(context).bottom +
                  tokens.pagePaddingVertical * 2,
            ),
            padding: EdgeInsets.zero,
            borderRadius: BorderRadius.circular(tokens.cardRadius),
            child: Column(
              children: <Widget>[
                InkWell(
                  onTap: () {
                    Navigator.of(context).pop();
                    onSendMessage?.call();
                  },
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(tokens.cardRadius),
                  ),
                  child: SizedBox(
                    height: 50,
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 20,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '发消息',
                            style: TextStyle(
                              fontSize: 16.0,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Divider(
                  height: tokens.dividerThickness,
                  thickness: tokens.dividerThickness,
                  indent: 28,
                  endIndent: 28,
                  color: tokens.dividerBorder,
                ),
                InkWell(
                  onTap:
                      () => showMediaCallActionSheet(context, data.displayName),
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(tokens.cardRadius),
                  ),
                  child: SizedBox(
                    height: 50,
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            Icons.videocam_outlined,
                            size: 22,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '音视频通话',
                            style: TextStyle(
                              fontSize: 16.0,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
