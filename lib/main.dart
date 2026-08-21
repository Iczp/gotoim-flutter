import 'dart:async';
import 'package:flutter/widgets.dart';

import 'app/bootstrap.dart';
import 'app/bootstrap_error_app.dart';

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

