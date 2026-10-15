import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../../../core/services/clipboard_service.dart';
import '../../chat/application/chat_controller.dart';
import '../../chat/data/repositories/message_repository.dart';

class ChatDiagnosticsPage extends ConsumerStatefulWidget {
  const ChatDiagnosticsPage({super.key});
  @override
  ConsumerState<ChatDiagnosticsPage> createState() =>
      _ChatDiagnosticsPageState();
}

class _ChatDiagnosticsPageState extends ConsumerState<ChatDiagnosticsPage> {
  final ownerId = TextEditingController(text: '1');
  final sessionUnitId = TextEditingController();
  final title = TextEditingController(text: '聊天诊断');
  final messageId = TextEditingController();
  bool _recalling = false;
  String _recallResult = '未执行';
  String? _recallStack;
  bool _syncingChanges = false;
  String _changesResult = '未执行增量同步';
  bool _deleting = false;
  String _deleteResult = '未执行单条删除';

  Future<void> _delete() async {
    final owner = int.tryParse(ownerId.text);
    final id = int.tryParse(messageId.text);
    final unit = sessionUnitId.text.trim();
    if (owner == null || owner <= 0 || id == null || id <= 0 || unit.isEmpty) {
      setState(
        () => _deleteResult = '请输入有效 Owner ID、SessionUnit ID、Message ID',
      );
      return;
    }
    setState(() {
      _deleting = true;
      _deleteResult = '执行中';
    });
    final watch = Stopwatch()..start();
    try {
      final repo = ref.read(messageRepositoryProvider);
      final original = await repo.findLocalByServerId(
        ownerId: owner,
        sessionUnitId: unit,
        serverId: id,
      );
      if (original == null) throw StateError('本地未找到消息，请先打开聊天加载目标消息');
      await repo.deleteRemote(original);
      await repo.loadChanges(ownerId: owner, sessionUnitId: unit);
      final remaining = await repo.findLocalByServerId(
        ownerId: owner,
        sessionUnitId: unit,
        serverId: id,
      );
      if (mounted) {
        setState(
          () =>
              _deleteResult =
                  '完成 · ${watch.elapsedMilliseconds} ms\nMessage ID: $id\n本地消息仍存在：${remaining != null}\n删除仅对当前身份生效；其他设备请执行增量同步验证。',
        );
      }
    } catch (error, stack) {
      if (mounted) {
        setState(
          () => _deleteResult = '失败：${error.runtimeType}\n$error\n$stack',
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _syncChanges() async {
    final owner = int.tryParse(ownerId.text);
    final unit = sessionUnitId.text.trim();
    if (owner == null || owner <= 0) {
      setState(() => _changesResult = '请输入有效 Owner ID');
      return;
    }
    setState(() {
      _syncingChanges = true;
      _changesResult = '同步中';
    });
    final watch = Stopwatch()..start();
    try {
      final repo = ref.read(messageRepositoryProvider);
      final before =
          unit.isEmpty ? null : await repo.changeSyncCursor(owner, unit);
      await repo.loadChanges(
        ownerId: owner,
        sessionUnitId: unit.isEmpty ? null : unit,
      );
      final after =
          unit.isEmpty ? null : await repo.changeSyncCursor(owner, unit);
      if (mounted) {
        setState(
          () =>
              _changesResult =
                  repo.isChangeSyncAvailable
                      ? '同步完成 · ${watch.elapsedMilliseconds} ms\n范围：${unit.isEmpty ? '当前身份本地缓存会话' : unit}\n原游标：$before\n新游标：$after\nSQLite、摘要及引用已按返回状态更新；再次执行可验证幂等。'
                      : '服务端尚未启用消息变更同步或接口未部署，现有消息恢复逻辑继续工作。',
        );
      }
    } catch (error, stack) {
      if (mounted) setState(() => _changesResult = '失败：$error\n$stack');
    } finally {
      if (mounted) setState(() => _syncingChanges = false);
    }
  }

  Future<void> _recall() async {
    final owner = int.tryParse(ownerId.text);
    final id = int.tryParse(messageId.text);
    final session = sessionUnitId.text.trim();
    if (owner == null ||
        owner <= 0 ||
        id == null ||
        id <= 0 ||
        session.isEmpty) {
      setState(
        () => _recallResult = '请输入有效的 Owner ID、SessionUnit ID 和 Message ID',
      );
      return;
    }
    setState(() {
      _recalling = true;
      _recallResult = '执行中';
      _recallStack = null;
    });
    final watch = Stopwatch()..start();
    try {
      final repository = ref.read(messageRepositoryProvider);
      final original = await repository.findLocalByServerId(
        ownerId: owner,
        sessionUnitId: session,
        serverId: id,
      );
      if (original == null) throw StateError('本地未找到消息，请先打开真实聊天窗口并加载目标消息。');
      final result = await repository.rollback(original);
      if (!mounted) return;
      setState(
        () =>
            _recallResult =
                '成功（服务端请求完成，本地已保存）\nMessage ID: ${result.serverId}\nisRollbacked: ${result.isRollbacked}\n耗时：${watch.elapsedMilliseconds} ms\n其他设备是否收到，请在对应设备检查。',
      );
    } catch (error, stack) {
      if (!mounted) return;
      setState(() {
        _recallResult =
            '失败：${error.runtimeType}\n$error\n耗时：${watch.elapsedMilliseconds} ms';
        _recallStack = '$stack';
      });
    } finally {
      if (mounted) setState(() => _recalling = false);
    }
  }

  final markdown = TextEditingController(
    text: '**Markdown 消息**\n\n- 引用、链接与 `code`\n- 支持多行文本',
  );

  @override
  void dispose() {
    ownerId.dispose();
    sessionUnitId.dispose();
    title.dispose();
    messageId.dispose();
    markdown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('聊天窗口诊断')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Text('使用真实 Repository、SQLite 和 HTTP 打开聊天窗口。支持移动端、平板、桌面和 Web。'),
        const SizedBox(height: 16),
        TextField(
          controller: ownerId,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Owner ID',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: sessionUnitId,
          decoration: const InputDecoration(
            labelText: 'SessionUnit ID',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: title,
          decoration: const InputDecoration(
            labelText: '标题',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: markdown,
          minLines: 4,
          maxLines: 10,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Markdown 文本消息输入',
            helperText: '输入会立即经过聊天页相同的 Markdown 渲染器',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('实际渲染结果'),
                const Divider(),
                MarkdownBody(data: markdown.text, selectable: true),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            final owner = int.tryParse(ownerId.text);
            final session = sessionUnitId.text.trim();
            if (owner == null || session.isEmpty) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('请输入有效参数')));
              return;
            }
            context.push(
              '/chat/${Uri.encodeComponent(session)}?ownerId=$owner&title=${Uri.encodeQueryComponent(title.text)}',
            );
          },
          child: const Text('执行：打开真实聊天窗口'),
        ),
        TextButton(
          onPressed:
              _recalling
                  ? null
                  : () => setState(() {
                    messageId.clear();
                    _recallResult = '未执行';
                    _recallStack = null;
                  }),
          child: const Text('恢复撤回诊断默认值'),
        ),
        const Divider(),
        const Text('持久化消息变更同步 · 全平台共用。会话为空时同步当前身份的本地缓存会话；首次自动校准，后续只拉增量。'),
        FilledButton(
          onPressed: _deleting ? null : _delete,
          child: Text(_deleting ? '删除中…' : '执行：仅对当前身份删除这条消息'),
        ),
        SelectableText(_deleteResult),
        TextButton(
          onPressed:
              () => ref.read(clipboardServiceProvider).copy(_deleteResult),
          child: const Text('复制删除诊断结果'),
        ),
        FilledButton(
          onPressed: _syncingChanges ? null : _syncChanges,
          child: Text(_syncingChanges ? '同步中…' : '执行消息变更同步'),
        ),
        SelectableText(_changesResult),
        TextButton(
          onPressed:
              () => ref.read(clipboardServiceProvider).copy(_changesResult),
          child: const Text('复制增量同步结果'),
        ),
        TextButton(
          onPressed:
              _syncingChanges
                  ? null
                  : () => setState(() => _changesResult = '未执行增量同步'),
          child: const Text('重置同步诊断结果'),
        ),
        const Text(
          '撤回同步诊断 · Android / iOS / 平板 / Windows / macOS / Linux / Web',
        ),
        const Text('使用上方身份和会话参数，以及已加载到本地的消息。执行按钮会真实撤回该消息；服务端权限和撤回时限仍会校验。'),
        TextField(
          controller: messageId,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '撤回 Message ID',
            border: OutlineInputBorder(),
          ),
        ),
        FilledButton(
          onPressed: _recalling ? null : _recall,
          child: Text(_recalling ? '正在撤回…' : '执行：撤回指定消息'),
        ),
        SelectableText(_recallResult),
        if (_recallStack != null)
          ExpansionTile(
            title: const Text('异常堆栈'),
            children: [SelectableText(_recallStack!)],
          ),
        TextButton(
          onPressed:
              () => ref
                  .read(clipboardServiceProvider)
                  .copy('$_recallResult\n${_recallStack ?? ''}'),
          child: const Text('复制撤回诊断结果'),
        ),
        TextButton(
          onPressed:
              () => setState(() {
                ownerId.text = '1';
                sessionUnitId.clear();
                title.text = '聊天诊断';
                markdown.text = '**Markdown 消息**\n\n- 引用、链接与 `code`\n- 支持多行文本';
              }),
          child: const Text('恢复默认'),
        ),
      ],
    ),
  );
}
