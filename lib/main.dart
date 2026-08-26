import 'package:flutter/widgets.dart';

import 'app/bootstrap.dart';
import 'app/bootstrap_error_app.dart';
import 'app/mini_app_bootstrap.dart';

Future<void> main() async {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('Flutter error: ${details.exception}\n${details.stack}');
  };

  // [bootstrap] owns its error boundary. Do not wrap it in runZonedGuarded:
  // the guarded-zone error handler runs in the parent zone, while Flutter's
  // binding is initialized inside bootstrap. Calling runApp from that parent
  // zone causes Flutter's "Zone mismatch" assertion.
  await bootstrap();
}

/// Entry point for MiniApp FlutterEngines.
///
/// This is called by [MiniAppActivity] via [FlutterEngineGroup.createAndRunEngine]
/// with the Dart entrypoint name `miniAppMain`. It runs a lightweight bootstrap
/// that only initializes services needed by the WebView container.
@pragma('vm:entry-point')
Future<void> miniAppMain() async {
  try {
    await miniAppBootstrap();
  } catch (error, stackTrace) {
    // miniAppBootstrap initializes the binding before any await. Keeping the
    // fallback runApp in this same async zone avoids a binding-zone mismatch.
    debugPrint('MiniApp unhandled error: $error\n$stackTrace');
    runApp(BootstrapErrorApp(error: error, stackTrace: stackTrace));
  }
}
