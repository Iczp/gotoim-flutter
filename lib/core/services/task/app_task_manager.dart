import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/workbench/data/workbench_models.dart';

export '../../../features/workbench/data/workbench_models.dart'
    show MiniAppTaskRequest, MiniAppLaunchRequest;

/// Platform-agnostic API for managing independent application tasks.
///
/// On Android this creates real system tasks via `FLAG_ACTIVITY_NEW_DOCUMENT`.
/// On iOS/Web/Desktop this degrades to opening a Flutter page.
abstract interface class AppTaskManager {
  /// Whether the current platform supports independent system tasks.
  bool get isSupported;

  /// Opens a MiniApp as an independent system task (Android) or as a
  /// Flutter page (iOS/Web/Desktop fallback).
  ///
  /// When [request.reuseExisting] is true and a task with the same
  /// [request.appId] already exists, the existing task is brought to front.
  Future<void> openMiniApp(MiniAppTaskRequest request);

  /// Closes the current MiniApp task (Android: `finishAndRemoveTask()`).
  ///
  /// On non-Android platforms this pops the MiniApp page.
  Future<void> closeCurrentTask();
}

/// Callback interface implemented by the MiniApp Dart side to receive
/// new launch payloads when an already-running task is re-activated
/// with a different URL.
abstract interface class MiniAppLaunchHandler {
  Future<void> handleLaunch(MiniAppLaunchRequest request);
}

/// Provider for the application task manager. Overridden at bootstrap with the
/// platform-appropriate implementation.
final appTaskManagerProvider = Provider<AppTaskManager>(
  (ref) => throw UnimplementedError(
    'AppTaskManager must be provided at bootstrap.',
  ),
);

/// Helper that opens a [WorkbenchApp] using the appropriate mechanism based
/// on its [AppOpenMode].
Future<void> openWorkbenchApp(
  WorkbenchApp app, {
  required AppTaskManager taskManager,
  required NavigatorState? navigator,
}) async {
  switch (app.openMode) {
    case AppOpenMode.systemTask:
      await taskManager.openMiniApp(
        MiniAppTaskRequest(
          appId: app.appId,
          title: app.name,
          url: app.url,
          iconUrl: app.iconUrl,
          reuseExisting: app.reuseExisting,
        ),
      );
    case AppOpenMode.page:
      // Open as a Flutter page within the main navigator.
      await taskManager.openMiniApp(
        MiniAppTaskRequest(
          appId: app.appId,
          title: app.name,
          url: app.url,
          iconUrl: app.iconUrl,
          reuseExisting: app.reuseExisting,
        ),
      );
    case AppOpenMode.current:
      // Future: open inside the current container.
      debugPrint('[AppTask] openMode=current is not yet implemented, '
          'falling back to page mode for ${app.appId}');
      await taskManager.openMiniApp(
        MiniAppTaskRequest(
          appId: app.appId,
          title: app.name,
          url: app.url,
          iconUrl: app.iconUrl,
          reuseExisting: app.reuseExisting,
        ),
      );
  }
}
