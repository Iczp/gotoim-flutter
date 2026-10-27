import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/session/presentation/chat_object_avatar.dart';
import '../../features/user/data/models/profile_subject.dart';
import '../../features/user/presentation/widgets/profile_action_sheets.dart';
import '../../features/user/presentation/widgets/profile_gender_badge.dart';
import '../../features/social/data/social_repository.dart';
import '../../features/social/presentation/social_page.dart';
import '../platform/desktop_window_adapter.dart';
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
    this.readSocialPreview,
    super.key,
  });

  final ProfileSubject? initialSubject;
  final Future<Map<String, dynamic>> Function(ProfileSubject subject)?
  readSocialPreview;
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
  Future<Map<String, dynamic>>? _recentPosts;
  late final WindowMethodChannel _mainIpcChannel;

  @override
  void initState() {
    super.initState();
    _subject = widget.initialSubject;
    _mainIpcChannel = const WindowMethodChannel(
      'gotoim/ipc_to_main',
      mode: ChannelMode.unidirectional,
    );
    if (_subject != null) _recentPosts = _readRecent(_subject!);

    Future<dynamic> handleMethodCall(MethodCall call) async {
      switch (call.method) {
        case 'social_identity_changed':
          if (mounted && _subject != null) {
            setState(() => _recentPosts = _readRecent(_subject!));
          }
          return true;
        case 'update_profile':
          final args = call.arguments;
          if (args is Map && mounted) {
            setState(() {
              _subject = ProfileSubject.fromMap(
                Map<String, dynamic>.from(args),
              );
              _recentPosts = _readRecent(_subject!);
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
      WindowController.fromCurrentEngine()
          .then((controller) {
            controller.setWindowMethodHandler(handleMethodCall);
          })
          .catchError((_) {});
    }
  }

  Future<void> _handleHide() async {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      await DesktopWindowAdapter.hide();
    }
  }

  Future<Map<String, dynamic>> _readRecent(ProfileSubject subject) async {
    if (subject.kind == ProfileKind.group) return {'hidden': true};
    if (widget.readSocialPreview != null) {
      return widget.readSocialPreview!(subject);
    }
    final result = await _mainIpcChannel.invokeMethod(
      'social_profile_preview',
      subject.toMap(),
    );
    if (result is! Map) throw StateError('动态加载失败');
    return Map<String, dynamic>.from(result);
  }

  Future<void> _openSocialPost(SocialPost post) async {
    dynamic result;
    try {
      result = await _mainIpcChannel.invokeMethod('social_profile_post', {
        'postId': post.id,
      });
    } catch (_) {
      if (mounted) showToast('动态加载失败，请重试');
      return;
    }
    if (!mounted) return;
    if (result is! Map || result['error'] != null) {
      showToast('动态已不可用或无权查看');
      return;
    }
    final current = SocialPost.fromJson(Map<String, dynamic>.from(result));
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder:
          (context) => SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .75,
              child: SingleChildScrollView(
                child: SocialPostCard(post: current),
              ),
            ),
          ),
    );
  }

  Widget _buildRecentPosts(ProfileSubject subject) {
    if (subject.kind == ProfileKind.group) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '动态 · 最近三条',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '刷新动态',
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed:
                      () => setState(() => _recentPosts = _readRecent(subject)),
                ),
              ],
            ),
            FutureBuilder<Map<String, dynamic>>(
              future: _recentPosts,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LinearProgressIndicator();
                }
                if (snapshot.hasError || snapshot.data?['error'] != null) {
                  return const Text('动态加载失败，请刷新重试');
                }
                final data = snapshot.data;
                if (data?['actorLinked'] != true) {
                  return const Text('尚未关联 Social 身份');
                }
                final posts =
                    (data?['posts'] as List? ?? [])
                        .take(3)
                        .map(
                          (item) => SocialPost.fromJson(
                            Map<String, dynamic>.from(item as Map),
                          ),
                        )
                        .toList();
                return Column(
                  children: [
                    Wrap(
                      spacing: 12,
                      children: [
                        Text('关注 ${data?['followingCount'] ?? 0}'),
                        Text('粉丝 ${data?['followersCount'] ?? 0}'),
                        Text(
                          data?['isSelf'] == true
                              ? '当前社区身份'
                              : data?['isFollowing'] == true
                              ? '已关注'
                              : data?['isFollowing'] == false
                              ? '未关注'
                              : '尚未选择社区身份',
                        ),
                      ],
                    ),
                    if (posts.isEmpty) const Text('暂无可见动态'),
                    for (final post in posts)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(
                          post.content.isNotEmpty ? post.content : '动态',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '赞 ${post.likes} · 回复 ${post.replies}${post.publishedAt != null ? ' · ${post.publishedAt!.toLocal().toString().split('.').first}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _openSocialPost(post),
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
                color:
                    isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : colorScheme.outlineVariant.withValues(alpha: 0.45),
                width: 0.8,
              ),
            ),
            child: SingleChildScrollView(
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
                          itemBuilder:
                              (ctx) => [
                                const PopupMenuItem(
                                  value: 'more_action',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.settings_suggest_rounded,
                                        size: 16,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        '资料与权限设置',
                                        style: TextStyle(fontSize: 13),
                                      ),
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
                              imageUrl:
                                  subject.avatarUrl.isEmpty
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
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
                  _buildRecentPosts(subject),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _handleSendMessage,
                            icon: const Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 16,
                            ),
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
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
          ),
        ),
      ],
    );
  }
}
