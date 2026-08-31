import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app_task_manager.dart';

/// Android implementation of [AppTaskManager].
///
/// Uses a [MethodChannel] to communicate with `MainActivity` on the
/// native side, which launches `MiniAppActivity` with
/// `FLAG_ACTIVITY_NEW_DOCUMENT` and `documentLaunchMode="intoExisting"`.
class AndroidAppTaskManager implements AppTaskManager {
  AndroidAppTaskManager({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.gotoim.task_manager');

  final MethodChannel _channel;

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
}
