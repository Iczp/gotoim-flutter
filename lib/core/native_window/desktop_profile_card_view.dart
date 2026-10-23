import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/session/presentation/chat_object_avatar.dart';
import '../../features/user/data/models/profile_subject.dart';
import '../../features/user/presentation/widgets/profile_action_sheets.dart';
import '../../features/user/presentation/widgets/profile_gender_badge.dart';
import '../platform/windows/windows_window_adapter.dart';
import '../widgets/app_toast.dart';

/// 桌面端无边框常驻复用资料卡悬浮窗视图 (DesktopProfileCardView)
///
/// 遵循桌面端无边框独立子窗口规范：
/// 1. 窗口样式为原生无边框、无系统标题栏，启用圆角与原生阴影；
/// 2. 背景透明，卡片居中悬浮；
/// 3. 支持 IPC 动态更新 `update_profile` 数据；
/// 4. 点击「发消息」通过 IPC `open_chat` 通知主窗口激活会话并隐藏本窗口；
/// 5. 原生统一管理跨窗口悬停；点击后保持交互，支持 ESC 关闭。
class DesktopProfileCardView extends ConsumerStatefulWidget {
  const DesktopProfileCardView({
    this.initialSubject,
    this.onClose,
    this.onRegisterMethodHandler,
    super.key,
  });

  final ProfileSubject? initialSubject;
  final VoidCallback? onClose;
  final void Function(Future<dynamic> Function(MethodCall call) handler)?
      onRegisterMethodHandler;

  @override
  ConsumerState<DesktopProfileCardView> createState() =>
      _DesktopProfileCardViewState();
}

class _DesktopProfileCardViewState
    extends ConsumerState<DesktopProfileCardView> {
  ProfileSubject? _subject;
  late final WindowMethodChannel _mainIpcChannel;

  @override
  void initState() {
    super.initState();
    _subject = widget.initialSubject;
    _mainIpcChannel = const WindowMethodChannel(
      'gotoim/ipc_to_main',
      mode: ChannelMode.unidirectional,
    );

    Future<dynamic> handleMethodCall(MethodCall call) async {
      switch (call.method) {
        case 'update_profile':
          final args = call.arguments;
          if (args is Map && mounted) {
            setState(() {
              _subject = ProfileSubject.fromMap(
                Map<String, dynamic>.from(args),
              );
            });
          }
          return true;
        case 'hide_profile':
          await _handleHide();
          return true;
        default:
          return null;
      }
    }

    if (widget.onRegisterMethodHandler != null) {
      widget.onRegisterMethodHandler!(handleMethodCall);
    } else {
      WindowController.fromCurrentEngine().then((controller) {
        controller.setWindowMethodHandler(handleMethodCall);
      }).catchError((_) {});
    }
  }

  Future<void> _handleHide() async {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      await WindowsWindowAdapter.hide();
    }
  }

  void _handleSendMessage() {
    final targetId = _subject?.id;
    if (targetId != null && targetId.isNotEmpty) {
      _mainIpcChannel.invokeMethod('open_chat', {'sessionUnitId': targetId});
    }
    _handleHide();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final subject = _subject;
    if (subject == null) {
      return const SizedBox.shrink();
    }

    final data = ProfileData(subject);

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _handleHide();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        // Native tracking covers the avatar, the gap, this window and its
        // active popups. A Dart leave timer could close an already entered card.
        child: Material(
          color: colorScheme.surface,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : colorScheme.outlineVariant.withValues(alpha: 0.45),
                width: 0.8,
              ),
            ),
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
                          onPressed: _handleHide,
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

                  Divider(
                    height: 1,
                    thickness: 0.5,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                  ),

                  // ── 附加详细信息（地区、个性签名、身份来源等） ──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (data.region.isNotEmpty)
                          _buildDetailRow(
                            context,
                            label: '地区',
                            value: data.region,
                            colorScheme: colorScheme,
                          ),
                        if (data.description.isNotEmpty) ...[
                          if (data.region.isNotEmpty) const SizedBox(height: 8),
                          _buildDetailRow(
                            context,
                            label: '签名',
                            value: data.description,
                            colorScheme: colorScheme,
                          ),
                        ],
                        if (subject.subtitle.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _buildDetailRow(
                            context,
                            label: '身份',
                            value: subject.subtitle,
                            colorScheme: colorScheme,
                          ),
                        ],
                      ],
                    ),
                  ),

                  Divider(
                    height: 1,
                    thickness: 0.5,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                  ),

                  // ── 底部快捷操作区（发消息 / 语音视频） ──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _handleSendMessage,
                            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                            label: const Text('发消息'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF07C160),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton.filledTonal(
                          tooltip: '音视频通话',
                          onPressed: () {
                            showToast('音视频通话已发起', type: ToastType.info);
                            _handleHide();
                          },
                          icon: const Icon(Icons.videocam_outlined, size: 20),
                          style: IconButton.styleFrom(
                            padding: const EdgeInsets.all(12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
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

  Widget _buildDetailRow(
    BuildContext context, {
    required String label,
    required String value,
    required ColorScheme colorScheme,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}
