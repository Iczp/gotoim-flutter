import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/app_toast.dart';
import '../url_security_repository.dart';

/// 误报申诉理由选项
class AppealReasonOption {
  const AppealReasonOption({
    required this.code,
    required this.label,
    required this.description,
  });

  final String code;
  final String label;
  final String description;
}

const List<AppealReasonOption> kDefaultAppealReasons = [
  AppealReasonOption(
    code: 'whitelisted_safe',
    label: '正规官方网站 / 知名企业业务',
    description: '合法合规的企业官网、公开公共服务、已备案站点',
  ),
  AppealReasonOption(
    code: 'personal_tech',
    label: '个人技术博客 / 开源项目 / 文档',
    description: 'GitHub、开源社区、技术博文分享等技术类安全资源',
  ),
  AppealReasonOption(
    code: 'repaired',
    label: '历史风险已整改，申请解除拦截',
    description: '已清除被黑客攻击、恶意挂马或违规的内容，恢复正常服务',
  ),
  AppealReasonOption(
    code: 'internal_tool',
    label: '企业内部系统 / 协同办公平台',
    description: '内网办公系统、OA、CRM 等组织内部合法使用的域名',
  ),
  AppealReasonOption(
    code: 'other',
    label: '其他误报情况说明',
    description: '未被上述分类涵盖的正常网站或误伤拦截',
  ),
];

/// 网站误报与加白申诉弹窗组件
class AppealDialog extends ConsumerStatefulWidget {
  const AppealDialog({
    required this.url,
    this.domain,
    this.title,
    super.key,
  });

  final String url;
  final String? domain;
  final String? title;

  /// 快速调起申诉弹窗
  static Future<bool?> show(
    BuildContext context, {
    required String url,
    String? domain,
    String? title,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AppealDialog(
        url: url,
        domain: domain,
        title: title,
      ),
    );
  }

  @override
  ConsumerState<AppealDialog> createState() => _AppealDialogState();
}

class _AppealDialogState extends ConsumerState<AppealDialog> {
  String _selectedReason = 'whitelisted_safe';
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _descController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    try {
      final repo = ref.read(urlSecurityRepositoryProvider);
      final reasonObj = kDefaultAppealReasons.firstWhere(
        (r) => r.code == _selectedReason,
        orElse: () => kDefaultAppealReasons.first,
      );

      final contactText = _contactController.text.trim();
      final descText = _descController.text.trim();
      final fullDesc = StringBuffer();
      if (descText.isNotEmpty) {
        fullDesc.writeln(descText);
      }
      if (contactText.isNotEmpty) {
        fullDesc.write('联系方式 / 备案号: $contactText');
      }

      final success = await repo.report(
        target: widget.url,
        targetType: 'url',
        reason: '【误报申诉】${reasonObj.label}',
        description: fullDesc.toString(),
      );

      if (!mounted) return;
      if (success) {
        Navigator.of(context).pop(true);
        showToast('申诉已提交', type: ToastType.success);
      } else {
        showToast('提交失败，请检查网络或稍后重试', type: ToastType.error);
      }
    } catch (e) {
      if (mounted) {
        showToast('网络请求异常: $e', type: ToastType.error);
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
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: const Color(0xFF07C160).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.verified_user_outlined,
              color: Color(0xFF07C160),
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              '网站误报申诉 / 申请加白',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
              // 申诉目标卡片
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
                    if (widget.domain != null && widget.domain!.isNotEmpty)
                      Row(
                        children: [
                          Icon(
                            Icons.language_rounded,
                            size: 13,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              widget.domain!,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 2),
                    Text(
                      widget.url,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '请选择申诉类型：',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),

              // 选项单选
              ...kDefaultAppealReasons.map((reason) {
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
                          width: 16,
                          height: 16,
                          margin: const EdgeInsets.only(top: 2, right: 8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF07C160)
                                  : (isDark ? Colors.white38 : Colors.black38),
                              width: isSelected ? 5.0 : 1.5,
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
                                  fontSize: 12.5,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                  color: isSelected
                                      ? (isDark ? Colors.white : const Color(0xFF1F2937))
                                      : (isDark ? Colors.white70 : Colors.black87),
                                ),
                              ),
                              Text(
                                reason.description,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: isDark ? Colors.white38 : Colors.black45,
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

              const SizedBox(height: 8),
              // 补充说明
              TextField(
                controller: _descController,
                maxLines: 2,
                maxLength: 200,
                decoration: InputDecoration(
                  hintText: '详细说明网站业务用途、误报原因（选填）',
                  hintStyle: const TextStyle(fontSize: 11),
                  filled: true,
                  fillColor: isDark ? Colors.white10 : const Color(0xFFF9FAFB),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: isDark ? Colors.white24 : const Color(0xFFE5E7EB),
                    ),
                  ),
                  contentPadding: const EdgeInsets.all(8),
                ),
                style: const TextStyle(fontSize: 11.5),
              ),
              const SizedBox(height: 4),
              // 联系人信息（选填）
              TextField(
                controller: _contactController,
                maxLength: 50,
                decoration: InputDecoration(
                  hintText: '联系邮箱 / 手机号 / ICP备案号（选填，便于审核回访）',
                  hintStyle: const TextStyle(fontSize: 11),
                  counterText: '',
                  filled: true,
                  fillColor: isDark ? Colors.white10 : const Color(0xFFF9FAFB),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: isDark ? Colors.white24 : const Color(0xFFE5E7EB),
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                style: const TextStyle(fontSize: 11.5),
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
            backgroundColor: const Color(0xFF07C160), // 信任绿
          ),
          onPressed: _isSubmitting ? null : _handleSubmit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('提交申诉', style: TextStyle(fontSize: 13)),
        ),
      ],
    );
  }
}
