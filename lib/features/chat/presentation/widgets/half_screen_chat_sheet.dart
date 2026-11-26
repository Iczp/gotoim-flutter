import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/app_navigation.dart';
import '../../../../app/application_providers.dart';
import '../../../../core/config/app_environment.dart';
import '../../../../core/services/file/attachment_transfer_service.dart';
import '../../../session/presentation/chat_object_avatar.dart';
import '../../application/chat_controller.dart';
import '../../data/models/chat_message.dart';
import '../message_content/chat_message_content_renderer.dart';

/// 半屏聊天/聊天记录展示组件 (HalfScreenChatSheet)
///
/// 核心特性：
/// 1. 不关闭当前窗口/页面，直接作为半屏页浮层滑出（桌面端/宽屏为右侧半屏 Side Sheet，移动端为底部半屏 Bottom Sheet）；
/// 2. 支持传入 [targetServerMessageId] 以指定消息为中心加载前后切片，并自动居中高亮脉冲；
/// 3. 支持双向翻页：向上翻页加载更早历史（Older），向下翻页加载更新历史（Newer）；
/// 4. 处于历史视口时提供“回到最新”悬浮按钮；
/// 5. 内置消息输入栏（Composer），允许用户在查阅历史的同时直接聊天交互；
/// 6. 提供一键最大化/弹出为完整页面或独立窗口功能。
class HalfScreenChatSheet extends ConsumerStatefulWidget {
  const HalfScreenChatSheet({
    required this.sessionUnitId,
    this.ownerId,
    this.targetServerMessageId,
    this.title,
    this.isHistoryMode = false,
    super.key,
  });

  final String sessionUnitId;
  final int? ownerId;
  final int? targetServerMessageId;
  final String? title;
  final bool isHistoryMode;

  /// 静态调起半屏页入口方法
  static Future<T?> show<T>({
    required BuildContext context,
    required String sessionUnitId,
    int? ownerId,
    int? targetServerMessageId,
    String? title,
    bool isHistoryMode = false,
  }) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 720;

    if (isDesktop) {
      // 桌面端/宽屏：右侧滑出半屏 Side Sheet
      final sheetWidth = math.min(
        580.0,
        MediaQuery.sizeOf(context).width * 0.52,
      );
      return showGeneralDialog<T>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'HalfScreenChatSheet',
        barrierColor: Colors.black38,
        transitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (dialogContext, animation, secondaryAnimation) {
          return Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: sheetWidth,
              height: double.infinity,
              child: Material(
                elevation: 16,
                color: Theme.of(context).colorScheme.surface,
                child: HalfScreenChatSheet(
                  sessionUnitId: sessionUnitId,
                  ownerId: ownerId,
                  targetServerMessageId: targetServerMessageId,
                  title: title,
                  isHistoryMode: isHistoryMode,
                ),
              ),
            ),
          );
        },
        transitionBuilder: (context, anim1, anim2, child) {
          final curved = CurvedAnimation(
            parent: anim1,
            curve: Curves.easeOutCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        },
      );
    } else {
      // 移动端：底部半屏弹窗 (Modal Bottom Sheet)
      return showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (bottomSheetContext) {
          final sheetHeight = MediaQuery.sizeOf(context).height * 0.85;
          return Container(
            height: sheetHeight,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: HalfScreenChatSheet(
              sessionUnitId: sessionUnitId,
              ownerId: ownerId,
              targetServerMessageId: targetServerMessageId,
              title: title,
              isHistoryMode: isHistoryMode,
            ),
          );
        },
      );
    }
  }

  @override
  ConsumerState<HalfScreenChatSheet> createState() =>
      _HalfScreenChatSheetState();
}

class _HalfScreenChatSheetState extends ConsumerState<HalfScreenChatSheet> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  List<ChatMessage> _messages = [];
  bool _isLoading = true;
  bool _isLoadingOlder = false;
  bool _isLoadingNewer = false;
  bool _hasMoreOlder = false;
  bool _hasMoreNewer = false;
  bool _isAnchoredMode = false;
  int? _highlightedServerId;
  Timer? _highlightTimer;

  int get _effectiveOwnerId {
    if (widget.ownerId != null) return widget.ownerId!;
    final user = ref.read(currentUserProvider);
    return int.tryParse(user?.id ?? '') ?? 0;
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _initLoad();
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _scrollController.dispose();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;

    // 向上滑动接近顶部（加载更早历史，Older）
    if (pos.pixels <= pos.minScrollExtent + 40 &&
        _hasMoreOlder &&
        !_isLoadingOlder) {
      _loadMoreOlder();
    }

    // 向下滑动接近底部（在切片模式下加载更新历史，Newer）
    if (pos.pixels >= pos.maxScrollExtent - 40 &&
        _hasMoreNewer &&
        !_isLoadingNewer) {
      _loadMoreNewer();
    }
  }

  Future<void> _initLoad() async {
    setState(() => _isLoading = true);
    final repo = ref.read(messageRepositoryProvider);

    try {
      if (widget.targetServerMessageId != null) {
        // 目标切片模式
        final slice = await repo.getAroundAnchorSlice(
          ownerId: _effectiveOwnerId,
          sessionUnitId: widget.sessionUnitId,
          targetServerId: widget.targetServerMessageId!,
          beforeCount: 20,
          afterCount: 20,
        );

        if (!mounted) return;
        setState(() {
          _messages = List.of(slice.items);
          _hasMoreOlder = slice.hasMoreOlder;
          _hasMoreNewer = slice.hasMoreNewer;
          _isAnchoredMode = true;
          _isLoading = false;
        });

        if (slice.targetIndex >= 0) {
          _highlightTarget(widget.targetServerMessageId!);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToIndex(slice.targetIndex);
          });
        }
      } else {
        // 普通最新模式
        final page = await repo.loadHistory(
          ownerId: _effectiveOwnerId,
          sessionUnitId: widget.sessionUnitId,
          limit: 30,
        );

        if (!mounted) return;
        setState(() {
          // loadMessages 返回的是倒序或正序，转为正序列表展示
          final sorted = List.of(page.items)
            ..sort((a, b) => a.score.compareTo(b.score));
          _messages = sorted;
          _hasMoreOlder = page.hasMore;
          _hasMoreNewer = false;
          _isAnchoredMode = false;
          _isLoading = false;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      debugPrint('[HalfScreenChatSheet] init error: $e');
    }
  }

  void _highlightTarget(int serverId) {
    _highlightTimer?.cancel();
    setState(() => _highlightedServerId = serverId);
    _highlightTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _highlightedServerId = null);
    });
  }

  void _scrollToIndex(int index) {
    if (!_scrollController.hasClients || _messages.isEmpty) return;
    // 粗略估算每个气泡 80px，将目标消息居中在视口中央
    final targetOffset = index * 80.0;
    final viewportHeight = _scrollController.position.viewportDimension;
    final centeredOffset = (targetOffset - viewportHeight / 2).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      centeredOffset,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _loadMoreOlder() async {
    if (_isLoadingOlder || !_hasMoreOlder || _messages.isEmpty) return;
    setState(() => _isLoadingOlder = true);

    try {
      final repo = ref.read(messageRepositoryProvider);
      final oldestScore = _messages.first.score;
      final prevScrollHeight = _scrollController.position.maxScrollExtent;
      final prevOffset = _scrollController.offset;

      final page = await repo.loadHistory(
        ownerId: _effectiveOwnerId,
        sessionUnitId: widget.sessionUnitId,
        beforeScore: oldestScore,
        limit: 20,
      );

      if (!mounted) return;
      if (page.items.isNotEmpty) {
        final sortedOlder = List.of(page.items)
          ..sort((a, b) => a.score.compareTo(b.score));
        final existingIds = _messages.map((m) => m.localId).toSet();
        final dedupedOlder = sortedOlder.where((m) => !existingIds.contains(m.localId)).toList();

        setState(() {
          _messages = [...dedupedOlder, ..._messages];
          _hasMoreOlder = page.hasMore;
          _isLoadingOlder = false;
        });

        // 保持视口锚点相对位置稳定
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            final newScrollHeight = _scrollController.position.maxScrollExtent;
            final delta = newScrollHeight - prevScrollHeight;
            if (delta > 0) {
              _scrollController.jumpTo(prevOffset + delta);
            }
          }
        });
      } else {
        setState(() {
          _hasMoreOlder = page.hasMore;
          _isLoadingOlder = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingOlder = false);
    }
  }

  Future<void> _loadMoreNewer() async {
    if (_isLoadingNewer || !_hasMoreNewer || _messages.isEmpty) return;
    setState(() => _isLoadingNewer = true);

    try {
      final repo = ref.read(messageRepositoryProvider);
      final newest = _messages.last;

      final page = await repo.loadNewerMessages(
        ownerId: _effectiveOwnerId,
        sessionUnitId: widget.sessionUnitId,
        afterScore: newest.score,
        afterServerId: newest.serverId ?? 0,
        limit: 20,
      );

      if (!mounted) return;
      if (page.items.isNotEmpty) {
        final sortedNewer = List.of(page.items)
          ..sort((a, b) => a.score.compareTo(b.score));
        final existingIds = _messages.map((m) => m.localId).toSet();
        final dedupedNewer = sortedNewer.where((m) => !existingIds.contains(m.localId)).toList();

        setState(() {
          _messages = [..._messages, ...dedupedNewer];
          _hasMoreNewer = page.hasMore;
          _isLoadingNewer = false;
        });
      } else {
        setState(() {
          _hasMoreNewer = page.hasMore;
          _isLoadingNewer = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingNewer = false);
    }
  }

  Future<void> _resetToLatest() async {
    setState(() => _isLoading = true);
    final repo = ref.read(messageRepositoryProvider);
    try {
      final page = await repo.loadHistory(
        ownerId: _effectiveOwnerId,
        sessionUnitId: widget.sessionUnitId,
        limit: 30,
      );
      if (!mounted) return;
      final sorted = List.of(page.items)
        ..sort((a, b) => a.score.compareTo(b.score));
      setState(() {
        _messages = sorted;
        _hasMoreOlder = page.hasMore;
        _hasMoreNewer = false;
        _isAnchoredMode = false;
        _highlightedServerId = null;
        _isLoading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        }
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();

    try {
      final repo = ref.read(messageRepositoryProvider);
      final clientMsgId = 'half_${DateTime.now().millisecondsSinceEpoch}';
      await repo.api.sendText(
        sessionUnitId: widget.sessionUnitId,
        clientMessageId: clientMsgId,
        text: text,
      );

      // 若处于历史切片模式，发送后重置并滚动到底部最新
      if (_isAnchoredMode && _hasMoreNewer) {
        await _resetToLatest();
      } else {
        // 增量刷新最新消息
        final latest = await repo.loadHistory(
          ownerId: _effectiveOwnerId,
          sessionUnitId: widget.sessionUnitId,
          limit: 10,
        );
        if (mounted && latest.items.isNotEmpty) {
          final sorted = List.of(latest.items)
            ..sort((a, b) => a.score.compareTo(b.score));
          final existing = _messages.map((m) => m.localId).toSet();
          final newItems = sorted.where((m) => !existing.contains(m.localId)).toList();
          if (newItems.isNotEmpty) {
            setState(() {
              _messages = [..._messages, ...newItems];
            });
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
              );
            }
          });
        }
      }
    } catch (e) {
      debugPrint('[HalfScreenChatSheet] send text error: $e');
    }
  }

  void _popOutToFullChat() {
    Navigator.of(context).pop();
    SafeChatNavigator.pushChat(
      context,
      '/chat/${Uri.encodeComponent(widget.sessionUnitId)}'
      '?ownerId=$_effectiveOwnerId'
      '&title=${Uri.encodeQueryComponent(widget.title ?? '')}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        // 1. 顶部 Header 栏
        _buildHeader(theme, colorScheme, isDark),
        const Divider(height: 1),

        // 2. 消息内容区域
        Expanded(
          child: Stack(
            children: [
              _buildMessageBody(theme, colorScheme, isDark),
              if (_isAnchoredMode && _hasMoreNewer)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton.extended(
                    heroTag: 'half_screen_back_to_latest',
                    icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                    label: const Text('回到最新', style: TextStyle(fontSize: 12)),
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    elevation: 3,
                    onPressed: _resetToLatest,
                  ),
                ),
            ],
          ),
        ),

        const Divider(height: 1),

        // 3. 底部快捷输入栏（支持在半屏页中直接聊天互动）
        _buildComposerBar(theme, colorScheme, isDark),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme, ColorScheme colorScheme, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          ChatObjectAvatar(
            imageUrl: null,
            name: widget.title ?? '会话',
            size: 36,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.title ?? '会话详情',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: widget.isHistoryMode
                            ? Colors.amber.withValues(alpha: 0.2)
                            : colorScheme.primaryContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: widget.isHistoryMode
                              ? Colors.amber.shade700
                              : colorScheme.primary,
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        widget.isHistoryMode ? '聊天记录' : '半屏会话',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: widget.isHistoryMode
                              ? Colors.amber.shade800
                              : colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  widget.sessionUnitId,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '全屏/独立打开',
            icon: const Icon(Icons.open_in_new_rounded, size: 20),
            onPressed: _popOutToFullChat,
          ),
          IconButton(
            tooltip: '关闭',
            icon: const Icon(Icons.close_rounded, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBody(
    ThemeData theme,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    if (_isLoading) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }

    if (_messages.isEmpty) {
      return Center(
        child: Text(
          '暂无聊天记录',
          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      itemCount: _messages.length + 2, // 包含顶部与底部指示器
      itemBuilder: (context, index) {
        if (index == 0) {
          // 顶部 Older 状态
          if (_isLoadingOlder) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          if (_hasMoreOlder) {
            return Center(
              child: TextButton(
                onPressed: _loadMoreOlder,
                child: const Text('向上加载更早记录', style: TextStyle(fontSize: 11)),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Center(
              child: Text(
                '已达最早历史记录',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
            ),
          );
        }

        if (index == _messages.length + 1) {
          // 底部 Newer 状态
          if (_isLoadingNewer) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          if (_hasMoreNewer) {
            return Center(
              child: TextButton(
                onPressed: _loadMoreNewer,
                child: const Text('向下加载更新记录', style: TextStyle(fontSize: 11)),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Center(
              child: Text(
                '已加载至最新消息',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
            ),
          );
        }

        final msg = _messages[index - 1];
        final isHighlighted =
            _highlightedServerId != null && msg.serverId == _highlightedServerId;

        return _buildMessageItem(msg, isHighlighted, theme, colorScheme, isDark);
      },
    );
  }

  Widget _buildMessageItem(
    ChatMessage message,
    bool isHighlighted,
    ThemeData theme,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    final isMe = message.isMine;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isHighlighted
            ? Colors.amber.withValues(alpha: 0.35)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            ChatObjectAvatar(
              imageUrl: null,
              name: message.senderName,
              size: 32,
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe && message.senderName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2, left: 2),
                    child: Text(
                      message.senderName,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isMe
                        ? colorScheme.primary
                        : (isDark ? Colors.white12 : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ChatMessageContentRenderer(
                    message: message,
                    attachmentState: const AttachmentTransferState(),
                    onVoiceOpened: () async {},
                    onAttachmentDownload: () async {},
                    onAttachmentCancel: () async {},
                    onAttachmentOpen: () async {},
                    onAttachmentSaveAs: () async {},
                    imageBytes: null,
                    uploadProgress: null,
                    apiBaseUrl: ref.read(appEnvironmentProvider).apiBaseUrl,
                    mediaItems: const [],
                    mediaInitialIndex: 0,
                    maxWidth: 360,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 2, right: 2),
                  child: Text(
                    _formatTime(message.createdAt),
                    style: TextStyle(
                      fontSize: 10,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 8),
            const ChatObjectAvatar(
              imageUrl: null,
              name: '我',
              size: 32,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildComposerBar(
    ThemeData theme,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: '发送消息直接聊天...',
                    hintStyle: TextStyle(fontSize: 13),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                  onSubmitted: (_) => _handleSendMessage(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              icon: const Icon(Icons.send_rounded, size: 18),
              onPressed: _handleSendMessage,
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    String pad(int n) => n.toString().padLeft(2, '0');

    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${pad(dt.hour)}:${pad(dt.minute)}';
    }
    return '${pad(dt.month)}-${pad(dt.day)} ${pad(dt.hour)}:${pad(dt.minute)}';
  }
}
