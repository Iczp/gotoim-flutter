import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../search/data/search_repository.dart';
import '../../session/application/session_list_controller.dart';

class SearchAndGroupDiagnosticsPage extends ConsumerStatefulWidget {
  const SearchAndGroupDiagnosticsPage({super.key});

  @override
  ConsumerState<SearchAndGroupDiagnosticsPage> createState() =>
      _SearchAndGroupDiagnosticsPageState();
}

class _SearchAndGroupDiagnosticsPageState
    extends ConsumerState<SearchAndGroupDiagnosticsPage> {
  final _keywordController = TextEditingController(text: 'Goto');
  final _codeController = TextEditingController(text: '1234');
  final _groupNameController = TextEditingController(text: '测试诊断群');

  String _status = '未执行';
  String _output = '';
  int _elapsedMs = 0;
  bool _isRunning = false;

  void _resetDefaults() {
    setState(() {
      _keywordController.text = 'Goto';
      _codeController.text = '1234';
      _groupNameController.text = '测试诊断群';
      _status = '未执行';
      _output = '';
      _elapsedMs = 0;
    });
  }

  void _copyOutput() {
    Clipboard.setData(ClipboardData(text: _output));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制到剪贴板')),
    );
  }

  Future<void> _testSearchHistory() async {
    setState(() {
      _isRunning = true;
      _status = '执行中...';
      _output = '';
    });
    final sw = Stopwatch()..start();

    try {
      final repo = ref.read(searchRepositoryProvider);
      final initial = await repo.getSearchHistory();
      final afterAdd = await repo.addSearchHistory(_keywordController.text.trim());
      final afterDelete = await repo.deleteSearchHistory('__diagnostics_temp__');

      sw.stop();
      setState(() {
        _status = '成功';
        _elapsedMs = sw.elapsedMilliseconds;
        _output = const JsonEncoder.withIndent('  ').convert({
          'test': '搜索历史 CRUD',
          'initialHistory': initial,
          'afterAddKeyword': afterAdd,
          'afterDeleteTemp': afterDelete,
          'currentKeyword': _keywordController.text.trim(),
        });
      });
    } catch (e, st) {
      sw.stop();
      setState(() {
        _status = '失败';
        _elapsedMs = sw.elapsedMilliseconds;
        _output = '异常: $e\n$st';
      });
    } finally {
      setState(() => _isRunning = false);
    }
  }

  Future<void> _testLocalSearch() async {
    setState(() {
      _isRunning = true;
      _status = '执行中...';
      _output = '';
    });
    final sw = Stopwatch()..start();

    try {
      final repo = ref.read(searchRepositoryProvider);
      final sessionController = ref.read(sessionListControllerProvider);
      final ownerId = sessionController.currentOwner?.id ?? 0;
      final keyword = _keywordController.text.trim();

      final contacts = await repo.searchLocalContacts(
        ownerId: ownerId,
        keyword: keyword,
      );
      final messages = await repo.searchLocalMessages(
        ownerId: ownerId,
        keyword: keyword,
      );

      sw.stop();
      setState(() {
        _status = '成功';
        _elapsedMs = sw.elapsedMilliseconds;
        _output = const JsonEncoder.withIndent('  ').convert({
          'test': '本地离线检索 (Friends & Messages)',
          'ownerId': ownerId,
          'keyword': keyword,
          'localContactsCount': contacts.length,
          'localContacts': contacts.map((c) => {
            'id': c.id,
            'title': c.title,
            'subtitle': c.subtitle,
            'isRoom': c.isRoom,
          }).toList(),
          'localMessagesCount': messages.length,
          'localMessages': messages.map((m) => {
            'id': m.id,
            'sessionUnitId': m.sessionUnitId,
            'snippet': m.contentSnippet,
          }).toList(),
        });
      });
    } catch (e, st) {
      sw.stop();
      setState(() {
        _status = '失败';
        _elapsedMs = sw.elapsedMilliseconds;
        _output = '异常: $e\n$st';
      });
    } finally {
      setState(() => _isRunning = false);
    }
  }

  Future<void> _testCreateGroupPayload() async {
    setState(() {
      _isRunning = true;
      _status = '执行中...';
      _output = '';
    });
    final sw = Stopwatch()..start();

    try {
      final sessionController = ref.read(sessionListControllerProvider);
      final ownerId = sessionController.currentOwner?.id ?? 0;
      final code = _codeController.text.trim();
      final name = _groupNameController.text.trim();

      final payload = {
        'url': '/api/chat/room',
        'method': 'POST',
        'body': {
          'name': name,
          'code': code,
          'ownerId': ownerId,
          'type': 0,
          'description': '面对面建群(码:$code)',
          'chatObjectIdList': <int>[],
        },
      };

      sw.stop();
      setState(() {
        _status = '成功 (参数组装验证)';
        _elapsedMs = sw.elapsedMilliseconds;
        _output = const JsonEncoder.withIndent('  ').convert({
          'test': '面对面建群接口参数组装',
          'requestPayload': payload,
          'ownerAvailable': ownerId > 0,
        });
      });
    } catch (e, st) {
      sw.stop();
      setState(() {
        _status = '失败';
        _elapsedMs = sw.elapsedMilliseconds;
        _output = '异常: $e\n$st';
      });
    } finally {
      setState(() => _isRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('全局搜索与群聊诊断'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '恢复默认',
            onPressed: _resetDefaults,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 功能介绍与平台支持
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '功能说明',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '验证搜索历史 SQLite 持久化、本地联系人/聊天记录秒级检索、面对面建群/好友建群接口组装。',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      _platformChip('Android ✓'),
                      _platformChip('iOS ✓'),
                      _platformChip('Windows ✓'),
                      _platformChip('macOS ✓'),
                      _platformChip('Linux ✓'),
                      _platformChip('Web ✓'),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 参数输入
          Text('输入参数', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _keywordController,
            decoration: const InputDecoration(
              labelText: '搜索关键词',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 4,
            decoration: const InputDecoration(
              labelText: '进群码 (4位数字)',
              counterText: '',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _groupNameController,
            decoration: const InputDecoration(
              labelText: '群名称',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),

          const SizedBox(height: 16),

          // 操作按钮组
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: _isRunning ? null : _testSearchHistory,
                child: const Text('测试搜索历史'),
              ),
              FilledButton.tonal(
                onPressed: _isRunning ? null : _testLocalSearch,
                child: const Text('测试本地检索'),
              ),
              FilledButton.tonal(
                onPressed: _isRunning ? null : _testCreateGroupPayload,
                child: const Text('验证建群参数'),
              ),
              OutlinedButton(
                onPressed: () => context.push('/search'),
                child: const Text('打开搜索页'),
              ),
              OutlinedButton(
                onPressed: () => context.push('/create-group'),
                child: const Text('打开建群页'),
              ),
              OutlinedButton(
                onPressed: () => context.push('/add-friend'),
                child: const Text('打开加好友页'),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 执行状态与耗时
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text('状态: ', style: theme.textTheme.bodyMedium),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _status.contains('成功')
                          ? Colors.green.withValues(alpha: 0.2)
                          : _status.contains('失败')
                              ? Colors.red.withValues(alpha: 0.2)
                              : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _status,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _status.contains('成功')
                            ? Colors.green.shade700
                            : _status.contains('失败')
                                ? Colors.red.shade700
                                : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              if (_elapsedMs > 0)
                Text(
                  '耗时: $_elapsedMs ms',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),

          const SizedBox(height: 12),

          // 结果输出展示
          if (_output.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('返回结果', style: theme.textTheme.titleSmall),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  tooltip: '复制结果',
                  onPressed: _copyOutput,
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _output,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _platformChip(String label) {
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
