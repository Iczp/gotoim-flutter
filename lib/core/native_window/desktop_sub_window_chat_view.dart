import 'dart:math' as math;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/widgets/app_toast.dart';
import 'native_window_payload.dart';

/// 桌面端微信风格独立聊天子窗口视图
class DesktopSubWindowChatView extends StatefulWidget {
  const DesktopSubWindowChatView({
    required this.payload,
    required this.controller,
    this.onClose,
    super.key,
  });

  final NativeWindowPayload payload;
  final WindowController controller;
  final VoidCallback? onClose;

  @override
  State<DesktopSubWindowChatView> createState() =>
      _DesktopSubWindowChatViewState();
}

class _DesktopSubWindowChatViewState extends State<DesktopSubWindowChatView> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final List<_ChatMessage> _messages = [];

  bool _isLoading = true;
  bool _isPinned = false;
  bool _isMaximized = false;

  late final WindowMethodChannel _mainIpcChannel;

  @override
  void initState() {
    super.initState();
    _mainIpcChannel = const WindowMethodChannel(
      'gotoim/ipc_to_main',
      mode: ChannelMode.bidirectional,
    );
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final dynamic raw = await _mainIpcChannel.invokeMethod('chat_load_history', {
        'sessionUnitId': widget.payload.sessionUnitId,
        'ownerId': widget.payload.ownerId,
      });

      if (raw is List && mounted) {
        final list = <_ChatMessage>[];
        for (final item in raw) {
          if (item is Map) {
            final t = item['time'];
            final time = t is num
                ? DateTime.fromMillisecondsSinceEpoch(t.toInt())
                : DateTime.now();
            list.add(_ChatMessage(
              id: item['id']?.toString(),
              serverId: (item['serverId'] as num?)?.toInt(),
              clientMessageId: item['clientMessageId']?.toString(),
              text: item['text']?.toString() ?? '',
              isMe: item['isMe'] == true,
              time: time,
              state: item['state']?.toString() ?? 'sent',
            ));
          }
        }
        setState(() {
          _messages.clear();
          _messages.add(
            _ChatMessage(
              text: '已进入与 [${widget.payload.title}] 的独立会话',
              isMe: false,
              time: DateTime.now(),
              isSystem: true,
            ),
          );
          _messages.addAll(list);
          _isLoading = false;
        });
        _scrollToBottom();
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _handleSendMessage({String? overrideText, String? retryClientId}) async {
    final text = overrideText ?? _inputController.text.trim();
    if (text.isEmpty) return;

    final clientMessageId = retryClientId ??
        'cmsg_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(99999)}';

    if (retryClientId == null) {
      _inputController.clear();
      setState(() {
        _messages.add(
          _ChatMessage(
            clientMessageId: clientMessageId,
            text: text,
            isMe: true,
            time: DateTime.now(),
            state: 'sending',
          ),
        );
      });
      _scrollToBottom();
    } else {
      setState(() {
        final idx = _messages.indexWhere((m) => m.clientMessageId == retryClientId);
        if (idx != -1) {
          _messages[idx] = _messages[idx].copyWith(state: 'sending');
        }
      });
    }

    try {
      final dynamic res = await _mainIpcChannel.invokeMethod('chat_send_message', {
        'sessionUnitId': widget.payload.sessionUnitId,
        'ownerId': widget.payload.ownerId,
        'content': text,
        'clientMessageId': clientMessageId,
      });

      if (res is Map && res['success'] == true && mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.clientMessageId == clientMessageId);
          if (idx != -1) {
            _messages[idx] = _messages[idx].copyWith(
              serverId: (res['serverId'] as num?)?.toInt(),
              state: res['state']?.toString() ?? 'sent',
            );
          }
        });
      } else {
        _markMessageFailed(clientMessageId);
      }
    } catch (_) {
      _markMessageFailed(clientMessageId);
    }
  }

  void _markMessageFailed(String clientMessageId) {
    if (!mounted) return;
    setState(() {
      final idx = _messages.indexWhere((m) => m.clientMessageId == clientMessageId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(state: 'failed');
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5);
    final titleBarColor =
        isDark ? const Color(0xFF232323) : const Color(0xFFEBEBEB);
    final inputBg = isDark ? const Color(0xFF262626) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      body: Column(
        children: [
          // 1. 微信桌面风格无边框沉浸式标题栏
          _buildTitleBar(isDark, titleBarColor),

          // 2. 消息内容流
          Expanded(child: _buildMessageList(isDark)),

          // 3. 底部快捷工具与输入区
          _buildInputArea(isDark, inputBg),
        ],
      ),
    );
  }

  Widget _buildTitleBar(bool isDark, Color bg) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0x1FFFFFFF) : const Color(0x1F000000),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.chat_bubble_outline_rounded,
            size: 18,
            color: Color(0xFF07C160),
          ),
          const SizedBox(width: 10),
          Text(
            widget.payload.title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const Spacer(),
          // 置顶按钮
          IconButton(
            icon: Icon(
              _isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              size: 16,
              color: _isPinned ? const Color(0xFF07C160) : Colors.grey,
            ),
            tooltip: _isPinned ? '取消置顶' : '置顶窗口',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              setState(() {
                _isPinned = !_isPinned;
              });
            },
          ),
          // 最小化
          IconButton(
            icon: const Icon(Icons.remove_rounded, size: 16),
            tooltip: '最小化',
            visualDensity: VisualDensity.compact,
            onPressed: () => widget.controller.hide(),
          ),
          // 最大化/还原
          IconButton(
            icon: Icon(
              _isMaximized
                  ? Icons.filter_none_rounded
                  : Icons.crop_square_rounded,
              size: 15,
            ),
            tooltip: _isMaximized ? '还原' : '最大化',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              setState(() {
                _isMaximized = !_isMaximized;
              });
            },
          ),
          // 关闭按钮
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 17),
            tooltip: '关闭',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              if (widget.onClose != null) {
                widget.onClose!();
              } else {
                widget.controller.hide();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(bool isDark) {
    if (_isLoading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_messages.isEmpty) {
      return Center(
        child: Text(
          '暂无历史消息',
          style: TextStyle(
            color: isDark ? Colors.white38 : Colors.black38,
            fontSize: 13,
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        if (msg.isSystem) {
          return Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : Colors.black12,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                msg.text,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ),
          );
        }

        final timeStr =
            '${msg.time.hour.toString().padLeft(2, '0')}:${msg.time.minute.toString().padLeft(2, '0')}';

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!msg.isMe) ...[
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF07C160),
                  child: Text(
                    widget.payload.title.characters.firstOrNull ?? 'U',
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (msg.isMe && msg.state == 'sending') ...[
                const Padding(
                  padding: EdgeInsets.only(right: 6, bottom: 4),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ],
              if (msg.isMe && msg.state == 'failed') ...[
                Padding(
                  padding: const EdgeInsets.only(right: 4, bottom: 2),
                  child: GestureDetector(
                    onTap: () => _handleSendMessage(
                      overrideText: msg.text,
                      retryClientId: msg.clientMessageId,
                    ),
                    child: const Tooltip(
                      message: '发送失败，点击重试',
                      child: Icon(
                        Icons.error_outline_rounded,
                        size: 18,
                        color: Colors.redAccent,
                      ),
                    ),
                  ),
                ),
              ],
              Flexible(
                child: Column(
                  crossAxisAlignment:
                      msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: msg.isMe
                            ? const Color(0xFF07C160)
                            : (isDark
                                ? const Color(0xFF2C2C2C)
                                : Colors.white),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Text(
                        msg.text,
                        style: TextStyle(
                          fontSize: 14,
                          color: msg.isMe
                              ? Colors.white
                              : (isDark ? Colors.white : Colors.black87),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  ],
                ),
              ),
              if (msg.isMe) ...[
                const SizedBox(width: 8),
                const CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.blueAccent,
                  child: Icon(Icons.person, size: 18, color: Colors.white),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildInputArea(bool isDark, Color inputBg) {
    return Container(
      decoration: BoxDecoration(
        color: inputBg,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0x1FFFFFFF) : const Color(0x1F000000),
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        children: [
          // 快捷工具栏 (表情、图片、文件、截图)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.sentiment_satisfied_alt_rounded,
                    size: 20,
                  ),
                  tooltip: '表情',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    showToast('请在主窗口或直接使用系统输入法表情', type: ToastType.info);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.image_outlined, size: 20),
                  tooltip: '发送图片',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    showToast('独立窗口可通过剪贴板粘贴直接发送图片', type: ToastType.info);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.folder_open_rounded, size: 20),
                  tooltip: '发送文件',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    showToast('独立窗口可通过剪贴板粘贴直接发送文件', type: ToastType.info);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.content_cut_rounded, size: 20),
                  tooltip: '截图',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    showToast('支持使用 Win+Shift+S 截图后直接粘贴发送', type: ToastType.info);
                  },
                ),
              ],
            ),
          ),
          // 文本输入行与发送按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Focus(
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.enter) {
                        if (HardwareKeyboard.instance.isShiftPressed ||
                            HardwareKeyboard.instance.isControlPressed) {
                          return KeyEventResult.ignored;
                        } else {
                          _handleSendMessage();
                          return KeyEventResult.handled;
                        }
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      controller: _inputController,
                      focusNode: _focusNode,
                      maxLines: 4,
                      minLines: 1,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      decoration: const InputDecoration(
                        hintText: '按 Enter 发送消息，Shift/Ctrl+Enter 换行...',
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _handleSendMessage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF07C160),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    elevation: 0,
                  ),
                  child: const Text('发送'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatMessage {
  const _ChatMessage({
    required this.text,
    required this.isMe,
    required this.time,
    this.id,
    this.serverId,
    this.clientMessageId,
    this.state = 'sent',
    this.isSystem = false,
  });

  final String? id;
  final int? serverId;
  final String? clientMessageId;
  final String text;
  final bool isMe;
  final DateTime time;
  final String state; // 'sending', 'sent', 'failed'
  final bool isSystem;

  _ChatMessage copyWith({
    String? id,
    int? serverId,
    String? clientMessageId,
    String? text,
    bool? isMe,
    DateTime? time,
    String? state,
    bool? isSystem,
  }) {
    return _ChatMessage(
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      clientMessageId: clientMessageId ?? this.clientMessageId,
      text: text ?? this.text,
      isMe: isMe ?? this.isMe,
      time: time ?? this.time,
      state: state ?? this.state,
      isSystem: isSystem ?? this.isSystem,
    );
  }
}
