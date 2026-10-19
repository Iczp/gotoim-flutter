import 'dart:math' as math;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/chat/data/models/chat_message.dart' as domain;
import '../../features/chat/presentation/message_content/chat_message_content_renderer.dart';
import '../services/file/attachment_transfer_service.dart';
import '../services/window_service.dart';
import '../media/media_preview.dart';
import '../config/app_environment.dart';
import '../utils/api_url_resolver.dart';

import 'package:file_picker/file_picker.dart';
import '../services/file/file_picker_service.dart';
import '../../features/chat/presentation/widgets/chat_composer.dart';
import '../../features/chat/presentation/widgets/chat_composer_controller.dart';
import '../../features/chat_settings/data/models/chat_member.dart';

import '../../core/widgets/app_toast.dart';
import '../platform/windows/windows_window_adapter.dart';
import 'native_window_payload.dart';

/// 桌面端微信风格独立聊天子窗口视图
class DesktopSubWindowChatView extends StatefulWidget {
  const DesktopSubWindowChatView({
    required this.payload,
    required this.controller,
    this.onClose,
    this.onRegisterHandler,
    super.key,
  });

  final NativeWindowPayload payload;
  final WindowController controller;
  final VoidCallback? onClose;
  final void Function(Future<dynamic> Function(MethodCall call)? handler)?
  onRegisterHandler;

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
  bool _loadingHistory = false;
  bool _refreshPending = false;
  bool _hasMore = true;
  final Map<String, AttachmentTransferState> _attachments = {};
  bool _isPinned = false;
  bool _isMaximized = false;

  late final WindowMethodChannel _mainIpcChannel;
  late final SubWindowChatController _subWindowChatController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WindowsWindowAdapter.setupCustomTitleBar();
      if (mounted) {
        setState(() {
          _isMaximized = WindowsWindowAdapter.isMaximized();
        });
      }
    });

    _mainIpcChannel = const WindowMethodChannel(
      'gotoim/ipc_to_main',
      mode: ChannelMode.bidirectional,
    );

    _subWindowChatController = SubWindowChatController(
      sessionUnitId: widget.payload.sessionUnitId ?? '',
      ownerId: widget.payload.ownerId ?? 0,
      mainIpcChannel: _mainIpcChannel,
      onSendMessage: (text, {quote}) {
        _handleSendMessage(overrideText: text);
      },
      onSendImage: (bytes, {caption, fileName}) async {
        final clientMsgId = 'cmsg_img_${DateTime.now().millisecondsSinceEpoch}';
        final effectiveName =
            fileName ?? 'image_${DateTime.now().millisecondsSinceEpoch}.png';
        if (mounted) {
          setState(() {
            _messages.add(
              _ChatMessage(
                clientMessageId: clientMsgId,
                text: caption ?? '[图片]',
                isMe: true,
                time: DateTime.now(),
                state: 'sending',
              ),
            );
          });
          _scrollToBottom();
        }
        try {
          final res = await _mainIpcChannel.invokeMethod('chat_send_image', {
            'sessionUnitId': widget.payload.sessionUnitId,
            'ownerId': widget.payload.ownerId,
            'bytes': bytes.toList(),
            'fileName': effectiveName,
            'caption': caption,
          });
          if (res is Map && res['success'] == true && mounted) {
            setState(() {
              final idx = _messages.indexWhere(
                (m) => m.clientMessageId == clientMsgId,
              );
              if (idx != -1) {
                _messages[idx] = _messages[idx].copyWith(
                  serverId: (res['serverId'] as num?)?.toInt(),
                  state: res['state']?.toString() ?? 'sent',
                );
              }
            });
          } else {
            _markMessageFailed(clientMsgId);
          }
        } catch (_) {
          _markMessageFailed(clientMsgId);
        }
      },
      onSendFiles: (filePaths, {caption}) async {
        for (final p in filePaths) {
          final clientMsgId =
              'cmsg_file_${DateTime.now().millisecondsSinceEpoch}';
          final fileName = p.split(r'\').last.split('/').last;
          if (mounted) {
            setState(() {
              _messages.add(
                _ChatMessage(
                  clientMessageId: clientMsgId,
                  text: '[文件] $fileName',
                  isMe: true,
                  time: DateTime.now(),
                  state: 'sending',
                ),
              );
            });
            _scrollToBottom();
          }
        }
        try {
          await _mainIpcChannel.invokeMethod('chat_send_files', {
            'sessionUnitId': widget.payload.sessionUnitId,
            'ownerId': widget.payload.ownerId,
            'filePaths': filePaths,
            'caption': caption,
          });
        } catch (_) {}
      },
    );

    Future<dynamic> handler(MethodCall call) async {
      switch (call.method) {
        case 'chat_receive_message':
          final data = call.arguments as Map?;
          if (data != null && mounted) {
            final t = data['time'];
            final time =
                t is num
                    ? DateTime.fromMillisecondsSinceEpoch(t.toInt())
                    : DateTime.now();
            final clientMsgId = data['clientMessageId']?.toString();
            final serverId = (data['serverId'] as num?)?.toInt();
            final newMsg = _ChatMessage(
              id: data['id']?.toString(),
              serverId: serverId,
              clientMessageId: clientMsgId,
              text: data['text']?.toString() ?? '',
              message:
                  data['raw'] is Map
                      ? domain.ChatMessage.fromWindowPayload(data)
                      : null,
              isMe: data['isMe'] == true,
              time: time,
              state: data['state']?.toString() ?? 'sent',
            );
            setState(() {
              final existingIndex = _messages.indexWhere(
                (m) =>
                    (clientMsgId != null && m.clientMessageId == clientMsgId) ||
                    (serverId != null &&
                        serverId != 0 &&
                        m.serverId == serverId),
              );
              if (existingIndex != -1) {
                _messages[existingIndex] = newMsg;
              } else {
                _messages.add(newMsg);
              }
            });
            _scrollToBottom();
          }
          return true;
        case 'chat_refresh':
        case 'bringToFront':
          await _loadHistory();
          return true;
        case 'account_logout':
          if (mounted) {
            setState(() {
              _messages.clear();
            });
          }
          widget.onClose?.call();
          return true;
        default:
          return null;
      }
    }

    if (widget.onRegisterHandler != null) {
      widget.onRegisterHandler!(handler);
    } else {
      widget.controller.setWindowMethodHandler(handler);
    }

    _loadHistory();
  }

  Future<void> _loadHistory({bool older = false}) async {
    if (_loadingHistory) {
      if (!older) _refreshPending = true;
      return;
    }
    _loadingHistory = true;
    final previousOffset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    final scores = _messages
        .map((m) => m.message?.score)
        .whereType<int>()
        .where((s) => s > 0);
    final beforeScore =
        older && scores.isNotEmpty ? scores.reduce(math.min) : null;
    setState(() => _isLoading = _messages.isEmpty);
    try {
      final dynamic raw = await _mainIpcChannel
          .invokeMethod('chat_load_history', {
            'sessionUnitId': widget.payload.sessionUnitId,
            'ownerId': widget.payload.ownerId,
            if (beforeScore != null) 'beforeScore': beforeScore,
          });

      if (raw is List && mounted) {
        final list = <_ChatMessage>[];
        for (final item in raw) {
          if (item is Map) {
            final t = item['time'];
            final time =
                t is num
                    ? DateTime.fromMillisecondsSinceEpoch(t.toInt())
                    : DateTime.now();
            list.add(
              _ChatMessage(
                id: item['id']?.toString(),
                serverId: (item['serverId'] as num?)?.toInt(),
                clientMessageId: item['clientMessageId']?.toString(),
                text: item['text']?.toString() ?? '',
                message:
                    item['raw'] is Map
                        ? domain.ChatMessage.fromWindowPayload(item)
                        : null,
                isMe: item['isMe'] == true,
                time: time,
                state: item['state']?.toString() ?? 'sent',
              ),
            );
          }
        }
        setState(() {
          final merged = <String, _ChatMessage>{};
          for (final m in [..._messages, ...list]) {
            merged[m.clientMessageId ??
                    m.serverId?.toString() ??
                    m.id ??
                    '${m.time.microsecondsSinceEpoch}'] =
                m;
          }
          _messages
            ..clear()
            ..addAll(merged.values);
          _messages.sort((a, b) => a.time.compareTo(b.time));
          if (older) _hasMore = list.isNotEmpty;
          _isLoading = false;
        });
        // Reverse layout anchors the newest item at zero even when images
        // change height after loading. Older pages append away from the anchor.
        if (!older && previousOffset <= 80) _scrollToBottom();
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _isLoading = false);
        showToast('加载历史消息失败，请重试', type: ToastType.error);
      }
    } finally {
      _loadingHistory = false;
      if (_refreshPending && mounted) {
        _refreshPending = false;
        _loadHistory();
      }
    }
  }

  @override
  void didUpdateWidget(covariant DesktopSubWindowChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.payload.sessionUnitId != widget.payload.sessionUnitId ||
        oldWidget.payload.ownerId != widget.payload.ownerId) {
      _loadHistory();
    }
  }

  @override
  void dispose() {
    widget.onRegisterHandler?.call(null);
    _subWindowChatController.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _handleSendMessage({
    String? overrideText,
    String? retryClientId,
  }) async {
    final text = overrideText ?? _inputController.text.trim();
    if (text.isEmpty) return;

    final clientMessageId =
        retryClientId ??
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
        final idx = _messages.indexWhere(
          (m) => m.clientMessageId == retryClientId,
        );
        if (idx != -1) {
          _messages[idx] = _messages[idx].copyWith(state: 'sending');
        }
      });
    }

    try {
      final dynamic res = await _mainIpcChannel
          .invokeMethod('chat_send_message', {
            'sessionUnitId': widget.payload.sessionUnitId,
            'ownerId': widget.payload.ownerId,
            'content': text,
            'clientMessageId': clientMessageId,
          });

      if (res is Map && res['success'] == true && mounted) {
        setState(() {
          final idx = _messages.indexWhere(
            (m) => m.clientMessageId == clientMessageId,
          );
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
      final idx = _messages.indexWhere(
        (m) => m.clientMessageId == clientMessageId,
      );
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(state: 'failed');
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
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

    return Scaffold(
      backgroundColor: bgColor,
      body: Column(
        children: [
          // 1. 微信桌面风格无边框沉浸式标题栏
          _buildTitleBar(isDark, titleBarColor),

          // 2. 消息内容流
          Expanded(child: _buildMessageList(isDark)),

          // 3. 微信同款 ChatComposer 统一输入区（复用非独立聊天输入框，带高度拖拽、截图、文件粘贴、表情等）
          ChatComposer(
            controller: _subWindowChatController,
            input: _inputController,
            isDesktop: true,
            quoteContentBuilder:
                (quote) => Text(
                  '${quote.senderName}: ${quote.text}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleBar(bool isDark, Color bg) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => WindowsWindowAdapter.startDragging(),
      onDoubleTap: () {
        WindowsWindowAdapter.toggleMaximize();
        if (mounted) {
          setState(() {
            _isMaximized = WindowsWindowAdapter.isMaximized();
          });
        }
      },
      child: Container(
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
            Expanded(
              child: Text(
                widget.payload.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
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
                WindowsWindowAdapter.setAlwaysOnTop(_isPinned);
              },
            ),
            // 最小化
            IconButton(
              icon: const Icon(Icons.remove_rounded, size: 16),
              tooltip: '最小化',
              visualDensity: VisualDensity.compact,
              onPressed: () => WindowsWindowAdapter.minimize(),
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
                WindowsWindowAdapter.toggleMaximize();
                if (mounted) {
                  setState(() {
                    _isMaximized = WindowsWindowAdapter.isMaximized();
                  });
                }
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
                  WindowsWindowAdapter.close();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _messageAction(domain.ChatMessage message, String action) async {
    try {
      final raw = await _mainIpcChannel.invokeMethod('chat_message_action', {
        'action': action,
        'message': message.toWindowPayload(),
      });
      if (!mounted || raw is! Map) return;
      if (raw['success'] != true) throw StateError('附件操作失败');
      setState(
        () =>
            _attachments[message.localId] = AttachmentTransferState(
              status:
                  raw['status'] == 'completed'
                      ? AttachmentTransferStatus.completed
                      : AttachmentTransferStatus.idle,
              localPath: raw['localPath'] as String?,
            ),
      );
    } catch (_) {
      if (mounted) showToast('操作失败，请检查连接后重试', type: ToastType.error);
    }
  }

  Widget _buildRichContent(domain.ChatMessage message) => Consumer(
    builder: (context, ref, _) {
      if (message.messageType == 3) {
        return TextButton.icon(
          icon: const Icon(Icons.volume_up),
          label: Text('语音 ${message.audioDuration.inSeconds}秒'),
          onPressed: () => _messageAction(message, 'voice'),
        );
      }
      final mediaItems =
          message.mediaUrl == null
              ? <MediaPreviewItem>[]
              : [
                MediaPreviewItem(
                  id: message.localId,
                  messageId: message.serverId?.toString() ?? message.localId,
                  type:
                      message.messageType == 4
                          ? MediaPreviewType.video
                          : MediaPreviewType.image,
                  source: resolveApiUrl(
                    message.mediaUrl,
                    ref.read(appEnvironmentProvider).apiBaseUrl,
                  ),
                  heroTag: message.localId,
                  localPath: message.localFilePath,
                ),
              ];
      return ChatMessageContentRenderer(
        message: message,
        attachmentState:
            _attachments[message.localId] ?? const AttachmentTransferState(),
        onVoiceOpened: () => _messageAction(message, 'voice'),
        onAttachmentDownload: () => _messageAction(message, 'download'),
        onAttachmentCancel: () => _messageAction(message, 'cancel'),
        onAttachmentOpen: () => _messageAction(message, 'open'),
        onAttachmentSaveAs: () => _messageAction(message, 'saveAs'),
        onLinkTap:
            () => ref
                .read(windowServiceProvider)
                .openWebBrowser(url: message.mediaUrl ?? ''),
        imageBytes: null,
        uploadProgress: null,
        apiBaseUrl: ref.read(appEnvironmentProvider).apiBaseUrl,
        mediaItems: mediaItems,
        mediaInitialIndex: 0,
        maxWidth: 440,
      );
    },
  );

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
      reverse: true,
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _messages.length + 1,
      itemBuilder: (context, index) {
        if (index == _messages.length) {
          return Center(
            child: TextButton(
              onPressed:
                  _hasMore && !_loadingHistory
                      ? () => _loadHistory(older: true)
                      : null,
              child: Text(_hasMore ? '加载更早消息' : '已加载全部历史消息'),
            ),
          );
        }
        final msg = _messages[_messages.length - 1 - index];
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
                    onTap:
                        () => _handleSendMessage(
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
                      msg.isMe
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding:
                          msg.message != null
                              ? EdgeInsets.zero
                              : const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                      decoration:
                          msg.message != null
                              ? null
                              : BoxDecoration(
                                color:
                                    msg.isMe
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
                      child:
                          msg.message != null
                              ? _buildRichContent(msg.message!)
                              : Text(
                                msg.text,
                                style: TextStyle(
                                  fontSize: 14,
                                  color:
                                      msg.isMe
                                          ? Colors.white
                                          : (isDark
                                              ? Colors.white
                                              : Colors.black87),
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
    this.message,
  });

  final domain.ChatMessage? message;
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
      message: message,
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

class SubWindowChatController extends ChangeNotifier
    implements ChatComposerController {
  SubWindowChatController({
    required this.sessionUnitId,
    required this.ownerId,
    required this.mainIpcChannel,
    required this.onSendMessage,
    required this.onSendImage,
    required this.onSendFiles,
  });

  final String sessionUnitId;
  final int ownerId;
  final WindowMethodChannel mainIpcChannel;
  final void Function(String text, {domain.ChatMessage? quote}) onSendMessage;
  final Future<void> Function(
    Uint8List bytes, {
    String? caption,
    String? fileName,
  })
  onSendImage;
  final Future<void> Function(List<String> filePaths, {String? caption})
  onSendFiles;

  @override
  bool get isOfficialAccount => false;

  @override
  List<Map<String, dynamic>> get officialAccountMenus => const [];

  @override
  bool get isMuted => false;

  @override
  bool isSending = false;

  domain.ChatMessage? _quoting;

  @override
  domain.ChatMessage? get quoting => _quoting;

  @override
  void quoteMessage(domain.ChatMessage message) {
    _quoting = message;
    notifyListeners();
  }

  @override
  void cancelQuote() {
    _quoting = null;
    notifyListeners();
  }

  @override
  bool get mentionVisible => false;

  @override
  String get mentionKeyword => '';

  @override
  List<ChatMember> get mentionMembers => const [];

  @override
  bool get mentionLoading => false;

  @override
  bool get mentionHasMore => false;

  @override
  void updateMentionInput(String text) {}

  @override
  void dismissMention() {}

  @override
  void updateMentionKeyword(String keyword) {}

  @override
  Future<void> loadMoreMentions() async {}

  @override
  String toggleMention(String text, ChatMember member) => text;

  @override
  bool isMemberMentioned(ChatMember member, String text) => false;

  @override
  Future<bool> hasVoiceRecordingPermission() async => false;

  @override
  Future<void> startVoiceRecording() async {}

  @override
  Future<void> cancelVoiceRecording() async {}

  @override
  Future<void> finishVoiceRecording(Duration duration) async {}

  @override
  Stream<double> voiceRecordingLevels(Duration interval) =>
      const Stream.empty();

  @override
  void send(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final currentQuote = _quoting;
    _quoting = null;
    notifyListeners();
    onSendMessage(trimmed, quote: currentQuote);
  }

  @override
  Future<void> sendImageBytes(
    Uint8List bytes, {
    String? caption,
    String? fileName,
  }) async {
    await onSendImage(bytes, caption: caption, fileName: fileName);
  }

  @override
  Future<void> sendDirectFiles(
    List<SelectedFile> files, {
    String? caption,
  }) async {
    if (files.isEmpty) return;
    final paths = files.map((f) => f.originalPath).whereType<String>().toList();
    if (paths.isEmpty) return;
    await onSendFiles(paths, caption: caption);
  }

  @override
  Future<void> chooseAndSendImages() async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.image,
        dialogTitle: '选择要发送的图片',
      );
      if (picked.isNotEmpty) {
        final paths = picked.map((f) => f.path).whereType<String>().toList();
        if (paths.isNotEmpty) {
          await onSendFiles(paths);
        }
      }
    } catch (_) {}
  }

  @override
  Future<void> chooseAndSendFile() async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.any,
        dialogTitle: '选择要发送的文件',
      );
      if (picked.isNotEmpty) {
        final paths = picked.map((f) => f.path).whereType<String>().toList();
        if (paths.isNotEmpty) {
          await onSendFiles(paths);
        }
      }
    } catch (_) {}
  }

  @override
  Future<void> takeAndSendPhoto() async {
    await chooseAndSendImages();
  }

  @override
  Future<void> chooseAndSendVideo() async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.video,
        dialogTitle: '选择要发送的视频',
      );
      if (picked.isNotEmpty) {
        final paths = picked.map((f) => f.path).whereType<String>().toList();
        if (paths.isNotEmpty) {
          await onSendFiles(paths);
        }
      }
    } catch (_) {}
  }
}
