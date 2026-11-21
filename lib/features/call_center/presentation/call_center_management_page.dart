import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/call_center_controller.dart';
import '../../session/application/session_list_controller.dart';

class CallCenterManagementPage extends ConsumerStatefulWidget {
  const CallCenterManagementPage({required this.shopKeeperId, super.key});

  final int shopKeeperId;

  @override
  ConsumerState<CallCenterManagementPage> createState() =>
      _CallCenterManagementPageState();
}

class _CallCenterManagementPageState
    extends ConsumerState<CallCenterManagementPage> {
  Map<String, dynamic>? configuration;
  Map<String, dynamic> counts = {};
  List<Map<String, dynamic>> agents = [];
  final Map<int, List<Map<String, dynamic>>> assignments = {0: [], 1: []};
  final Map<int, String?> nextAt = {0: null, 1: null};
  final Map<int, String?> nextId = {0: null, 1: null};
  bool busy = false;
  Object? error;
  int distribution = 1;
  int overflow = 2;
  int maxActive = 20;
  int timeout = 30;
  bool requireOnline = true;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final repository = ref.read(callCenterRepositoryProvider);
      final loaded = await repository.getConfiguration(widget.shopKeeperId);
      final active = await repository.getActiveCounts(widget.shopKeeperId);
      final staff = await repository.getAgents(widget.shopKeeperId);
      final assigned = await repository.getAssignments(
        shopKeeperId: widget.shopKeeperId,
        status: 1,
      );
      final queued = await repository.getAssignments(
        shopKeeperId: widget.shopKeeperId,
        status: 0,
      );
      if (!mounted) return;
      setState(() {
        configuration = loaded;
        counts = active;
        agents = staff;
        _setPage(1, assigned, reset: true);
        _setPage(0, queued, reset: true);
        distribution = (loaded['distributionStrategy'] as num?)?.toInt() ?? 1;
        overflow = (loaded['overflowStrategy'] as num?)?.toInt() ?? 2;
        maxActive = (loaded['maxActiveConversations'] as num?)?.toInt() ?? 20;
        timeout = (loaded['activeTimeoutMinutes'] as num?)?.toInt() ?? 30;
        requireOnline = loaded['requireOnline'] as bool? ?? true;
      });
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _setPage(int status, Map<String, dynamic> page, {required bool reset}) {
    final items =
        (page['items'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>();
    if (reset) assignments[status]!.clear();
    assignments[status]!.addAll(items);
    nextAt[status] = page['nextQueuedAt']?.toString();
    nextId[status] = page['nextId']?.toString();
  }

  Future<void> _loadMore(int status) async {
    if (busy || nextId[status] == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final page = await ref
          .read(callCenterRepositoryProvider)
          .getAssignments(
            shopKeeperId: widget.shopKeeperId,
            status: status,
            afterQueuedAt: nextAt[status],
            afterId: nextId[status],
          );
      if (mounted) setState(() => _setPage(status, page, reset: false));
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _cancelQueue(String sessionId) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref.read(callCenterRepositoryProvider).cancelQueue(sessionId);
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = e;
        });
      }
    }
  }

  Future<void> _transfer(String sessionId) async {
    final repository = ref.read(callCenterRepositoryProvider);
    try {
      final targets = await repository.loadTransferTargets(
        shopKeeperId: widget.shopKeeperId,
        keyword: '',
        skipCount: 0,
      );
      if (!mounted) return;
      final destination = await showModalBottomSheet<int>(
        context: context,
        builder:
            (context) => ListView(
              children: [
                const ListTile(title: Text('选择接待人')),
                for (final target in targets.items)
                  ListTile(
                    title: Text(target.name),
                    subtitle: Text(target.serviceStatusDescription),
                    onTap: () => Navigator.pop(context, target.id),
                  ),
              ],
            ),
      );
      if (destination == null) return;
      setState(() {
        busy = true;
        error = null;
      });
      await repository.transferAssignment(sessionId, destination);
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = e;
        });
      }
    }
  }

  Future<void> _save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(callCenterRepositoryProvider)
          .updateConfiguration(widget.shopKeeperId, {
            'distributionStrategy': distribution,
            'overflowStrategy': overflow,
            'maxActiveConversations': maxActive,
            'activeTimeoutMinutes': timeout,
            'requireOnline': requireOnline,
          });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('配置已保存')));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = e;
        });
      }
    }
  }

  Future<void> _drain() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final count = await ref
          .read(callCenterRepositoryProvider)
          .drainQueue(widget.shopKeeperId);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已分配 $count 个排队会话')));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = e;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentOwner = ref.watch(sessionListControllerProvider).currentOwner;
    if (currentOwner != null &&
        (currentOwner.id != widget.shopKeeperId ||
            currentOwner.objectType != 7)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
      return const Scaffold(body: SizedBox.shrink());
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('客服管理'),
        actions: [
          IconButton(
            onPressed: busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Text(
              '操作失败：$error',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (configuration != null) ...[
            Text('分配设置', style: Theme.of(context).textTheme.titleLarge),
            DropdownButtonFormField<int>(
              initialValue: distribution,
              decoration: const InputDecoration(labelText: '分配规则'),
              items: const [
                DropdownMenuItem(value: 0, child: Text('店长优先')),
                DropdownMenuItem(value: 1, child: Text('最少活跃接待量')),
                DropdownMenuItem(value: 2, child: Text('所有客服')),
              ],
              onChanged: busy ? null : (v) => setState(() => distribution = v!),
            ),
            DropdownButtonFormField<int>(
              initialValue: overflow,
              decoration: const InputDecoration(labelText: '满员处理'),
              items: const [
                DropdownMenuItem(value: 0, child: Text('排队等待')),
                DropdownMenuItem(value: 1, child: Text('分配给店长')),
                DropdownMenuItem(value: 2, child: Text('允许超额分配')),
              ],
              onChanged: busy ? null : (v) => setState(() => overflow = v!),
            ),
            TextFormField(
              initialValue: '$maxActive',
              decoration: const InputDecoration(labelText: '最大活跃接待量'),
              keyboardType: TextInputType.number,
              onChanged: (v) => maxActive = int.tryParse(v) ?? 0,
            ),
            TextFormField(
              initialValue: '$timeout',
              decoration: const InputDecoration(labelText: '活跃超时（分钟）'),
              keyboardType: TextInputType.number,
              onChanged: (v) => timeout = int.tryParse(v) ?? 0,
            ),
            SwitchListTile(
              title: const Text('仅分配在线客服'),
              value: requireOnline,
              onChanged: busy ? null : (v) => setState(() => requireOnline = v),
            ),
            FilledButton(
              onPressed: busy || maxActive < 1 || timeout < 1 ? null : _save,
              child: const Text('保存设置'),
            ),
            const SizedBox(height: 24),
            Text(
              '店员与活跃接待量（合计 ${counts.values.fold<int>(0, (sum, value) => sum + ((value as num?)?.toInt() ?? 0))}）',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final item in agents)
              ListTile(
                title: Text('${item['name']}'),
                subtitle: Text(
                  '状态：${switch (item['serviceStatus']) {
                    1 => '在线',
                    2 => '挂起',
                    3 => '隐身',
                    _ => '离线',
                  }}',
                ),
                trailing: Text('接待 ${item['activeCount'] ?? 0}'),
              ),
            for (final status in [1, 0]) ...[
              Text(
                status == 1 ? '接待中' : '排队中',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (final item in assignments[status]!)
                ListTile(
                  title: Text('客户 ${item['customerId']}'),
                  subtitle: Text('会话 ${item['sessionId']}'),
                  trailing: Text(
                    status == 1 ? '负责人 ${item['agentId'] ?? '-'}' : '等待中',
                  ),
                  onTap:
                      busy
                          ? null
                          : status == 0
                          ? () => _cancelQueue('${item['sessionId']}')
                          : () => _transfer('${item['sessionId']}'),
                ),
              if (nextId[status] != null)
                TextButton(
                  onPressed: busy ? null : () => _loadMore(status),
                  child: const Text('加载更多'),
                ),
            ],
            OutlinedButton(
              onPressed: busy ? null : _drain,
              child: const Text('调度等待队列'),
            ),
          ],
        ],
      ),
    );
  }
}
