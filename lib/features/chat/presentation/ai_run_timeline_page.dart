import 'package:flutter/material.dart';

import '../application/ai_stream_change_bus.dart';
import '../application/chat_controller.dart';

/// Read-only Redis-backed history for the current conversation's AI runs.
/// Final replies remain ordinary IM messages; this page explains the runtime
/// lifecycle that produced them without exposing model prompts or secrets.
class AiRunTimelinePage extends StatefulWidget {
  const AiRunTimelinePage({required this.controller, super.key});

  final ChatController controller;

  @override
  State<AiRunTimelinePage> createState() => _AiRunTimelinePageState();
}

class _AiRunTimelinePageState extends State<AiRunTimelinePage> {
  Object? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.controller.refreshRecentAiRuns();
    } catch (error) {
      _error = error;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text('AI 运行记录', style: Theme.of(context).textTheme.titleLarge),
            ),
            IconButton(
              tooltip: '刷新',
              onPressed: _loading ? null : _reload,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: '关闭',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.error_outline, size: 40),
                  const SizedBox(height: 12),
                  const Text('无法读取 AI 运行记录'),
                  const SizedBox(height: 8),
                  Text('请检查网络或稍后重试。', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _reload, child: const Text('重试')),
                ],
              ),
            ),
          )
        : AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) {
              final runs = widget.controller.recentAiRuns;
              if (runs.isEmpty) {
                return const Center(child: Text('当前会话暂无 AI 运行记录'));
              }
              return RefreshIndicator(
                onRefresh: _reload,
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: runs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => _RunCard(run: runs[index]),
                ),
              );
            },
          ),
      ),
    ],
  );
}

class _RunCard extends StatelessWidget {
  const _RunCard({required this.run});
  final AiRunRecord run;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = run.status == 'failed' || run.status == 'cancelled';
    final active = run.status == 'running' || run.status == 'streaming' || run.status == 'queued';
    final color = failed
        ? theme.colorScheme.error
        : active
        ? theme.colorScheme.primary
        : theme.colorScheme.tertiary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(active ? Icons.pending_outlined : failed ? Icons.error_outline : Icons.check_circle_outline, color: color),
                const SizedBox(width: 8),
                Expanded(child: Text(_statusText(run.status), style: theme.textTheme.titleSmall)),
                Text(run.updatedAt == null ? '—' : _time(run.updatedAt!), style: theme.textTheme.labelSmall),
              ],
            ),
            const SizedBox(height: 8),
            Text('源消息 ${run.sourceMessageId} · 排队 ${_duration(run.queueMilliseconds)} · 调用 ${_duration(run.elapsedMilliseconds)}'),
            if (run.finalMessageId != null) Text('最终消息 ${run.finalMessageId}', style: theme.textTheme.bodySmall),
            if (run.error.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(run.error, style: TextStyle(color: theme.colorScheme.error)),
            ],
            if (run.timeline.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('执行时间线（${run.timeline.length}）', style: theme.textTheme.bodySmall),
                children: run.timeline.map((item) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.more_time, size: 18),
                  title: Text(_statusText(item.status)),
                  subtitle: Text('${item.eventType}${item.detail.isEmpty ? '' : ' · ${item.detail}'}'),
                  trailing: Text(_duration(item.elapsedMilliseconds), style: theme.textTheme.labelSmall),
                )).toList(growable: false),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _statusText(String status) => switch (status) {
  'queued' => '等待执行',
  'running' => '正在思考',
  'streaming' => '正在生成',
  'completed' => '已完成',
  'failed' => '执行失败',
  'cancelled' => '已取消',
  _ => status.isEmpty ? '未知状态' : status,
};

String _duration(int milliseconds) {
  if (milliseconds < 1000) return '${milliseconds}ms';
  if (milliseconds < 60000) return '${(milliseconds / 1000).toStringAsFixed(1)}s';
  return '${milliseconds ~/ 60000}分${(milliseconds % 60000) ~/ 1000}秒';
}

String _time(DateTime time) =>
    '${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
