import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/utils/api_url_resolver.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/desktop_dialog.dart';
import '../../session/presentation/chat_object_avatar.dart';
import '../data/contact_api.dart';
import '../data/models/session_request_models.dart';

Future<void> showSessionRequestDetailModal(
  BuildContext context, {
  required String requestId,
  String? handlerSessionUnitId,
  VoidCallback? onHandled,
}) {
  final isDesktop = MediaQuery.sizeOf(context).width >= 720;
  if (isDesktop) {
    return showDesktopModalDialog<void>(
      context: context,
      title: '验证申请详情',
      width: 480,
      child: _SessionRequestDetailBody(
        requestId: requestId,
        handlerSessionUnitId: handlerSessionUnitId,
        onHandled: onHandled,
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              '验证申请详情',
              style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _SessionRequestDetailBody(
              requestId: requestId,
              handlerSessionUnitId: handlerSessionUnitId,
              onHandled: onHandled,
            ),
          ],
        ),
      ),
    ),
  );
}

class _SessionRequestDetailBody extends ConsumerStatefulWidget {
  const _SessionRequestDetailBody({
    required this.requestId,
    this.handlerSessionUnitId,
    this.onHandled,
  });

  final String requestId;
  final String? handlerSessionUnitId;
  final VoidCallback? onHandled;

  @override
  ConsumerState<_SessionRequestDetailBody> createState() =>
      _SessionRequestDetailBodyState();
}

class _SessionRequestDetailBodyState
    extends ConsumerState<_SessionRequestDetailBody> {
  final TextEditingController _handleMessageController = TextEditingController();
  SessionRequestItem? _detail;
  bool _loading = true;
  bool _submitting = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _handleMessageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await ref
          .read(contactApiProvider)
          .getSessionRequestDetail(widget.requestId);
      if (!mounted) return;
      setState(() {
        _detail = SessionRequestItem.fromJson(raw);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _handle(bool isAgreed) async {
    final detail = _detail;
    if (detail == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      final updatedRaw = await ref
          .read(contactApiProvider)
          .handleSessionRequest(
            sessionRequestId: detail.id,
            isAgreed: isAgreed,
            handleMessage: _handleMessageController.text.trim(),
            handlerSessionUnitId: widget.handlerSessionUnitId,
          );
      if (!mounted) return;
      setState(() {
        _detail = SessionRequestItem.fromJson(updatedRaw);
        _submitting = false;
      });
      showToast(
        isAgreed ? '已同意申请' : '已拒绝申请',
        type: ToastType.success,
      );
      widget.onHandled?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showToast('处理失败：$e', type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '加载申请详情失败：$_error',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }

    final detail = _detail;
    if (detail == null) {
      return const SizedBox.shrink();
    }

    final apiBaseUrl = ref.watch(appEnvironmentProvider).apiBaseUrl;
    final owner = detail.owner;
    final destination = detail.destination;
    final ownerAvatar =
        owner?.avatar != null
            ? resolveApiUrl(owner!.avatar!, apiBaseUrl)
            : null;
    final destAvatar =
        destination?.avatar != null
            ? resolveApiUrl(destination!.avatar!, apiBaseUrl)
            : null;
    final isRoom = destination?.objectType == 2 || destination?.objectType == 5;
    final canHandle = !detail.isHandled && !detail.isExpired;

    final (statusText, statusColor) = _statusPresentation(context, detail);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            ChatObjectAvatar(
              name: owner?.name ?? '申请人',
              imageUrl: ownerAvatar,
              size: 46,
              chatObjectId: owner?.id,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    owner?.name.isNotEmpty == true
                        ? owner!.name
                        : '用户 #${detail.ownerId}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (owner?.code != null && owner!.code!.isNotEmpty)
                    Text(
                      '账号: ${owner.code}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                statusText,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    isRoom ? '申请加入群聊' : '目标对象',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (destAvatar != null) ...<Widget>[
                    ChatObjectAvatar(
                      name: destination?.name ?? '',
                      imageUrl: destAvatar,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      destination?.name.isNotEmpty == true
                          ? destination!.name
                          : '#${detail.destinationId}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '验证消息：${detail.requestMessage.isNotEmpty ? detail.requestMessage : '（无验证消息）'}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (detail.handleMessage.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  '审批备注：${detail.handleMessage}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (canHandle) ...<Widget>[
          const SizedBox(height: 14),
          TextField(
            controller: _handleMessageController,
            enabled: !_submitting,
            maxLines: 2,
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: '审批备注（可选）',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: _submitting ? null : () => _handle(false),
                  child: const Text('拒绝'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _submitting ? null : () => _handle(true),
                  child: const Text('同意'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  (String, Color) _statusPresentation(
    BuildContext context,
    SessionRequestItem detail,
  ) {
    final scheme = Theme.of(context).colorScheme;
    if (detail.isExpired) {
      return ('已过期', scheme.outline);
    }
    if (!detail.isHandled) {
      return ('待处理', Colors.orange);
    }
    if (detail.isAgreed == true) {
      return ('已同意', Colors.green);
    }
    return ('已拒绝', scheme.error);
  }
}
