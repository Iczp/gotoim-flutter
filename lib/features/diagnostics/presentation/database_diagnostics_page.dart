import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/application_providers.dart';
import '../../../core/database/unified_database.dart';

class DatabaseDiagnosticsPage extends ConsumerStatefulWidget {
  const DatabaseDiagnosticsPage({super.key});

  @override
  ConsumerState<DatabaseDiagnosticsPage> createState() =>
      _DatabaseDiagnosticsPageState();
}

class _DatabaseDiagnosticsPageState
    extends ConsumerState<DatabaseDiagnosticsPage> {
  String _result = '尚未调用。';
  String? _lastRecordId;
  bool _working = false;

  // 消息查询输入
  final _sessionUnitIdCtrl = TextEditingController(
    text: 'b51b5df6-33f4-e1ec-94ff-3a0aab12edf9',
  );
  final _ownerIdCtrl = TextEditingController(text: '');
  final _limitCtrl = TextEditingController(text: '10');

  UnifiedDatabase get _database => ref.read(unifiedDatabaseProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _inspect());
  }

  @override
  void dispose() {
    _sessionUnitIdCtrl.dispose();
    _ownerIdCtrl.dispose();
    _limitCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<Object?> Function() action) async {
    setState(() => _working = true);
    try {
      final value = await action();
      if (mounted) setState(() => _result = _pretty(value));
    } catch (error, stackTrace) {
      if (mounted) {
        setState(
          () =>
              _result = _pretty(<String, Object?>{
                'success': false,
                'error': error.toString(),
                'stack': stackTrace.toString(),
              }),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _inspect() =>
      _run(() async => (await _database.inspect()).toJson());

  Future<void> _insert() => _run(() async {
    final id = 'diagnostic-${DateTime.now().microsecondsSinceEpoch}';
    await _database.insertDiagnosticRecord(
      id: id,
      title: '开发诊断样本',
      payload: <String, Object?>{
        'platform': defaultTargetPlatform.name,
        'createdBy': 'database_diagnostics',
      },
    );
    _lastRecordId = id;
    return <String, Object?>{
      'operation': 'insert',
      'id': id,
      'records':
          (await _database.readDiagnosticRecords())
              .map((record) => record.toJson())
              .toList(),
    };
  });

  Future<void> _read() => _run(
    () async => <String, Object?>{
      'operation': 'select',
      'records':
          (await _database.readDiagnosticRecords())
              .map((record) => record.toJson())
              .toList(),
    },
  );

  Future<void> _update() => _run(() async {
    final id = _lastRecordId;
    if (id == null) throw StateError('请先插入一条诊断记录。');
    final affected = await _database.updateDiagnosticRecord(
      id: id,
      title: '开发诊断样本（已更新）',
      payload: <String, Object?>{
        'updatedBy': 'database_diagnostics',
        'updatedAt': DateTime.now().toIso8601String(),
      },
    );
    return <String, Object?>{
      'operation': 'update',
      'id': id,
      'affected': affected,
    };
  });

  Future<void> _delete() => _run(() async {
    final id = _lastRecordId;
    if (id == null) throw StateError('请先插入一条诊断记录。');
    final affected = await _database.deleteDiagnosticRecord(id);
    _lastRecordId = null;
    return <String, Object?>{
      'operation': 'delete',
      'id': id,
      'affected': affected,
    };
  });

  Future<void> _clear() => _run(() async {
    final affected = await _database.clearTable(
      UnifiedDatabase.diagnosticsTable,
    );
    _lastRecordId = null;
    return <String, Object?>{
      'operation': 'clearTable',
      'table': UnifiedDatabase.diagnosticsTable,
      'affected': affected,
    };
  });

  Future<void> _createScratch() => _run(() async {
    await _database.createDiagnosticsScratchTable();
    return <String, Object?>{
      'operation': 'createTable',
      'table': UnifiedDatabase.diagnosticsScratchTable,
      'overview': (await _database.inspect()).toJson(),
    };
  });

  Future<void> _dropScratch() => _run(() async {
    await _database.dropDiagnosticsScratchTable();
    return <String, Object?>{
      'operation': 'dropTable',
      'table': UnifiedDatabase.diagnosticsScratchTable,
      'overview': (await _database.inspect()).toJson(),
    };
  });

  // ── 消息查询 ──────────────────────────────────────────────────────────────

  Future<void> _queryMessageStats() => _run(() async {
    final sessionUnitId = _sessionUnitIdCtrl.text.trim();
    if (sessionUnitId.isEmpty) throw ArgumentError('请填写 SessionUnit ID');
    final stats = await _database.queryMessageStatsBySession(sessionUnitId);
    final loadedAll = await _database.readFriendMessagesLoadedAll(sessionUnitId);
    return <String, Object?>{
      'operation': 'message_stats',
      'sessionUnitId': sessionUnitId,
      'loadedAll': loadedAll,
      'groups': stats,
    };
  });

  Future<void> _queryMessageList() => _run(() async {
    final sessionUnitId = _sessionUnitIdCtrl.text.trim();
    final limit = int.tryParse(_limitCtrl.text.trim()) ?? 10;
    if (sessionUnitId.isEmpty) throw ArgumentError('请填写 SessionUnit ID');

    final ownerIdText = _ownerIdCtrl.text.trim();
    if (ownerIdText.isNotEmpty) {
      final ownerId = int.parse(ownerIdText);
      final rows = await _database.readMessageRows(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
        limit: limit,
      );
      return <String, Object?>{
        'operation': 'SELECT messages (with ownerId)',
        'sessionUnitId': sessionUnitId,
        'ownerId': ownerId,
        'limit': limit,
        'returned': rows.length,
        'rows': rows.map((r) => <String, Object?>{
          ...r,
          'raw': r['raw']?.toString().substring(
            0, (r['raw']!.toString().length).clamp(0, 300),
          ),
        }).toList(),
      };
    }

    final rows = await _database.queryMessagesBySession(
      sessionUnitId,
      limit: limit,
    );
    return <String, Object?>{
      'operation': 'SELECT messages (no ownerId filter)',
      'sessionUnitId': sessionUnitId,
      'limit': limit,
      'returned': rows.length,
      'rows': rows,
    };
  });

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(body: Center(child: Text('开发诊断仅在 Debug 模式可用。')));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('统一数据库测试'),
        actions: [
          IconButton(
            tooltip: '复制结果',
            onPressed: () => Clipboard.setData(ClipboardData(text: _result)),
            icon: const Icon(Icons.copy_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '所有端执行同一套 SQLite schema 和 SQL。移动/桌面使用数据库文件；Web 使用 SQLite WASM 持久化，'
            '不会维护另一套 IndexedDB 表结构。结果可直接复制。',
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Schema 与表操作',
            description: '查看数据库版本、实际表、行数与 CREATE TABLE SQL；可创建/删除隔离的诊断测试表。',
            children: [
              _button('检查 schema 与表', _inspect),
              _button('CREATE TABLE diagnostic_scratch', _createScratch),
              _button('DROP TABLE diagnostic_scratch', _dropScratch),
            ],
          ),
          _Section(
            title: 'diagnostic_records CRUD',
            description:
                '此表是正式 schema 的诊断记录表，用来验证 INSERT、SELECT、UPDATE、DELETE 与清表。',
            children: [
              _button('INSERT 样本记录', _insert),
              _button('SELECT 诊断记录', _read),
              _button('UPDATE 最后插入记录', _lastRecordId == null ? null : _update),
              _button('DELETE 最后插入记录', _lastRecordId == null ? null : _delete),
              _button('DELETE FROM diagnostic_records（清表）', _clear),
            ],
          ),

          // ── 消息本地查询 ─────────────────────────────────────────────────
          _Section(
            title: '📨 消息本地查询',
            description:
                '验证本地 SQLite 是否有指定会话的消息。ownerId 可留空（扫描所有 ownerId）。\n'
                '结果中 loadedAll=true 表示已拉取过全部历史；groups 按 ownerId 分组显示行数。',
            children: [
              const SizedBox(height: 4),
              TextField(
                controller: _sessionUnitIdCtrl,
                decoration: const InputDecoration(
                  labelText: 'SessionUnit ID *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _ownerIdCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Owner ID（可留空，留空则不过滤）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _limitCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '消息列表最大条数 (1–100)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              _button('统计 + loadedAll 状态', _queryMessageStats),
              _button('查询消息列表（SELECT）', _queryMessageList),
            ],
          ),

          const SizedBox(height: 16),
          Text('调用结果', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(
              _result,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _button(String label, VoidCallback? onPressed) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: FilledButton.tonal(
      onPressed: _working ? null : onPressed,
      child: Text(label),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.description,
    required this.children,
  });

  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(description),
          ...children,
        ],
      ),
    ),
  );
}

String _pretty(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(value);
