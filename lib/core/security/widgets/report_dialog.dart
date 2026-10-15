import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/chat/data/models/chat_message.dart';
import '../../widgets/app_toast.dart';
import '../url_security_repository.dart';

/// 投诉/举报标准化类型
class ReportReasonOption {
  const ReportReasonOption({
    required this.code,
    required this.label,
    required this.description,
  });

  final String code;
  final String label;
  final String description;
}

const List<ReportReasonOption> kDefaultReportReasons = [
  ReportReasonOption(
    code: 'fraud',
    label: '涉嫌欺诈 / 电信诈骗 / 杀猪盘',
    description: '虚假兼职刷单、冒充客服领奖、诱导投资转账等',
  ),
  ReportReasonOption(
    code: 'porn',
    label: '传播色情低俗内容',
    description: '含有色情、淫秽、低俗暴恐等违规信息',
  ),
  ReportReasonOption(
    code: 'gambling',
    label: '涉嫌赌博与非法彩票',
    description: '在线百家乐、私彩、赌博开奖等违规活动',
  ),
  ReportReasonOption(
    code: 'phishing_malware',
    label: '仿冒钓鱼 / 病毒木马 / 恶意软件',
    description: '仿冒官方网站、窃取账号密码、诱导下载恶意安装包',
  ),
  ReportReasonOption(
    code: 'misleading',
    label: '诱导分享与虚假营销',
    description: '强制分享、虚假砍价、引诱裂变传播',
  ),
  ReportReasonOption(
    code: 'infringement',
    label: '侵犯个人隐私或名誉权',
    description: '泄露个人隐私信息、人身攻击、造谣诽谤',
  ),
  ReportReasonOption(
    code: 'other',
    label: '其他违规行为',
    description: '其他违反国家法律法规或平台守则的行为',
  ),
];

/// 通用投诉/举报弹窗组件（支持对 URL 或聊天消息发起投诉）
class ReportDialog extends ConsumerStatefulWidget {
  const ReportDialog({
    required this.target,
    required this.targetType,
    this.messageId,
    this.targetTitle,
    super.key,
  });

  /// 投诉目标（URL 字符串 或 消息文本摘要）
  final String target;

  /// 目标类型：'url' | 'message' | 'user'
  final String targetType;

  /// 可选关联的消息唯一标识
  final String? messageId;

  /// 可选目标展示标题
  final String? targetTitle;

  /// 针对网页/URL 发起投诉
  static Future<bool?> showForUrl(
    BuildContext context, {
    required String url,
    String? title,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => ReportDialog(
        target: url,
        targetType: 'url',
        targetTitle: title,
      ),
    );
  }

  /// 针对聊天消息发起投诉
  static Future<bool?> showForMessage(
    BuildContext context, {
    required ChatMessage message,
  }) {
    final preview = message.text.isNotEmpty
        ? message.text
        : (message.linkUrl.isNotEmpty ? message.linkUrl : '[媒体内容]');
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => ReportDialog(
        target: preview,
        targetType: 'message',
        messageId: message.serverId?.toString() ?? message.localId,
        targetTitle: '来自「${message.senderName}」的消息',
      ),
    );
  }

  @override
  ConsumerState<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends ConsumerState<ReportDialog> {
  String _selectedReason = 'fraud';
  final TextEditingController _descController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    try {
      final repo = ref.read(urlSecurityRepositoryProvider);
      final reasonObj = kDefaultReportReasons.firstWhere(
        (r) => r.code == _selectedReason,
        orElse: () => kDefaultReportReasons.first,
      );

      final success = await repo.report(
        target: widget.target,
        targetType: widget.targetType,
        reason: '${reasonObj.label} (${reasonObj.code})',
        description: _descController.text.trim(),
        messageId: widget.messageId,
      );

      if (!mounted) return;
      if (success) {
        Navigator.of(context).pop(true);
        showToast('投诉已提交，平台安全团队将在24小时内核实处置', type: ToastType.success);
      } else {
        showToast('提交失败，请稍后重试', type: ToastType.error);
      }
    } catch (e) {
      if (mounted) {
        showToast('网络异常: $e', type: ToastType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.report_problem_rounded,
              color: Color(0xFFEF4444),
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.targetType == 'url' ? '投诉违规网页' : '投诉违规消息',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 目标预览
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.targetTitle != null)
                      Text(
                        widget.targetTitle!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    Text(
                      widget.target,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '请选择投诉原因：',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              // 原因列表 Radio 选项
              ...kDefaultReportReasons.map((reason) {
                final isSelected = _selectedReason == reason.code;
                return InkWell(
                  onTap: () {
                    setState(() => _selectedReason = reason.code);
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 18,
                          height: 18,
                          margin: const EdgeInsets.only(top: 2, right: 8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : (isDark ? Colors.white38 : Colors.black38),
                              width: isSelected ? 5.5 : 1.5,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                reason.label,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                  color: isSelected
                                      ? theme.colorScheme.primary
                                      : (isDark ? Colors.white : Colors.black87),
                                ),
                              ),
                              Text(
                                reason.description,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? Colors.white38 : Colors.black38,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 10),
              // 补充描述
              TextField(
                controller: _descController,
                maxLines: 2,
                maxLength: 200,
                decoration: InputDecoration(
                  hintText: '补充详细描述或受骗情况（选填）',
                  hintStyle: const TextStyle(fontSize: 12),
                  filled: true,
                  fillColor: isDark ? Colors.white10 : const Color(0xFFF9FAFB),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: isDark ? Colors.white24 : const Color(0xFFE5E7EB),
                    ),
                  ),
                  contentPadding: const EdgeInsets.all(10),
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消', style: TextStyle(color: Colors.grey)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFEF4444),
          ),
          onPressed: _isSubmitting ? null : _handleSubmit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('确认举报'),
        ),
      ],
    );
  }
}
