import 'package:flutter/foundation.dart';

/// ANSI escape codes for coloring console log messages.
const String ansiRed = '\x1B[31;1m';
const String ansiYellow = '\x1B[33m';
const String ansiReset = '\x1B[0m';

bool isConsoleErrorMessage(String message) {
  final lower = message.toLowerCase();
  return lower.contains('[failed]') ||
      lower.contains('[error]') ||
      lower.contains('error=') ||
      lower.contains('exception:') ||
      lower.contains('flutter error:') ||
      lower.contains('unhandled exception:') ||
      lower.contains('bad state:') ||
      lower.contains('assertion failed') ||
      lower.contains('uncaught error') ||
      lower.contains('cannot be used') ||
      lower.contains('stateerror');
}

bool isConsoleWarningMessage(String message) {
  final lower = message.toLowerCase();
  return lower.contains('[warn]') ||
      lower.contains('[warning]') ||
      lower.contains('warning:');
}

/// Sets up ANSI colored debugPrint output so errors appear in bold red
/// and warnings appear in yellow.
void setupConsoleColorLogger() {
  final originalDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message == null) return;
    if (message.startsWith('\x1B[')) {
      originalDebugPrint(message, wrapWidth: wrapWidth);
    } else if (isConsoleErrorMessage(message)) {
      originalDebugPrint('$ansiRed$message$ansiReset', wrapWidth: wrapWidth);
    } else if (isConsoleWarningMessage(message)) {
      originalDebugPrint('$ansiYellow$message$ansiReset', wrapWidth: wrapWidth);
    } else {
      originalDebugPrint(message, wrapWidth: wrapWidth);
    }
  };
}
