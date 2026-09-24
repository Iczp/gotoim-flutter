import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/native/native.dart';
import '../../../core/theme/app_theme_tokens.dart';
import '../../../core/ui/adaptive_page/adaptive_page.dart';
import '../../../core/ui/adaptive_page/adaptive_page_config.dart';
import '../../../core/ui/adaptive_page/adaptive_page_controller.dart';
import '../../../core/ui/adaptive_page/adaptive_page_presentation.dart';
import '../../../core/widgets/cell_group.dart';
import '../../../core/widgets/glass_container.dart';
import '../../chat_settings/data/models/chat_member.dart';
import '../../contact/data/models/contact_group.dart';
import '../../session/data/models/chat_owner.dart';
import '../../session/data/models/session_summary.dart';
import '../../session/data/models/session_summary_helpers.dart';
import '../../session/presentation/chat_object_avatar.dart';

enum ProfileKind { user, friend, group, member }

@immutable
class ProfileSubject {
  const ProfileSubject({
    required this.kind,
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.raw,
    this.subtitle = '',
    this.editableAvatar = false,
  });

  factory ProfileSubject.member(ChatMember member) => ProfileSubject(
    kind: ProfileKind.member,
    id: member.id,
    name: member.name,
    avatarUrl: member.avatarUrl,
    subtitle: member.isCreator ? '群主' : '会话成员',
    raw: member.raw,
  );

  factory ProfileSubject.contact(ContactEntry contact) => ProfileSubject(
    kind: contact.objectType == 2 ? ProfileKind.group : ProfileKind.friend,
    id: contact.id,
    name: contact.displayName,
    avatarUrl: contact.avatarUrl,
    subtitle: contact.objectType == 2 ? '群聊' : '好友',
    raw: contact.raw,
  );

  factory ProfileSubject.session(SessionSummary session) => ProfileSubject(
    kind: session.ownerObjectType == 2 ? ProfileKind.group : ProfileKind.friend,
    id: session.id,
    name: session.title,
    avatarUrl: _sessionAvatar(session.raw),
    subtitle: session.ownerObjectType == 2 ? '群聊资料' : '好友资料',
    raw: session.raw,
  );

  factory ProfileSubject.owner(ChatOwner owner) => ProfileSubject(
    kind: ProfileKind.user,
    id: '${owner.id}',
    name: owner.name,
    avatarUrl: owner.imageUrl ?? '',
    subtitle: owner.typeDescription,
    raw: <String, dynamic>{
      'id': owner.id,
      'displayName': owner.name,
      'objectTypeDescription': owner.typeDescription,
    },
    editableAvatar: true,
  );

  final ProfileKind kind;
  final String id;
  final String name;
  final String avatarUrl;
  final String subtitle;
  final Map<String, dynamic> raw;
  final bool editableAvatar;
}

String _sessionAvatar(Map<String, dynamic> raw) {
  final destination = asMap(raw['destination']);
  final owner = asMap(raw['owner']);
  return firstNonEmpty(<Object?>[
    destination['thumbnail'],
    destination['portrait'],
    owner['thumbnail'],
    owner['portrait'],
  ]);
}

/// 解析资料卡结构化数据的 Helper
class _ProfileData {
  _ProfileData(ProfileSubject subject) {
    final owner = asMap(subject.raw['owner']);
    final destination = asMap(subject.raw['destination']);
    final setting = asMap(subject.raw['setting']);

    displayName = subject.name;
    originalNickname = firstNonEmpty(<Object?>[
      owner['displayName'],
      owner['name'],
      subject.raw['nickname'],
      destination['memberName'],
      setting['memberName'],
    ]);
    showNickname =
        originalNickname.isNotEmpty && originalNickname != displayName;

    accountCode = firstNonEmpty(<Object?>[
      owner['code'],
      subject.raw['code'],
      subject.id,
    ]);

    region = firstNonEmpty(<Object?>[
      owner['area'],
      owner['region'],
      subject.raw['area'],
      subject.raw['region'],
    ]);

    phone = firstNonEmpty(<Object?>[
      owner['phone'],
      owner['phoneNumber'],
      subject.raw['phone'],
      subject.raw['phoneNumber'],
    ]);

    gender = asInt(owner['gender']) ?? asInt(subject.raw['gender']) ?? 0;

    description = firstNonEmpty(<Object?>[
      owner['description'],
      subject.raw['description'],
    ]);

    chatObjectId =
        asInt(destination['id']) ??
        asInt(subject.raw['destinationId']) ??
        asInt(subject.raw['id']);

    isGroup = subject.kind == ProfileKind.group;
  }

  late final String displayName;
  late final String originalNickname;
  late final bool showNickname;
  late final String accountCode;
  late final String region;
  late final String phone;
  late final int gender; // 1: 男, 2: 女, 0: 未知
  late final String description;
  late final int? chatObjectId;
  late final bool isGroup;
}

/// 以半屏轻量资料卡方式自适应弹出（手机端半屏，宽屏侧栏或全屏）
Future<void> openProfilePage(
  BuildContext context, {
  required ProfileSubject subject,
  VoidCallback? onSendMessage,
}) async {
  await AdaptivePage.open<void>(
    context,
    config: AdaptivePageConfig(
      title: _titleFor(subject.kind),
      sheetSizingMode: AdaptiveSheetSizingMode.content,
      maxContentHeightFactor: .78,
      sheetBorderRadius: 16,
      showDragHandle: true,
      showCloseButton: true,
      fullPageMinWidth: 720,
    ),
    builder:
        (context, controller) => ProfileSheet(
          subject: subject,
          adaptiveController: controller,
          onSendMessage: onSendMessage,
        ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. 半屏轻量资料卡（ProfileSheet）
//    只显示核心信息，头部个人主信息卡片右侧带箭头，点击推进到真正的详细资料卡。
// ─────────────────────────────────────────────────────────────────────────────

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
    final data = _ProfileData(subject);

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
                  // 头像（与本项目统一圆角）
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
                              _buildGenderBadge(data.gender),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '账号: ${data.accountCode.isEmpty ? '-' : data.accountCode}',
                          style: TextStyle(
                            fontSize: 13.0,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.75),
                            height: 1.25,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                    onTap: () => _handleCallPhone(context, data.phone),
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
                  onTap: () => _handleCallMedia(context, data.displayName),
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

// ─────────────────────────────────────────────────────────────────────────────
// 2. 真正的资料卡详情页（ProfileDetailPage）
//    全屏完整排版，包含朋友资料、朋友圈动态、视频号、扩展签名与全套操作。
// ─────────────────────────────────────────────────────────────────────────────

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
    final data = _ProfileData(subject);

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
                            _buildGenderBadge(data.gender),
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
                      Text(
                        '微信号: ${data.accountCode.isEmpty ? '-' : data.accountCode}',
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
                        ? () => _handleCallPhone(context, data.phone)
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
                      _buildMomentThumbnail(
                        context,
                        color: theme.colorScheme.primaryContainer,
                        icon: Icons.image_rounded,
                        tokens: tokens,
                      ),
                      const SizedBox(width: 5),
                      _buildMomentThumbnail(
                        context,
                        color: theme.colorScheme.secondaryContainer,
                        icon: Icons.play_arrow_rounded,
                        isVideo: true,
                        tokens: tokens,
                      ),
                      const SizedBox(width: 5),
                      _buildMomentThumbnail(
                        context,
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
                      _buildVideoThumbnail(
                        context,
                        theme.colorScheme.surfaceContainerHighest,
                        tokens,
                      ),
                      const SizedBox(width: 6),
                      _buildVideoThumbnail(
                        context,
                        theme.colorScheme.surfaceContainerHighest,
                        tokens,
                      ),
                      const SizedBox(width: 6),
                      _buildVideoThumbnail(
                        context,
                        theme.colorScheme.surfaceContainerHighest,
                        tokens,
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
                  onTap: () => _handleCallMedia(context, data.displayName),
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

// ─────────────────────────────────────────────────────────────────────────────
// 公共视觉组件 & 交互方法
// ─────────────────────────────────────────────────────────────────────────────

Widget _buildGenderBadge(int gender) {
  final isFemale = gender == 2;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1.5),
    decoration: BoxDecoration(
      color: isFemale ? const Color(0xFFF99788) : const Color(0xFF32BBFB),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Icon(
      isFemale ? Icons.female : Icons.male,
      size: 11.5,
      color: Colors.white,
    ),
  );
}

Widget _buildMomentThumbnail(
  BuildContext context, {
  required Color color,
  required IconData icon,
  required AppThemeTokens tokens,
  bool isVideo = false,
}) {
  return Container(
    width: 38,
    height: 38,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(tokens.cardRadius * 0.35),
    ),
    child: Stack(
      alignment: Alignment.center,
      children: <Widget>[
        Icon(
          icon,
          size: 19,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
        if (isVideo)
          Positioned(
            right: 2,
            bottom: 2,
            child: Container(
              padding: const EdgeInsets.all(1),
              decoration: const BoxDecoration(
                color: Colors.black45,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow,
                size: 8,
                color: Colors.white,
              ),
            ),
          ),
      ],
    ),
  );
}

Widget _buildVideoThumbnail(
  BuildContext context,
  Color color,
  AppThemeTokens tokens,
) {
  return Container(
    width: 40,
    height: 52,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(tokens.cardRadius * 0.35),
    ),
    child: Center(
      child: Icon(
        Icons.play_circle_outline_rounded,
        size: 18,
        color: Theme.of(
          context,
        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
      ),
    ),
  );
}

void _handleCallPhone(BuildContext context, String phone) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder:
        (sheetContext) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ListTile(
                  title: Center(
                    child: Text(
                      '呼叫 $phone',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Native.system.makePhoneCall(phone);
                  },
                ),
                const Divider(height: 0.5),
                ListTile(
                  title: const Center(
                    child: Text('复制号码', style: TextStyle(fontSize: 15)),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Clipboard.setData(ClipboardData(text: phone));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('电话号码已复制到剪贴板'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
                const Divider(height: 0.5),
                ListTile(
                  title: const Center(
                    child: Text(
                      '取消',
                      style: TextStyle(fontSize: 15, color: Colors.grey),
                    ),
                  ),
                  onTap: () => Navigator.pop(sheetContext),
                ),
              ],
            ),
          ),
        ),
  );
}

void _handleCallMedia(BuildContext context, String displayName) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder:
        (sheetContext) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ListTile(
                  leading: const Icon(
                    Icons.phone_rounded,
                    color: Color(0xFF07C160),
                  ),
                  title: const Text('语音通话'),
                  subtitle: Text('与 $displayName 进行实时语音沟通'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('语音通话功能接入中')),
                    );
                  },
                ),
                const Divider(height: 0.5),
                ListTile(
                  leading: const Icon(
                    Icons.videocam_rounded,
                    color: Color(0xFF07C160),
                  ),
                  title: const Text('视频通话'),
                  subtitle: Text('与 $displayName 进行面对面高清视频'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('视频通话功能接入中')),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
  );
}

String _titleFor(ProfileKind kind) => switch (kind) {
  ProfileKind.user => '我的资料',
  ProfileKind.friend => '好友资料',
  ProfileKind.group => '群资料',
  ProfileKind.member => '成员资料',
};
