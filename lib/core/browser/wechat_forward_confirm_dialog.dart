import 'package:flutter/material.dart';

import '../../features/session/data/models/session_summary.dart';
import '../widgets/app_avatar.dart';
import '../widgets/avatar_preferences.dart';

/// 微信转发确认弹窗返回结果。
class WeChatForwardConfirmResult {
  const WeChatForwardConfirmResult({required this.comment});
  final String comment;
}

/// 微信同款「发送给朋友」高保真确认弹窗。
///
/// 包含：
/// - 发送目标头像与昵称；
/// - 网页链接卡片缩略预览；
/// - 「给朋友留言」输入框；
/// - 取消与微信绿「发送」按钮。
class WeChatForwardConfirmDialog extends StatefulWidget {
  const WeChatForwardConfirmDialog({
    required this.targets,
    required this.url,
    this.title,
    super.key,
  });

  final List<SessionSummary> targets;
  final String url;
  final String? title;

  static Future<WeChatForwardConfirmResult?> show(
    BuildContext context, {
    required List<SessionSummary> targets,
    required String url,
    String? title,
  }) {
    return showDialog<WeChatForwardConfirmResult>(
      context: context,
      barrierDismissible: true,
      builder: (_) => WeChatForwardConfirmDialog(
        targets: targets,
        url: url,
        title: title,
      ),
    );
  }

  @override
  State<WeChatForwardConfirmDialog> createState() =>
      _WeChatForwardConfirmDialogState();
}

class _WeChatForwardConfirmDialogState
    extends State<WeChatForwardConfirmDialog> {
  final TextEditingController _commentController = TextEditingController();

  String get _domain {
    try {
      final uri = Uri.parse(widget.url);
      return uri.host.isNotEmpty ? uri.host : '网页链接';
    } catch (_) {
      return '网页链接';
    }
  }

  String get _displayTitle =>
      (widget.title != null && widget.title!.isNotEmpty)
          ? widget.title!
          : _domain;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF7F7F7);
    final inputBg = isDark ? const Color(0xFF333333) : const Color(0xFFF0F0F0);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: isDark ? const Color(0xFF222222) : Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. 发送给 标题与目标信息
              const Text(
                '发送给:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 10),
              if (widget.targets.length == 1) ...[
                Row(
                  children: [
                    AppAvatar(
                      name: widget.targets.first.title,
                      imageUrl: widget.targets.first.avatarUrl,
                      size: 40,
                      shape: AvatarShape.square,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.targets.first.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    SizedBox(
                      height: 36,
                      child: ListView.separated(
                        shrinkWrap: true,
                        scrollDirection: Axis.horizontal,
                        itemCount: widget.targets.length.clamp(0, 4),
                        separatorBuilder: (_, _) => const SizedBox(width: 6),
                        itemBuilder: (context, index) {
                          final target = widget.targets[index];
                          return AppAvatar(
                            name: target.title,
                            imageUrl: target.avatarUrl,
                            size: 36,
                            shape: AvatarShape.square,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '共 ${widget.targets.length} 个目标',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),

              // 2. 链接卡片预览
              Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                    width: 0.8,
                  ),
                ),
                padding: const EdgeInsets.all(10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF07C160).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.link_rounded,
                        color: Color(0xFF07C160),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _displayTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : const Color(0xFF222222),
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _domain,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white38 : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 3. 给朋友留言输入框
              TextField(
                controller: _commentController,
                maxLines: 2,
                minLines: 1,
                style: const TextStyle(fontSize: 13.5),
                decoration: InputDecoration(
                  hintText: '给朋友留言',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white38 : Colors.grey,
                  ),
                  filled: true,
                  fillColor: inputBg,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 4. 操作按钮（取消 / 微信绿 发送）
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    style: TextButton.styleFrom(
                      foregroundColor: isDark ? Colors.white60 : Colors.black54,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    child: const Text('取消', style: TextStyle(fontSize: 15)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      final comment = _commentController.text.trim();
                      Navigator.of(context).pop(
                        WeChatForwardConfirmResult(comment: comment),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF07C160),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: const Text(
                      '发送',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
