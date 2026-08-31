import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/task/app_task_manager.dart';
import '../../../features/workbench/data/workbench_models.dart';
import '../../../features/workbench/data/workbench_repository.dart';

class AppTaskDiagnosticsPage extends ConsumerStatefulWidget {
  const AppTaskDiagnosticsPage({super.key});

  @override
  ConsumerState<AppTaskDiagnosticsPage> createState() =>
      _AppTaskDiagnosticsPageState();
}

class _AppTaskDiagnosticsPageState
    extends ConsumerState<AppTaskDiagnosticsPage> {
  final _appIdController = TextEditingController(text: 'test-app');
  final _titleController = TextEditingController(text: 'Test App');
  final _urlController = TextEditingController(text: 'https://flutter.dev');
  bool _reuseExisting = true;
  String _result = '尚未执行。';
  bool _working = false;

  // Dynamic workbench apps for testing.
  final List<WorkbenchApp> _dynamicApps = <WorkbenchApp>[];

  @override
  void dispose() {
    _appIdController.dispose();
    _titleController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _run(String label, Future<void> Function() action) async {
    setState(() => _working = true);
    final stopwatch = Stopwatch()..start();
    try {
      await action();
      stopwatch.stop();
      if (mounted) {
        setState(
          () => _result = '$label 成功\n耗时：${stopwatch.elapsedMilliseconds} ms',
        );
      }
    } catch (error, stack) {
      stopwatch.stop();
      if (mounted) {
        setState(
          () =>
              _result =
                  '$label 失败\n'
                  '耗时：${stopwatch.elapsedMilliseconds} ms\n'
                  '异常：$error\n'
                  '${stack.toString().split('\n').take(5).join('\n')}',
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _openTask() async {
    final taskManager = ref.read(appTaskManagerProvider);
    await _run('openMiniApp', () async {
      await taskManager.openMiniApp(
        MiniAppTaskRequest(
          appId: _appIdController.text.trim(),
          title: _titleController.text.trim(),
          url: Uri.parse(_urlController.text.trim()),
          reuseExisting: _reuseExisting,
        ),
      );
    });
  }

  Future<void> _closeTask() async {
    final taskManager = ref.read(appTaskManagerProvider);
    await _run('closeCurrentTask', () => taskManager.closeCurrentTask());
  }

  void _openQuickApp(String appId, String name, String url) {
    _appIdController.text = appId;
    _titleController.text = name;
    _urlController.text = url;
    _openTask();
  }

  void _addDynamicApp(String appId, String name, String url) {
    final app = WorkbenchApp(
      appId: appId,
      name: name,
      url: Uri.parse(url),
      sort: _dynamicApps.length * 10 + 100,
    );
    setState(() {
      _dynamicApps.removeWhere((a) => a.appId == appId);
      _dynamicApps.add(app);
    });

    // Also add to the mock repository if available.
    final repository = ref.read(workbenchRepositoryProvider);
    if (repository is MockWorkbenchRepository) {
      repository.addApp(app);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(body: Center(child: Text('开发诊断仅在 Debug 模式可用。')));
    }

    final taskManager = ref.read(appTaskManagerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('应用级任务栈')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Platform info
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('平台信息', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    '支持 System Task：${taskManager.isSupported ? '✓ 是' : '✗ 否（降级为页面模式）'}',
                  ),
                  Text('平台：${defaultTargetPlatform.name}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Manual task test
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('任务栈测试', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  const Text('输入参数并打开独立 Task。同一 appId 再次打开应复用已有 Task。'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _appIdController,
                    decoration: const InputDecoration(
                      labelText: 'appId',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'title',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: 'url',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('reuseExisting'),
                    subtitle: const Text('再次打开时复用已有 Task'),
                    value: _reuseExisting,
                    onChanged: (v) => setState(() => _reuseExisting = v),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _working ? null : _openTask,
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('打开独立 Task'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: _working ? null : _closeTask,
                          child: const Text('关闭当前 Task'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Quick test buttons
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('快捷测试', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonal(
                        onPressed:
                            _working
                                ? null
                                : () => _openQuickApp(
                                  'app-a',
                                  'MiniApp A',
                                  'https://flutter.dev',
                                ),
                        child: const Text('MiniApp A'),
                      ),
                      FilledButton.tonal(
                        onPressed:
                            _working
                                ? null
                                : () => _openQuickApp(
                                  'app-b',
                                  'MiniApp B',
                                  'https://dart.dev',
                                ),
                        child: const Text('MiniApp B'),
                      ),
                      FilledButton.tonal(
                        onPressed:
                            _working
                                ? null
                                : () {
                                  final id = 'rand-${Random().nextInt(9999)}';
                                  _openQuickApp(
                                    id,
                                    'Random $id',
                                    'https://example.com/$id',
                                  );
                                },
                        child: const Text('随机 AppId'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Dynamic workbench test
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '工作台动态测试',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text('验证动态增加应用后无需修改 Manifest 即可创建独立 Task。'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed:
                            _working
                                ? null
                                : () => _addDynamicApp(
                                  'cloud-drive',
                                  'Cloud Drive',
                                  'https://drive.gotoim.com',
                                ),
                        child: const Text('+ Cloud Drive'),
                      ),
                      OutlinedButton(
                        onPressed:
                            _working
                                ? null
                                : () => _addDynamicApp(
                                  'erp',
                                  'ERP',
                                  'https://erp.gotoim.com',
                                ),
                        child: const Text('+ ERP'),
                      ),
                      OutlinedButton(
                        onPressed:
                            _working
                                ? null
                                : () => _addDynamicApp(
                                  'project',
                                  'Project',
                                  'https://project.gotoim.com',
                                ),
                        child: const Text('+ Project'),
                      ),
                    ],
                  ),
                  if (_dynamicApps.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 8),
                    ...(_dynamicApps.map(
                      (app) => ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          child: Text(app.name[0]),
                        ),
                        title: Text(app.name),
                        subtitle: Text(app.appId),
                        trailing: FilledButton.tonal(
                          onPressed:
                              _working
                                  ? null
                                  : () => _openQuickApp(
                                    app.appId,
                                    app.name,
                                    app.url.toString(),
                                  ),
                          child: const Text('打开'),
                        ),
                      ),
                    )),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Result panel
          Text('执行结果', style: Theme.of(context).textTheme.titleMedium),
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
}
