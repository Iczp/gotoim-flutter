import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/native/native.dart';
import '../../../core/theme/app_theme_tokens.dart';
import '../../../core/ui/adaptive_page/adaptive_page.dart';
import '../../../core/ui/adaptive_page/adaptive_page_config.dart';
import '../../../core/ui/adaptive_page/adaptive_page_controller.dart';
import '../../../core/ui/adaptive_page/adaptive_page_presentation.dart';
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

Future<void> openProfilePage(
  BuildContext context, {
  required ProfileSubject subject,
  VoidCallback? onSendMessage,
}) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  await AdaptivePage.open<void>(
    context,
    config: AdaptivePageConfig(
      title: '',
      sheetSizingMode: AdaptiveSheetSizingMode.draggable,
      initialChildSize: .76,
      minChildSize: .45,
      maxChildSize: .96,
      sheetBorderRadius: 16,
      backgroundColor:
          isDark ? const Color(0xFF141414) : const Color(0xFFEDEDED),
      showDragHandle: true,
      showCloseButton: true,
      fullPageMinWidth: 720,
    ),
    builder:
        (context, controller) => ProfilePage(
          subject: subject,
          adaptiveController: controller,
          onSendMessage: onSendMessage,
        ),
  );
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({
    required this.subject,
    required this.adaptiveController,
    this.onSendMessage,
    super.key,
  });

  final ProfileSubject subject;
  final AdaptivePageController adaptiveController;
  final VoidCallback? onSendMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tokens = context.appTokens;

    // 微信主题配色
    final cardColor = isDark ? const Color(0xFF1F1F1F) : Colors.white;
    final dividerColor =
        isDark ? const Color(0x1FFFFFFF) : const Color(0x12000000);
    final linkColor = const Color(0xFF576B95);
    final subtextColor =
        isDark ? const Color(0x99FFFFFF) : const Color(0x88000000);

    final owner = asMap(subject.raw['owner']);
    final destination = asMap(subject.raw['destination']);
    final setting = asMap(subject.raw['setting']);

    // 昵称与展示名
    final displayName = subject.name;
    final originalNickname = firstNonEmpty(<Object?>[
      owner['displayName'],
      owner['name'],
      subject.raw['nickname'],
      destination['memberName'],
      setting['memberName'],
    ]);
    final showNickname =
        originalNickname.isNotEmpty && originalNickname != displayName;

    // 账号/微信号
    final accountCode = firstNonEmpty(<Object?>[
      owner['code'],
      subject.raw['code'],
      subject.id,
    ]);

    // 地区
    final region = firstNonEmpty(<Object?>[
      owner['area'],
      owner['region'],
      subject.raw['area'],
      subject.raw['region'],
    ]);

    // 电话
    final phone = firstNonEmpty(<Object?>[
      owner['phone'],
      owner['phoneNumber'],
      subject.raw['phone'],
      subject.raw['phoneNumber'],
    ]);

    // 性别 (1: 男, 2: 女, 0: 未知)
    final gender = asInt(owner['gender']) ?? asInt(subject.raw['gender']) ?? 0;

    // 简介/描述
    final description = firstNonEmpty(<Object?>[
      owner['description'],
      subject.raw['description'],
    ]);

    final chatObjectId =
        asInt(destination['id']) ??
        asInt(subject.raw['destinationId']) ??
        asInt(subject.raw['id']);

    return ListView(
      controller: adaptiveController.scrollController,
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        0,
        0,
        0,
        MediaQuery.paddingOf(context).bottom + 20,
      ),
      children: <Widget>[
        // ── 1. 头部卡片（头像、名字、性别、昵称、微信号、地区） ──
        Container(
          color: cardColor,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 大方形圆角头像
              Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 60,
                      height: 60,
                      child: ChatObjectAvatar(
                        name: displayName,
                        imageUrl:
                            subject.avatarUrl.isEmpty ? null : subject.avatarUrl,
                        radius: 30,
                        chatObjectId: chatObjectId,
                      ),
                    ),
                  ),
                  if (subject.editableAvatar)
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: GestureDetector(
                        onTap: () {
                          adaptiveController.close();
                          context.push('/settings/avatar');
                        },
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.edit,
                            size: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              // 右侧信息流
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // 第一行：主名称 + 性别图标
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            displayName,
                            style: const TextStyle(
                              fontSize: 18.5,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (gender != 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 2.5,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  gender == 2
                                      ? const Color(0xFFF99788)
                                      : const Color(0xFF32BBFB),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Icon(
                              gender == 2 ? Icons.female : Icons.male,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    // 第二行：原始昵称（如果与显示名不同）
                    if (showNickname) ...[
                      Text(
                        '昵称: $originalNickname',
                        style: TextStyle(
                          fontSize: 13.0,
                          color: subtextColor,
                          height: 1.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                    ],
                    // 第三行：微信号/账号
                    Text(
                      '微信号: ${accountCode.isEmpty ? '-' : accountCode}',
                      style: TextStyle(
                        fontSize: 13.0,
                        color: subtextColor,
                        height: 1.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    // 第四行：地区
                    Text(
                      '地区: ${region.isEmpty ? '中国' : region}',
                      style: TextStyle(
                        fontSize: 13.0,
                        color: subtextColor,
                        height: 1.3,
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
        const SizedBox(height: 8),

        // ── 2. 功能分组（朋友资料 / 电话） ──
        Container(
          color: cardColor,
          child: Column(
            children: <Widget>[
              _buildCellRow(
                context,
                title: '朋友资料',
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFFB2B2B2),
                  size: 20,
                ),
                onTap: () {
                  // 点击查看或编辑标签/备注
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('朋友资料与标签设置'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
              Divider(
                height: tokens.dividerThickness,
                thickness: tokens.dividerThickness,
                indent: 16,
                color: dividerColor,
              ),
              _buildCellRow(
                context,
                title: '电话',
                content:
                    phone.isNotEmpty
                        ? InkWell(
                          onTap: () => _handleCallPhone(context, phone),
                          child: Text(
                            phone,
                            style: TextStyle(
                              fontSize: 14.5,
                              color: linkColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        )
                        : Text(
                          '未填写',
                          style: TextStyle(fontSize: 14.0, color: subtextColor),
                        ),
                trailing:
                    phone.isNotEmpty
                        ? IconButton(
                          icon: Icon(
                            Icons.phone_outlined,
                            size: 18,
                            color: linkColor,
                          ),
                          onPressed: () => _handleCallPhone(context, phone),
                          tooltip: '拨打电话',
                        )
                        : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ── 3. 朋友圈分组（微信朋友圈动态展示） ──
        Container(
          color: cardColor,
          child: _buildCellRow(
            context,
            title: '朋友圈',
            content: SizedBox(
              height: 44,
              child: Row(
                children: <Widget>[
                  // 缩略图阵列（模拟微信朋友圈最新发表图格）
                  _buildMomentsThumbnail(
                    color: const Color(0xFFE57373),
                    isText: true,
                    label: '动态',
                  ),
                  const SizedBox(width: 6),
                  _buildMomentsThumbnail(
                    color: const Color(0xFF81C784),
                    icon: Icons.image_outlined,
                  ),
                  const SizedBox(width: 6),
                  _buildMomentsThumbnail(
                    color: const Color(0xFF64B5F6),
                    icon: Icons.play_arrow_rounded,
                    isVideo: true,
                  ),
                  const SizedBox(width: 6),
                  _buildMomentsThumbnail(
                    color: const Color(0xFFFFB74D),
                    icon: Icons.celebration_rounded,
                  ),
                ],
              ),
            ),
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFFB2B2B2),
              size: 20,
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
        ),
        const SizedBox(height: 8),

        // ── 4. 视频号 / 扩展资料分组 ──
        Container(
          color: cardColor,
          child: _buildCellRow(
            context,
            title: '视频号',
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  displayName,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: theme.textTheme.bodyMedium?.color,
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 48,
                  child: Row(
                    children: <Widget>[
                      _buildVideoFeedThumbnail(const Color(0xFF4DB6AC)),
                      const SizedBox(width: 6),
                      _buildVideoFeedThumbnail(const Color(0xFF7986CB)),
                      const SizedBox(width: 6),
                      _buildVideoFeedThumbnail(const Color(0xFFA1887F)),
                      const SizedBox(width: 6),
                      _buildVideoFeedThumbnail(const Color(0xFF90A4AE)),
                    ],
                  ),
                ),
              ],
            ),
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFFB2B2B2),
              size: 20,
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
        ),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            color: cardColor,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 72,
                  child: Text(
                    '个性签名',
                    style: TextStyle(
                      fontSize: 14.5,
                      color: theme.textTheme.bodyMedium?.color,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    description,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: subtextColor,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),

        // ── 5. 底部双操作按钮栏（居中、清爽发消息与音视频通话） ──
        Container(
          color: cardColor,
          child: Column(
            children: <Widget>[
              // 发消息
              InkWell(
                onTap: () {
                  adaptiveController.close();
                  onSendMessage?.call();
                },
                child: SizedBox(
                  height: 50,
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 19,
                          color: linkColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '发消息',
                          style: TextStyle(
                            fontSize: 16.0,
                            fontWeight: FontWeight.w600,
                            color: linkColor,
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
                indent: 32,
                endIndent: 32,
                color: dividerColor,
              ),
              // 音视频通话
              InkWell(
                onTap: () => _handleCallMedia(context, displayName),
                child: SizedBox(
                  height: 50,
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.videocam_outlined,
                          size: 22,
                          color: linkColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '音视频通话',
                          style: TextStyle(
                            fontSize: 16.0,
                            fontWeight: FontWeight.w600,
                            color: linkColor,
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
    );
  }

  // 微信经典单元行
  Widget _buildCellRow(
    BuildContext context, {
    required String title,
    Widget? content,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final rowContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        crossAxisAlignment:
            content != null && content is Column
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 72,
            child: Text(
              title,
              style: TextStyle(
                fontSize: 14.5,
                color: theme.textTheme.bodyMedium?.color,
              ),
            ),
          ),
          if (content != null) Expanded(child: content),
          if (trailing != null) trailing,
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(onTap: onTap, child: rowContent);
    }
    return rowContent;
  }

  // 朋友圈缩略图
  Widget _buildMomentsThumbnail({
    required Color color,
    IconData? icon,
    bool isText = false,
    bool isVideo = false,
    String? label,
  }) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          if (isText && label != null)
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            )
          else if (icon != null)
            Icon(icon, size: 20, color: color),
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
                  size: 9,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // 视频号缩略图
  Widget _buildVideoFeedThumbnail(Color color) {
    return Container(
      width: 36,
      height: 48,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(3),
      ),
      child: const Center(
        child: Icon(Icons.play_arrow_rounded, size: 16, color: Colors.white),
      ),
    );
  }

  // 拨打电话处理
  void _handleCallPhone(BuildContext context, String phone) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (sheetContext) => Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
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

  // 音视频通话处理
  void _handleCallMedia(BuildContext context, String displayName) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (sheetContext) => Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
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
}
