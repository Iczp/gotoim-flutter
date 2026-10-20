import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell/application_shell.dart';
import '../../../core/widgets/app_toast.dart';
import '../../home/presentation/home_sections.dart';
import '../../session/presentation/chat_object_avatar.dart';
import '../../session/presentation/desktop_session_split_view.dart';
import '../data/models/profile_subject.dart';
import 'widgets/profile_action_sheets.dart';
import 'widgets/profile_gender_badge.dart';

/// 桌面端微信 4.0 规范个人资料卡弹窗 (DesktopProfileCardDialog)
///
/// 遵循桌面端 IM 规范：
/// - 尺寸 380dp，圆角 12dp，极细边框，原生阴影与毛玻璃层次；
/// - 包含大头像、昵称、性别角标、GotoIM号、地区、签名；
/// - 底部提供主次清晰的操作按钮：「发消息」、「音视频通话」、「更多选项」；
/// - 点击「发消息」直接在桌面端三栏右侧激活聊天，绝不全屏重载或破坏当前分栏布局；
/// - 支持按 ESC 键或点击外部遮罩极速关闭。
class DesktopProfileCardDialog extends ConsumerWidget {
  const DesktopProfileCardDialog({
    required this.subject,
    this.onSendMessage,
    super.key,
  });

  final ProfileSubject subject;
  final VoidCallback? onSendMessage;

  static Future<void> show(
    BuildContext context, {
    required ProfileSubject subject,
    VoidCallback? onSendMessage,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => DesktopProfileCardDialog(
        subject: subject,
        onSendMessage: onSendMessage,
      ),
    );
  }

  void _handleSendMessage(BuildContext context, WidgetRef ref, ProfileData data) {
    Navigator.of(context).pop();

    if (onSendMessage != null) {
      onSendMessage!();
      return;
    }

    // 默认桌面端联动：切换至消息 Tab，并根据目标 ID 激活会话
    ref.read(currentHomeSectionProvider.notifier).setSection(HomeSection.messages);
    if (subject.id.isNotEmpty) {
      ref.read(selectedDesktopSessionUnitIdProvider.notifier).select(subject.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final data = ProfileData(subject);

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).maybePop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 380,
            constraints: const BoxConstraints(maxWidth: 380),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.10)
                    : colorScheme.outlineVariant.withValues(alpha: 0.45),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.16),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── 顶部操作栏（右侧更多操作与关闭按钮） ──
                Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      PopupMenuButton<String>(
                        tooltip: '更多选项',
                        icon: Icon(
                          Icons.more_horiz_rounded,
                          size: 20,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        offset: const Offset(0, 32),
                        onSelected: (val) {
                          if (val == 'more_action') {
                            showMoreProfileActionSheet(
                              context,
                              userId: subject.id,
                              userName: subject.name,
                            );
                          }
                        },
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(
                            value: 'more_action',
                            child: Row(
                              children: [
                                Icon(Icons.settings_suggest_rounded, size: 16),
                                SizedBox(width: 8),
                                Text('资料与权限设置', style: TextStyle(fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: '关闭 (Esc)',
                        icon: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),

                // ── 个人基本信息区（头像 + 昵称 + 账号） ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 头像
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 64,
                          height: 64,
                          child: ChatObjectAvatar(
                            name: data.displayName,
                            imageUrl: subject.avatarUrl.isEmpty
                                ? null
                                : subject.avatarUrl,
                            radius: 32,
                            chatObjectId: data.chatObjectId,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // 昵称与账号
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    data.displayName,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      height: 1.25,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (data.gender > 0) ...[
                                  const SizedBox(width: 6),
                                  ProfileGenderBadge(gender: data.gender),
                                ],
                              ],
                            ),
                            if (data.showNickname) ...[
                              const SizedBox(height: 3),
                              Text(
                                '昵称: ${data.originalNickname}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 4),
                            InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: () {
                                Clipboard.setData(
                                  ClipboardData(text: data.accountCode),
                                );
                                showToast('账号已复制到剪贴板');
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Goto号: ${data.accountCode}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.copy_rounded,
                                    size: 13,
                                    color: colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.7),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1, thickness: 0.5, indent: 24, endIndent: 24),

                // ── 详细信息区（地区、电话、签名） ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  child: Column(
                    children: [
                      if (subject.subtitle.isNotEmpty)
                        _buildInfoRow(
                          context,
                          label: '身份',
                          value: subject.subtitle,
                        ),
                      if (data.region.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _buildInfoRow(
                          context,
                          label: '地区',
                          value: data.region,
                        ),
                      ],
                      if (data.description.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _buildInfoRow(
                          context,
                          label: '个性签名',
                          value: data.description,
                        ),
                      ],
                    ],
                  ),
                ),

                const Divider(height: 1, thickness: 0.5),

                // ── 底部快捷操作栏（发消息与音视频通话） ──
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: isDark
                        ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.25)
                        : colorScheme.surfaceContainerLowest,
                  ),
                  child: Row(
                    children: [
                      // 发消息按钮（主要操作）
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _handleSendMessage(context, ref, data),
                          icon: const Icon(Icons.chat_bubble_outline_rounded, size: 17),
                          label: const Text('发消息', style: TextStyle(fontWeight: FontWeight.w600)),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 音视频通话按钮
                      OutlinedButton(
                        onPressed: () => showMediaCallActionSheet(
                          context,
                          data.displayName,
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          side: BorderSide(
                            color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                          ),
                        ),
                        child: const Icon(Icons.videocam_outlined, size: 19),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurface,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
