import 'package:flutter/material.dart';

import '../../../features/workbench/presentation/mini_app_host_page.dart';
import 'app_task_manager.dart';

/// Fallback [AppTaskManager] for platforms without system task support
/// (iOS, Web, Desktop).
///
/// Opens MiniApps as regular Flutter pages within the main navigator.
/// The interface is preserved so future iPad Scene / macOS Window
/// implementations can be swapped in without changing business code.
class StubAppTaskManager implements AppTaskManager {
  StubAppTaskManager({this.navigatorProvider});

  /// Provides the root navigator for page-mode fallback.
  final NavigatorState? Function()? navigatorProvider;

  @override
  bool get isSupported => false;

  @override
  Future<void> openMiniApp(MiniAppTaskRequest request) async {
    debugPrint('[AppTask] stub open appId=${request.appId} '
        '(platform does not support system tasks, opening as page)');
    final navigator = navigatorProvider?.call();
    if (navigator == null) {
      debugPrint('[AppTask] no navigator available for page fallback');
      return;
    }
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (context) => MiniAppHostPage(
          request: MiniAppLaunchRequest(
            appId: request.appId,
            url: request.url,
            title: request.title,
            arguments: request.arguments,
          ),
        ),
      ),
    );
  }

  @override
  Future<void> closeCurrentTask() async {
    debugPrint('[AppTask] stub close (popping current route)');
    final navigator = navigatorProvider?.call();
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
    }
  }
}
