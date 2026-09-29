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
/// 只显示核心概览信息，头部主信息卡片采用通栏设计，与标题栏浑然一体，点击平滑进入详细资料卡。
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
    final tokens = context.appTokens;
    final data = ProfileData(subject);

    return SingleChildScrollView(
      controller: adaptiveController.scrollController,
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.only(
        bottom:
            MediaQuery.paddingOf(context).bottom +
            tokens.pagePaddingVertical * 2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // ── 1. 头部个人主信息（通栏，与标题栏一体） ──
          _ProfileSheetHeader(
            data: data,
            avatarUrl: subject.avatarUrl,
            tokens: tokens,
            onTap: () => _navigateToDetail(context),
          ),
          Divider(
            height: tokens.dividerThickness,
            thickness: tokens.dividerThickness,
            color: tokens.dividerBorder,
          ),
          SizedBox(height: tokens.pagePaddingVertical),

          // ── 2. 下方内容区域（带标准左右边距） ──
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: tokens.pagePaddingHorizontal,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _ProfileSheetContactSection(data: data, tokens: tokens),
                _ProfileSheetActions(
                  tokens: tokens,
                  onSendMessage: () {
                    adaptiveController.close();
                    onSendMessage?.call();
                  },
                  onCallMedia:
                      () => showMediaCallActionSheet(context, data.displayName),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 子组件拆分
// ─────────────────────────────────────────────────────────────────────────────

/// 头部个人主信息卡片（通栏设计）
class _ProfileSheetHeader extends StatelessWidget {
  const _ProfileSheetHeader({
    required this.data,
    required this.avatarUrl,
    required this.tokens,
    required this.onTap,
  });

  final ProfileData data;
  final String avatarUrl;
  final AppThemeTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            tokens.pagePaddingHorizontal,
            6,
            tokens.pagePaddingHorizontal,
            14,
          ),
          child: Row(
            children: <Widget>[
              // 头像
              ClipRRect(
                borderRadius: BorderRadius.circular(tokens.cardRadius),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: ChatObjectAvatar(
                    name: data.displayName,
                    imageUrl: avatarUrl.isEmpty ? null : avatarUrl,
                    radius: 28,
                    chatObjectId: data.chatObjectId,
                  ),
                ),
              ),
              SizedBox(width: tokens.pagePaddingHorizontal),
              // 中间信息列
              Expanded(
                child: _ProfileSheetHeaderInfo(data: data),
              ),
              // 右侧箭头
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
    );
  }
}

/// 头部文本信息列（姓名、性别徽章、账号、地区）
class _ProfileSheetHeaderInfo extends StatelessWidget {
  const _ProfileSheetHeaderInfo({required this.data});

  final ProfileData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondaryStyle = TextStyle(
      fontSize: 13.0,
      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
      height: 1.25,
    );

    return Column(
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
            Text('账号: ', style: secondaryStyle),
            Flexible(
              child: Text(
                data.accountCode.isEmpty ? '-' : data.accountCode,
                style: secondaryStyle,
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
            style: secondaryStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

/// 电话与签名联系资料组件
class _ProfileSheetContactSection extends StatelessWidget {
  const _ProfileSheetContactSection({
    required this.data,
    required this.tokens,
  });

  final ProfileData data;
  final AppThemeTokens tokens;

  @override
  Widget build(BuildContext context) {
    if (data.phone.isEmpty && data.description.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);

    return CellGroup(
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
    );
  }
}

/// 底部双操作按钮栏（发消息、音视频通话）
class _ProfileSheetActions extends StatelessWidget {
  const _ProfileSheetActions({
    required this.tokens,
    required this.onSendMessage,
    required this.onCallMedia,
  });

  final AppThemeTokens tokens;
  final VoidCallback onSendMessage;
  final VoidCallback onCallMedia;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GlassCard(
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(tokens.cardRadius),
      child: Column(
        children: <Widget>[
          _ActionItem(
            icon: Icons.chat_bubble_outline_rounded,
            iconSize: 19,
            label: '发消息',
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(tokens.cardRadius),
            ),
            onTap: onSendMessage,
          ),
          Divider(
            height: tokens.dividerThickness,
            thickness: tokens.dividerThickness,
            indent: 24,
            endIndent: 24,
            color: tokens.dividerBorder,
          ),
          _ActionItem(
            icon: Icons.videocam_outlined,
            iconSize: 21,
            label: '音视频通话',
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.vertical(
              bottom: Radius.circular(tokens.cardRadius),
            ),
            onTap: onCallMedia,
          ),
        ],
      ),
    );
  }
}

/// 独立按钮行组件
class _ActionItem extends StatelessWidget {
  const _ActionItem({
    required this.icon,
    required this.iconSize,
    required this.label,
    required this.color,
    required this.borderRadius,
    required this.onTap,
  });

  final IconData icon;
  final double iconSize;
  final String label;
  final Color color;
  final BorderRadius borderRadius;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: borderRadius,
      child: SizedBox(
        height: 48,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: iconSize, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
