import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/utils/api_url_resolver.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../qr_code/data/models/qr_code_models.dart';
import '../../qr_code/data/qr_code_repository.dart';
import '../../session/application/session_list_controller.dart';
import '../../session/data/models/chat_owner.dart';

/// 桌面/弹窗版名片与群聊二维码展示对话框
class MyQrCodeDialog extends ConsumerStatefulWidget {
  const MyQrCodeDialog({
    required this.owner,
    this.isGroup = false,
    this.groupOwnerId,
    this.groupTitle,
    this.groupAvatar,
    this.inviterId,
    super.key,
  });

  final ChatOwner? owner;
  final bool isGroup;
  final int? groupOwnerId;
  final String? groupTitle;
  final String? groupAvatar;
  final int? inviterId;

  static Future<void> show(
    BuildContext context, {
    ChatOwner? owner,
    bool isGroup = false,
    int? groupOwnerId,
    String? groupTitle,
    String? groupAvatar,
    int? inviterId,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => MyQrCodeDialog(
        owner: owner,
        isGroup: isGroup,
        groupOwnerId: groupOwnerId,
        groupTitle: groupTitle,
        groupAvatar: groupAvatar,
        inviterId: inviterId,
      ),
    );
  }

  @override
  ConsumerState<MyQrCodeDialog> createState() => _MyQrCodeDialogState();
}

class _MyQrCodeDialogState extends ConsumerState<MyQrCodeDialog> {
  int? _selectedOwnerId;
  bool? _isPermanent;
  int? _expireDays;
  bool _loading = false;
  String? _error;
  QrCodeDetailModel? _detail;

  @override
  void initState() {
    super.initState();
    final sessionCtrl = ref.read(sessionListControllerProvider);
    _selectedOwnerId = widget.isGroup
        ? widget.groupOwnerId
        : (widget.owner?.id ?? sessionCtrl.currentOwnerId);
    _isPermanent = widget.isGroup ? false : true;
    _expireDays = widget.isGroup ? 7 : null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadQrCode());
  }

  Future<void> _loadQrCode({bool reset = false}) async {
    final targetOwnerId = _selectedOwnerId;
    if (targetOwnerId == null || targetOwnerId <= 0) {
      setState(() => _error = '未找到有效的聊天对象身份');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repo = ref.read(qrCodeRepositoryProvider);
      final inviterId = widget.isGroup
          ? (widget.inviterId ??
                ref.read(sessionListControllerProvider).currentOwnerId)
          : null;

      final detail = reset
          ? await repo.reset(
              ownerId: targetOwnerId,
              inviterId: inviterId,
              isPermanent: _isPermanent,
              expireDays: _expireDays,
            )
          : await repo.generate(
              ownerId: targetOwnerId,
              inviterId: inviterId,
              isPermanent: _isPermanent,
              expireDays: _expireDays,
            );
      if (!mounted) return;
      setState(() => _detail = detail);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '加载失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final sessionCtrl = ref.watch(sessionListControllerProvider);
    final owners = sessionCtrl.owners;
    final apiBaseUrl = ref.watch(appEnvironmentProvider).apiBaseUrl;

    ChatOwner? currentPersonalOwner = widget.owner;
    if (!widget.isGroup) {
      currentPersonalOwner = owners.cast<ChatOwner?>().firstWhere(
            (o) => o?.id == _selectedOwnerId,
            orElse: () => widget.owner ?? sessionCtrl.currentOwner,
          );
    }

    final name = widget.isGroup
        ? (_detail?.ownerName ?? widget.groupTitle ?? '群聊二维码')
        : (_detail?.ownerName ?? currentPersonalOwner?.name ?? 'Goto 用户');
    final rawAvatar = widget.isGroup
        ? (_detail?.ownerThumbnail ?? widget.groupAvatar)
        : (_detail?.ownerThumbnail ?? currentPersonalOwner?.imageUrl);
    final avatarUrl = rawAvatar != null && rawAvatar.isNotEmpty
        ? resolveApiUrl(rawAvatar, apiBaseUrl)
        : null;
    final qrData = _detail?.effectiveContent ?? '';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: colorScheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  AppAvatar(name: name, imageUrl: avatarUrl, radius: 26),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.isGroup
                              ? '群聊二维码'
                              : (currentPersonalOwner
                                            ?.typeDescription
                                            .isNotEmpty ==
                                        true
                                    ? currentPersonalOwner!.typeDescription
                                    : 'GotoIM 专属名片'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (!widget.isGroup && owners.length > 1) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: owners.map((o) {
                    return ChoiceChip(
                      label: Text(
                        o.typeDescription.isNotEmpty
                            ? '${o.name} (${o.typeDescription})'
                            : o.name,
                        style: const TextStyle(fontSize: 12),
                      ),
                      selected: o.id == _selectedOwnerId,
                      onSelected: _loading
                          ? null
                          : (_) {
                              setState(() => _selectedOwnerId = o.id);
                              _loadQrCode();
                            },
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                children: [
                  if (!widget.isGroup)
                    ChoiceChip(
                      label: const Text('永久', style: TextStyle(fontSize: 12)),
                      selected: _isPermanent == true && _expireDays == null,
                      onSelected: _loading
                          ? null
                          : (_) {
                              setState(() {
                                _isPermanent = true;
                                _expireDays = null;
                              });
                              _loadQrCode();
                            },
                    ),
                  ChoiceChip(
                    label: const Text('7天', style: TextStyle(fontSize: 12)),
                    selected: _isPermanent == false && _expireDays == 7,
                    onSelected: _loading
                        ? null
                        : (_) {
                            setState(() {
                              _isPermanent = false;
                              _expireDays = 7;
                            });
                            _loadQrCode();
                          },
                  ),
                  ChoiceChip(
                    label: const Text('30天', style: TextStyle(fontSize: 12)),
                    selected: _isPermanent == false && _expireDays == 30,
                    onSelected: _loading
                        ? null
                        : (_) {
                            setState(() {
                              _isPermanent = false;
                              _expireDays = 30;
                            });
                            _loadQrCode();
                          },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: 224,
                height: 224,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: _loading
                    ? const CircularProgressIndicator()
                    : _error != null
                    ? TextButton(
                        onPressed: () => _loadQrCode(),
                        child: Text('重试\n$_error', textAlign: TextAlign.center),
                      )
                    : qrData.isNotEmpty
                    ? QrImageView(
                        data: qrData,
                        version: QrVersions.auto,
                        size: 200,
                        backgroundColor: Colors.white,
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 12),
              Text(
                _detail?.isPermanent == true
                    ? '扫一扫加我好友 · 永久有效'
                    : '扫一扫${widget.isGroup ? '加入群聊' : '加我好友'} · ${_detail?.expireDays ?? _expireDays ?? 7}天内有效',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loading
                          ? null
                          : () => _loadQrCode(reset: true),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('重置'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: qrData.isEmpty
                          ? null
                          : () {
                              Clipboard.setData(ClipboardData(text: qrData));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('名片链接已复制到剪贴板')),
                              );
                            },
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('复制'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('完成'),
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
