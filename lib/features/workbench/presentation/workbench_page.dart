import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/task/app_task_manager.dart';
import '../data/workbench_models.dart';
import '../data/workbench_repository.dart';

/// The workbench tab page that displays dynamically loaded applications.
///
/// Applications are fetched from [WorkbenchRepository] and displayed in a
/// grid layout. Tapping an app opens it according to its [AppOpenMode].
class WorkbenchPage extends ConsumerStatefulWidget {
  const WorkbenchPage({super.key});

  @override
  ConsumerState<WorkbenchPage> createState() => _WorkbenchPageState();
}

class _WorkbenchPageState extends ConsumerState<WorkbenchPage> {
  List<WorkbenchApp> _apps = <WorkbenchApp>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  Future<void> _loadApps({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = ref.read(workbenchRepositoryProvider);
      final apps = await repository.getApps(forceRefresh: forceRefresh);
      if (mounted) {
        setState(() {
          _apps = apps;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _openApp(WorkbenchApp app) async {
    try {
      final taskManager = ref.read(appTaskManagerProvider);
      await openWorkbenchApp(
        app,
        taskManager: taskManager,
        navigator: Navigator.of(context),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开 ${app.name} 失败：$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (_error != null) {
      content = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('加载失败：$_error'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => _loadApps(forceRefresh: true),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    } else if (_loading && _apps.isEmpty) {
      content = const Center(child: CircularProgressIndicator());
    } else {
      content = RefreshIndicator(
        onRefresh: () => _loadApps(forceRefresh: true),
        child: GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 100,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 0.8,
          ),
          itemCount: _apps.length,
          itemBuilder: (context, index) {
            final app = _apps[index];
            return _AppGridItem(
              app: app,
              onTap: () => _openApp(app),
            );
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('工作台')),
      body: content,
    );
  }
}

class _AppGridItem extends StatelessWidget {
  const _AppGridItem({required this.app, required this.onTap});

  final WorkbenchApp app;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                app.name.isNotEmpty ? app.name[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            app.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
