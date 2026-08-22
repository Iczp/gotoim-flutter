import 'dart:async';
import 'package:flutter/widgets.dart';

import 'app/bootstrap.dart';
import 'app/bootstrap_error_app.dart';
import 'app/mini_app_bootstrap.dart';

Future<void> main() async {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('Flutter error: ${details.exception}\n${details.stack}');
  };

  runZonedGuarded(() async {
    await bootstrap();
  }, (error, stackTrace) {
    debugPrint('Unhandled error: $error\n$stackTrace');
    runApp(BootstrapErrorApp(error: error, stackTrace: stackTrace));
  });
}

/// Entry point for MiniApp FlutterEngines.
///
/// This is called by [MiniAppActivity] via [FlutterEngineGroup.createAndRunEngine]
/// with the Dart entrypoint name `miniAppMain`. It runs a lightweight bootstrap
/// that only initializes services needed by the WebView container.
@pragma('vm:entry-point')
Future<void> miniAppMain() async {
  runZonedGuarded(() async {
    await miniAppBootstrap();
  }, (error, stackTrace) {
    debugPrint('MiniApp unhandled error: $error\n$stackTrace');
    runApp(BootstrapErrorApp(error: error, stackTrace: stackTrace));
  });
}

