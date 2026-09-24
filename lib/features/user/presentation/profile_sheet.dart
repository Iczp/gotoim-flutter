import 'package:flutter/material.dart';

import '../../../core/theme/app_theme_tokens.dart';
import '../../../core/ui/adaptive_page/adaptive_page_controller.dart';
import '../../../core/widgets/cell_group.dart';
import '../../../core/widgets/glass_container.dart';
import '../../session/presentation/chat_object_avatar.dart';
import '../data/models/profile_subject.dart';
import 'profile_detail_page.dart';
import 'widgets/profile_action_sheets.dart';
import 'widgets/profile_gender_badge.dart';

/// 半屏轻量资料卡（ProfileSheet）
/// 只显示核心概览信息，头部主信息卡片右侧带指示箭头，点击平滑进入详细资料卡。
class ProfileSheet extends StatelessWidget {
  const ProfileSheet({
    required this.subject,
    required this.adaptiveController,
    this.onSendMessage,
    super.key,
  });

  final ProfileSubject subject;
  final AdaptivePageController adaptiveController;
  final VoidCallback? onSendMessage;

  void _navigateToDetail(BuildContext context) {
    adaptiveController.close();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (context) => ProfileDetailPage(
              subject: subject,
              onSendMessage: onSendMessage,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.appTokens;
    final data = ProfileData(subject);

    return SingleChildScrollView(
      controller: adaptiveController.scrollController,
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        tokens.pagePaddingHorizontal,
        tokens.pagePaddingVertical,
        tokens.pagePaddingHorizontal,
        MediaQuery.paddingOf(context).bottom + tokens.pagePaddingVertical * 2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // ── 头部个人主信息卡片（可点击进入详情，右侧带箭头） ──
          GlassCard(
            margin: EdgeInsets.only(bottom: tokens.pagePaddingVertical),
            padding: EdgeInsets.all(tokens.pagePaddingHorizontal),
            borderRadius: BorderRadius.circular(tokens.cardRadius),
            child: InkWell(
              onTap: () => _navigateToDetail(context),
              borderRadius: BorderRadius.circular(tokens.cardRadius),
              child: Row(
                children: <Widget>[
                  // 头像（统一卡片圆角）
                  ClipRRect(
                    borderRadius: BorderRadius.circular(tokens.cardRadius),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: ChatObjectAvatar(
                        name: data.displayName,
                        imageUrl:
                            subject.avatarUrl.isEmpty
                                ? null
                                : subject.avatarUrl,
                        radius: 28,
                        chatObjectId: data.chatObjectId,
                      ),
                    ),
                  ),
                  SizedBox(width: tokens.pagePaddingHorizontal),
                  // 中间信息
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
                                  fontSize: 17.5,
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
                        const SizedBox(height: 4),
                        Row(
                          children: <Widget>[
                            Text(
                              '账号: ',
                              style: TextStyle(
                                fontSize: 13.0,
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.75),
                                height: 1.25,
                              ),
                            ),
                            Flexible(
                              child: Text(
                                data.accountCode.isEmpty
                                    ? '-'
                                    : data.accountCode,
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
                        if (data.region.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            '地区: ${data.region}',
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
                      ],
                    ),
                  ),
                  // 右侧箭头（提示点击进入完整详情）
                  Icon(
                    Icons.chevron_right_rounded,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.5,
                    ),
                    size: 22,
                  ),
                ],
              ),
            ),
          ),

          // ── 半屏轻量内容区（电话 / 简介，使用统一 CellGroup） ──
          if (data.phone.isNotEmpty || data.description.isNotEmpty)
            CellGroup(
              margin: EdgeInsets.only(bottom: tokens.pagePaddingVertical),
              borderRadius: BorderRadius.circular(tokens.cardRadius),
              children: <Widget>[
                if (data.phone.isNotEmpty)
                  Cell(
                    title: '电话',
                    valueWidget: Text(
                      data.phone,
                      style: TextStyle(
                        fontSize: 14.5,
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    icon: const Icon(Icons.phone_outlined, size: 19),
                    onTap: () => showPhoneActionSheet(context, data.phone),
                  ),
                if (data.description.isNotEmpty)
                  Cell(
                    title: '签名',
                    subtitle: data.description,
                    icon: const Icon(Icons.edit_note_rounded, size: 20),
                    showArrow: false,
                  ),
              ],
            ),

          // ── 底部双操作按钮卡片（发消息、音视频通话） ──
          GlassCard(
            margin: EdgeInsets.zero,
            padding: EdgeInsets.zero,
            borderRadius: BorderRadius.circular(tokens.cardRadius),
            child: Column(
              children: <Widget>[
                InkWell(
                  onTap: () {
                    adaptiveController.close();
                    onSendMessage?.call();
                  },
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(tokens.cardRadius),
                  ),
                  child: SizedBox(
                    height: 48,
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 19,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '发消息',
                            style: TextStyle(
                              fontSize: 15.5,
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
                  indent: 24,
                  endIndent: 24,
                  color: tokens.dividerBorder,
                ),
                InkWell(
                  onTap:
                      () => showMediaCallActionSheet(context, data.displayName),
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(tokens.cardRadius),
                  ),
                  child: SizedBox(
                    height: 48,
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            Icons.videocam_outlined,
                            size: 21,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '音视频通话',
                            style: TextStyle(
                              fontSize: 15.5,
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
