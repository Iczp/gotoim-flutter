import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../floating_window/floating_window.dart';
import 'app_task_manager.dart';

/// Android implementation of [AppTaskManager].
///
/// Uses a [MethodChannel] to communicate with `MainActivity` on the
/// native side, which launches `MiniAppActivity` with
/// `FLAG_ACTIVITY_NEW_DOCUMENT` and `documentLaunchMode="intoExisting"`.
class AndroidAppTaskManager implements AppTaskManager {
  AndroidAppTaskManager({
    MethodChannel? channel,
    FloatingWindowManager? floatingWindowManager,
  })  : _channel = channel ?? const MethodChannel('com.gotoim.task_manager'),
        _floatingWindowManager = floatingWindowManager {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  final MethodChannel _channel;
  final FloatingWindowManager? _floatingWindowManager;

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onMiniAppMinimized':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final appId = args['appId'] as String? ?? '';
        final title = args['title'] as String? ?? appId;
        final urlStr = args['url'] as String? ?? '';
        final url = Uri.tryParse(urlStr) ?? Uri.parse('about:blank');
        final iconUrl = args['iconUrl'] as String?;

        if (appId.isNotEmpty && _floatingWindowManager != null) {
          _floatingWindowManager.show(
            id: 'miniapp:$appId',
            options: const FloatingWindowOptions(
              initialSize: Size(232, 92),
              snapToEdge: true,
              resizable: false,
            ),
            child: _MiniAppFloatingBubble(
              title: title,
              onRestore: () {
                _floatingWindowManager.close('miniapp:$appId');
                openMiniApp(
                  MiniAppTaskRequest(
                    appId: appId,
                    title: title,
                    url: url,
                    iconUrl: iconUrl,
                    reuseExisting: true,
                  ),
                );
              },
              onClose: () {
                _floatingWindowManager.close('miniapp:$appId');
                closeTaskByAppId(appId);
              },
            ),
          );
        }
        break;
      case 'onMiniAppClosed':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final appId = args['appId'] as String? ?? '';
        if (appId.isNotEmpty) {
          _floatingWindowManager?.close('miniapp:$appId');
        }
        break;
    }
  }

  @override
  bool get isSupported => true;

  @override
  Future<void> openMiniApp(MiniAppTaskRequest request) async {
    debugPrint(
      '[AppTask] open appId=${request.appId} '
      'url=${request.url} reuse=${request.reuseExisting}',
    );
    await _channel.invokeMethod<void>('openMiniApp', request.toJson());
  }

  @override
  Future<void> closeCurrentTask() async {
    debugPrint('[AppTask] close current task');
    await _channel.invokeMethod<void>('closeCurrentTask');
  }

  @override
  Future<void> closeTaskByAppId(String appId) async {
    debugPrint('[AppTask] close task by appId=$appId');
    await _channel.invokeMethod<void>('closeTaskByAppId', {'appId': appId});
  }
}

class _MiniAppFloatingBubble extends StatelessWidget {
  const _MiniAppFloatingBubble({
    required this.title,
    required this.onRestore,
    required this.onClose,
  });

  final String title;
  final VoidCallback onRestore;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      color: colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      elevation: 6,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onRestore,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.widgets_outlined,
                  size: 20,
                  color: colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '点击返回应用',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '关闭',
                icon: const Icon(Icons.close, size: 18),
                onPressed: onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

