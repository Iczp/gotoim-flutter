import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/scan/unified_scan_dispatcher.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_toast.dart';
import '../../session/application/session_list_controller.dart';
import '../data/contact_api.dart';

class AddFriendPage extends ConsumerStatefulWidget {
  const AddFriendPage({this.initialKeyword, super.key});

  final String? initialKeyword;

  @override
  ConsumerState<AddFriendPage> createState() => _AddFriendPageState();
}

class _AddFriendPageState extends ConsumerState<AddFriendPage> {
  late final TextEditingController _searchController;
  bool _isLoading = false;
  List<Map<String, dynamic>> _searchResults = [];
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialKeyword ?? '');
    if (widget.initialKeyword != null && widget.initialKeyword!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _doSearch(widget.initialKeyword!);
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _doSearch(String keyword) async {
    final term = keyword.trim();
    if (term.isEmpty) {
      setState(() {
        _searchResults = [];
        _searched = false;
      });
      return;
    }

    final sessionController = ref.read(sessionListControllerProvider);
    final ownerId = sessionController.currentOwner?.id;
    if (ownerId == null) {
      showToast('当前未获取到有效身份', type: ToastType.warning);
      return;
    }

    setState(() {
      _isLoading = true;
      _searched = true;
    });

    try {
      final res = await ref.read(contactApiProvider).searchChatObjects(
        keyword: term,
        isEnabledParentId: false,
        maxResultCount: 20,
      );

      final items = res['items'];
      if (items is List) {
        setState(() {
          _searchResults = items.whereType<Map<String, dynamic>>().toList();
        });
      } else {
        setState(() => _searchResults = []);
      }
    } catch (e) {
      showToast('搜索失败: $e', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendFriendRequest(Map<String, dynamic> item) async {
    final sessionController = ref.read(sessionListControllerProvider);
    final ownerId = sessionController.currentOwner?.id;
    if (ownerId == null) return;

    final dest = item['destination'];
    final destId = (dest is Map ? dest['id'] : item['destinationId'] ?? item['id']) as num?;
    if (destId == null) {
      showToast('无效的目标聊天对象', type: ToastType.warning);
      return;
    }

    final messageController = TextEditingController(text: '你好，我是${sessionController.currentOwner?.name ?? 'IM用户'}');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('发送好友申请'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('请输入申请附言：'),
              const SizedBox(height: 8),
              TextField(
                controller: messageController,
                maxLength: 50,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '写点什么介绍自己吧',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('发送'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    try {
      showToast('正在发送申请...', type: ToastType.info);
      await ref.read(contactApiProvider).createSessionRequest(
        ownerId: ownerId,
        destinationId: destId.toInt(),
        requestMessage: messageController.text.trim(),
      );
      showToast('好友申请已发送', type: ToastType.success);
    } catch (e) {
      showToast('发送申请失败: $e', type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentOwner = ref.watch(sessionListControllerProvider).currentOwner;

    return Scaffold(
      appBar: AppBar(
        title: const Text('添加好友'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          // 搜索框
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: _doSearch,
              decoration: InputDecoration(
                hintText: '输入账号、用户名或手机号',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.cancel_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _doSearch('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),

          // 快速入口卡片
          if (!_searched) ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Column(
                  children: [
                    Text(
                      '我的账号: ${currentOwner?.name ?? '-'}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '聊天身份ID: ${currentOwner?.id ?? '-'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              child: ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.qr_code_scanner_rounded,
                    color: colorScheme.primary,
                  ),
                ),
                title: const Text('扫一扫加好友'),
                subtitle: const Text(
                  '扫描对方的 Goto IM 二维码名片',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  ref.read(unifiedScanDispatcherProvider).openAndDispatch(context, ref);
                },
              ),
            ),
          ],

          // 搜索结果
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_searched && _searchResults.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.person_search_rounded,
                      size: 56,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '该用户不存在或未找到匹配结果',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          else if (_searchResults.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '搜索结果 (${_searchResults.length})',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final item in _searchResults)
              _buildSearchResultTile(context, item),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchResultTile(BuildContext context, Map<String, dynamic> item) {
    final dest = item['destination'];
    final name = (dest is Map
            ? (dest['name'] ?? dest['displayName'])
            : (item['displayName'] ?? item['name']))
        ?.toString() ??
        '-';
    final avatar = (dest is Map
            ? (dest['portraitUrl'] ?? dest['thumbnail'] ?? dest['avatar'])
            : (item['portrait'] ?? item['thumbnail'] ?? item['portraitUrl'] ?? item['avatar']))
        ?.toString();
    final isFriend = item['isFriendship'] == true;
    final objectTypeDesc = (dest is Map ? dest['objectTypeDescription'] : item['objectTypeDescription'])?.toString();
    final code = (dest is Map ? dest['code'] : item['code'])?.toString();
    final unitId = item['sessionUnitId']?.toString() ?? item['id']?.toString() ?? '';

    String? subtitleText = objectTypeDesc;
    if (code != null && code.isNotEmpty && code != name) {
      subtitleText = subtitleText != null ? '$subtitleText · 编码: $code' : '编码: $code';
    }

    return ListTile(
      leading: AppAvatar(name: name, imageUrl: avatar, radius: 22),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        subtitleText ?? 'Goto IM 用户',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: isFriend
          ? OutlinedButton(
              onPressed: () {
                context.push(
                  '/chat?sessionUnitId=$unitId&title=${Uri.encodeComponent(name)}',
                );
              },
              child: const Text('发消息'),
            )
          : FilledButton(
              onPressed: () => _sendFriendRequest(item),
              child: const Text('添加'),
            ),
    );
  }
}
