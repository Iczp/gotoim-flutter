import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/deep_link/deep_link_service.dart';
import '../../../core/services/task/app_task_manager.dart';
import '../data/workbench_models.dart';
import '../data/workbench_repository.dart';

/// The workbench tab page that displays dynamically loaded applications.
///
/// Supports opening applications via:
/// 1. Direct task launch (Android Document Task / Flutter Page).
/// 2. Uniform Deep Link dispatch (`gotoim-dev://workbench/{appId}`).
class WorkbenchPage extends ConsumerStatefulWidget {
  const WorkbenchPage({super.key});

  @override
  ConsumerState<WorkbenchPage> createState() => _WorkbenchPageState();
}

class _WorkbenchPageState extends ConsumerState<WorkbenchPage> {
  List<WorkbenchApp> _apps = <WorkbenchApp>[];
  bool _loading = true;
  String? _error;
  bool _useDeepLinkMode = false;

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

  Future<void> _openAppDirect(WorkbenchApp app) async {
    try {
      final taskManager = ref.read(appTaskManagerProvider);
      await openWorkbenchApp(
        app,
        taskManager: taskManager,
        navigator: Navigator.of(context),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('打开 ${app.name} 失败：$e')));
      }
    }
  }

  Future<void> _openAppViaDeepLink(WorkbenchApp app) async {
    final deepLinkUri = Uri.parse('gotoim-dev://workbench/${app.appId}');
    try {
      final service = ref.read(deepLinkServiceProvider);
      final result = await service.handleUri(
        deepLinkUri,
        source: 'workbench_ui',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Deep Link 响应 (${result.status.name}): ${result.message}',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Deep Link 打开失败：$e')));
      }
    }
  }

  void _showAppActionSheet(WorkbenchApp app) {
    final deepLinkStr = 'gotoim-dev://workbench/${app.appId}';

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    child: Text(
                      app.name.isNotEmpty ? app.name[0].toUpperCase() : '?',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  title: Text(
                    app.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'AppID: ${app.appId}  •  ${app.url}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.rocket_launch_outlined),
                  title: const Text('常规打开 (直接启动)'),
                  subtitle: Text('以 ${app.openMode.name} 模式独立启动应用'),
                  onTap: () {
                    Navigator.pop(context);
                    _openAppDirect(app);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.link),
                  title: const Text('通过 Deep Link 唤醒'),
                  subtitle: Text(deepLinkStr),
                  onTap: () {
                    Navigator.pop(context);
                    _openAppViaDeepLink(app);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.copy_outlined),
                  title: const Text('复制 Deep Link 链接'),
                  subtitle: const Text('可用于外部网页唤醒或快捷方式'),
                  onTap: () {
                    Navigator.pop(context);
                    Clipboard.setData(ClipboardData(text: deepLinkStr));
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('已复制：$deepLinkStr')));
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
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
              useDeepLink: _useDeepLinkMode,
              onTap:
                  () =>
                      _useDeepLinkMode
                          ? _openAppViaDeepLink(app)
                          : _openAppDirect(app),
              onLongPress: () => _showAppActionSheet(app),
            );
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('工作台'),
        actions: [
          Tooltip(
            message: _useDeepLinkMode ? '当前：Deep Link 打开模式' : '当前：直接启动模式',
            child: Row(
              children: [
                Icon(
                  _useDeepLinkMode ? Icons.link : Icons.open_in_new,
                  size: 18,
                  color:
                      _useDeepLinkMode
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  _useDeepLinkMode ? 'DeepLink' : '常规',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color:
                        _useDeepLinkMode
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                Switch(
                  value: _useDeepLinkMode,
                  onChanged: (val) => setState(() => _useDeepLinkMode = val),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: content,
    );
  }
}

class _AppGridItem extends StatelessWidget {
  const _AppGridItem({
    required this.app,
    required this.onTap,
    required this.onLongPress,
    this.useDeepLink = false,
  });

  final WorkbenchApp app;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool useDeepLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primaryContainer,
                      colorScheme.surfaceContainerHighest,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.shadow.withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    app.name.isNotEmpty ? app.name[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ),
              if (useDeepLink)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.link,
                      size: 12,
                      color: colorScheme.onPrimary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            app.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
