import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/utils/api_url_resolver.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/two_line_app_bar_title.dart';
import '../../contact/data/contact_api.dart';
import '../../contact/data/models/session_request_models.dart';
import '../../contact/presentation/session_request_detail_sheet.dart';
import '../../session/presentation/chat_object_avatar.dart';

class RoomJoinRequestsPage extends ConsumerStatefulWidget {
  const RoomJoinRequestsPage({
    required this.destinationId,
    required this.handlerSessionUnitId,
    this.sessionTitle,
    this.isDialog = false,
    super.key,
  });

  final int destinationId;
  final String handlerSessionUnitId;
  final String? sessionTitle;
  final bool isDialog;

  @override
  ConsumerState<RoomJoinRequestsPage> createState() =>
      _RoomJoinRequestsPageState();
}

class _RoomJoinRequestsPageState extends ConsumerState<RoomJoinRequestsPage> {
  bool? _filterIsHandled = false;
  bool _loading = true;
  String? _actingId;
  Object? _error;
  List<SessionRequestItem> _items = const <SessionRequestItem>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await ref
          .read(contactApiProvider)
          .listSessionRequests(
            destinationId: widget.destinationId,
            isHandled: _filterIsHandled,
            maxResultCount: 50,
          );
      final rawItems = raw['items'];
      final parsed =
          rawItems is List
              ? rawItems
                  .whereType<Map>()
                  .map(
                    (e) => SessionRequestItem.fromJson(
                      Map<String, dynamic>.from(e),
                    ),
                  )
                  .toList(growable: false)
              : const <SessionRequestItem>[];
      if (!mounted) return;
      setState(() {
        _items = parsed;
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

  Future<void> _handle(SessionRequestItem item, bool isAgreed) async {
    if (_actingId != null) return;
    setState(() => _actingId = item.id);
    try {
      await ref
          .read(contactApiProvider)
          .handleSessionRequest(
            sessionRequestId: item.id,
            isAgreed: isAgreed,
            handlerSessionUnitId: widget.handlerSessionUnitId,
          );
      if (!mounted) return;
      showToast(isAgreed ? '已同意入群申请' : '已拒绝入群申请', type: ToastType.success);
      await _load();
    } catch (e) {
      if (!mounted) return;
      showToast('处理失败：$e', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() => _actingId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: <Widget>[
              ChoiceChip(
                label: const Text('待处理'),
                selected: _filterIsHandled == false,
                onSelected: (_) {
                  if (_filterIsHandled == false) return;
                  setState(() => _filterIsHandled = false);
                  _load();
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('已处理'),
                selected: _filterIsHandled == true,
                onSelected: (_) {
                  if (_filterIsHandled == true) return;
                  setState(() => _filterIsHandled = true);
                  _load();
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('全部'),
                selected: _filterIsHandled == null,
                onSelected: (_) {
                  if (_filterIsHandled == null) return;
                  setState(() => _filterIsHandled = null);
                  _load();
                },
              ),
              const Spacer(),
              IconButton(
                tooltip: '刷新',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded, size: 20),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _buildBody(context)),
      ],
    );

    if (widget.isDialog) {
      return content;
    }

    return Scaffold(
      backgroundColor: WeChatPageStyle.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: WeChatPageStyle.appBarBg(context),
        scrolledUnderElevation: 0.5,
        title: TwoLineAppBarTitle(
          title: '入群申请',
          subtitle: widget.sessionTitle,
        ),
      ),
      body: content,
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '加载失败：$_error',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(child: Text('暂无入群申请'));
    }

    final apiBaseUrl = ref.watch(appEnvironmentProvider).apiBaseUrl;
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = _items[index];
        final owner = item.owner;
        final avatarUrl =
            owner?.avatar != null
                ? resolveApiUrl(owner!.avatar!, apiBaseUrl)
                : null;
        final canHandle = !item.isHandled && !item.isExpired;
        final isBusy = _actingId == item.id;

        return ListTile(
          onTap:
              () => showSessionRequestDetailModal(
                context,
                requestId: item.id,
                handlerSessionUnitId: widget.handlerSessionUnitId,
                onHandled: _load,
              ),
          leading: ChatObjectAvatar(
            name: owner?.name ?? '申请人',
            imageUrl: avatarUrl,
            size: 42,
            chatObjectId: owner?.id,
          ),
          title: Text(
            owner?.name.isNotEmpty == true
                ? owner!.name
                : '用户 #${item.ownerId}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            item.requestMessage.isNotEmpty
                ? item.requestMessage
                : '请求加入群聊',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing:
              canHandle
                  ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TextButton(
                        onPressed:
                            isBusy ? null : () => _handle(item, false),
                        child: const Text('拒绝'),
                      ),
                      const SizedBox(width: 4),
                      FilledButton(
                        onPressed:
                            isBusy ? null : () => _handle(item, true),
                        child: const Text('同意'),
                      ),
                    ],
                  )
                  : Text(
                    item.isExpired
                        ? '已过期'
                        : (item.isAgreed == true ? '已同意' : '已拒绝'),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color:
                          item.isExpired
                              ? Theme.of(context).colorScheme.outline
                              : (item.isAgreed == true
                                  ? Colors.green
                                  : Theme.of(context).colorScheme.error),
                    ),
                  ),
        );
      },
    );
  }
}
