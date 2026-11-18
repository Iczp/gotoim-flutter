import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/utils/api_url_resolver.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_toast.dart';
import '../../session/application/session_list_controller.dart';
import '../../session/data/models/chat_owner.dart';
import '../data/models/qr_code_models.dart';
import '../data/qr_code_repository.dart';

/// 微信风格二维码名片 / 群邀请识别弹窗
class QrCodeCardModal extends ConsumerStatefulWidget {
  const QrCodeCardModal({
    required this.initialData,
    this.rawContent,
    super.key,
  });

  final QrCodeScanDataModel initialData;
  final String? rawContent;

  static Future<void> show(
    BuildContext context, {
    required QrCodeScanDataModel data,
    String? rawContent,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => QrCodeCardModal(
        initialData: data,
        rawContent: rawContent,
      ),
    );
  }

  @override
  ConsumerState<QrCodeCardModal> createState() => _QrCodeCardModalState();
}

class _QrCodeCardModalState extends ConsumerState<QrCodeCardModal> {
  late QrCodeScanDataModel _data;
  int? _selectedApplicantId;
  bool _loadingIdentity = false;
  bool _submitting = false;
  final TextEditingController _msgController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _data = widget.initialData;
    final sessionCtrl = ref.read(sessionListControllerProvider);
    _selectedApplicantId =
        _data.viewerChatObjectId ?? sessionCtrl.currentOwnerId;
  }

  @override
  void dispose() {
    _msgController.dispose();
    super.dispose();
  }

  Future<void> _switchApplicantIdentity(int ownerId) async {
    if (_selectedApplicantId == ownerId || _loadingIdentity) return;
    setState(() {
      _selectedApplicantId = ownerId;
      _loadingIdentity = true;
    });
    try {
      final repo = ref.read(qrCodeRepositoryProvider);
      QrCodeScanDataModel? refreshed;
      if (widget.rawContent != null && widget.rawContent!.isNotEmpty) {
        refreshed = await repo.resolve(
          widget.rawContent!,
          currentChatObjectId: ownerId,
        );
      } else if (_data.code.isNotEmpty) {
        refreshed = await repo.getByCode(
          _data.code,
          currentChatObjectId: ownerId,
        );
      }
      if (refreshed != null && mounted) {
        setState(() => _data = refreshed!);
      }
    } catch (_) {
      // 保留原预览数据
    } finally {
      if (mounted) setState(() => _loadingIdentity = false);
    }
  }

  Future<void> _handleApply() async {
    if (_submitting || !_data.isValid) return;
    setState(() => _submitting = true);
    try {
      final repo = ref.read(qrCodeRepositoryProvider);
      final targetCode =
          _data.code.isNotEmpty ? _data.code : (widget.rawContent ?? '');
      final res = await repo.apply(
        code: targetCode,
        applicantChatObjectId: _selectedApplicantId,
        requestMessage: _msgController.text.trim(),
      );
      if (!mounted) return;

      final status = res.status;
      if (status == 'joined' ||
          status == 'added' ||
          status == 'already_member' ||
          status == 'already_friend') {
        showToast(
          res.message ?? (status == 'joined' ? '已加入群聊' : '已添加好友'),
          type: ToastType.success,
        );
        Navigator.of(context).pop();
        if (res.sessionUnitId != null && res.sessionUnitId!.isNotEmpty) {
          context.push('/chat/${res.sessionUnitId}');
        }
      } else if (status == 'request_sent') {
        showToast(
          res.message ?? '已发送验证申请，请等待对方通过',
          type: ToastType.success,
        );
        Navigator.of(context).pop();
      } else {
        showToast(res.message ?? '操作完成', type: ToastType.info);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      showToast('操作失败：$e', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _enterExistingSession() {
    final unitId = _data.sessionUnitId;
    Navigator.of(context).pop();
    if (unitId != null && unitId.isNotEmpty) {
      context.push('/chat/$unitId');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final apiBaseUrl = ref.watch(appEnvironmentProvider).apiBaseUrl;
    final owners = ref.watch(sessionListControllerProvider).owners;

    final rawAvatar = _data.ownerThumbnail?.isNotEmpty == true
        ? _data.ownerThumbnail
        : _data.ownerPortrait;
    final avatarUrl = rawAvatar != null && rawAvatar.isNotEmpty
        ? resolveApiUrl(rawAvatar, apiBaseUrl)
        : null;

    final displayName = _data.ownerName?.isNotEmpty == true
        ? _data.ownerName!
        : (_data.isGroup ? '群聊名片' : 'GotoIM 名片');

    final typeLabel = _data.ownerObjectTypeDescription?.isNotEmpty == true
        ? _data.ownerObjectTypeDescription!
        : (_data.isGroup ? '群聊' : '个人名片');

    final canEnterSession =
        (_data.isAlreadyMember || _data.isFriend) &&
        _data.sessionUnitId != null &&
        _data.sessionUnitId!.isNotEmpty;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 头部头像与名片信息
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppAvatar(
                    name: displayName,
                    imageUrl: avatarUrl,
                    radius: 28,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                displayName,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                typeLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (_data.ownerCode != null &&
                            _data.ownerCode!.isNotEmpty)
                          Text(
                            '账号：${_data.ownerCode}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        if (_data.isGroup && _data.memberCount != null)
                          Text(
                            '群成员：${_data.memberCount} 人'
                            '${_data.inviterName != null ? ' · 邀请人：${_data.inviterName}' : ''}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_data.description != null &&
                  _data.description!.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.45,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _data.description!.trim(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              if (!_data.isValid) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 18,
                        color: colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _data.invalidReason ??
                              (_data.isExpired
                                  ? '该二维码已过期'
                                  : '该二维码已失效或被停用'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // 多 ChatObjectId 身份选择器
              if (_data.isValid && owners.length > 1) ...[
                const SizedBox(height: 14),
                Text(
                  '使用身份',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: owners.map((ChatOwner o) {
                    final selected = o.id == _selectedApplicantId;
                    return ChoiceChip(
                      label: Text(
                        o.typeDescription.isNotEmpty
                            ? '${o.name} (${o.typeDescription})'
                            : o.name,
                        style: const TextStyle(fontSize: 12),
                      ),
                      selected: selected,
                      onSelected: _loadingIdentity
                          ? null
                          : (_) => _switchApplicantIdentity(o.id),
                    );
                  }).toList(),
                ),
              ],
              // 需要验证时展示验证附言输入框
              if (_data.isValid &&
                  !_data.isSelf &&
                  !canEnterSession &&
                  _data.needsApproval) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: _msgController,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: '验证信息',
                    hintText: '输入打招呼或验证理由（可选）',
                    border: OutlineInputBorder(),
                    isDense: true,
                    counterText: '',
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('关闭'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: _buildPrimaryAction(canEnterSession),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrimaryAction(bool canEnterSession) {
    if (!_data.isValid) {
      return FilledButton(
        onPressed: null,
        child: Text(_data.isExpired ? '已过期' : '已失效'),
      );
    }
    if (_data.isSelf) {
      return FilledButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('这是你自己的名片'),
      );
    }
    if (canEnterSession) {
      return FilledButton.icon(
        onPressed: _enterExistingSession,
        icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
        label: const Text('发消息'),
      );
    }
    final actionLabel = _data.isGroup
        ? (_data.needsApproval ? '申请加入群聊' : '加入群聊')
        : (_data.needsApproval ? '发送好友申请' : '添加到通讯录');

    return FilledButton(
      onPressed: (_submitting || _loadingIdentity) ? null : _handleApply,
      child: _submitting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(actionLabel),
    );
  }
}
