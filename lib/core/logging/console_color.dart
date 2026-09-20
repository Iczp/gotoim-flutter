import 'package:flutter/foundation.dart';

/// ANSI escape codes for coloring console log messages.
const String ansiRed = '\x1B[31;1m';
const String ansiYellow = '\x1B[33;1m';
const String ansiGreen = '\x1B[32;1m';
const String ansiCyan = '\x1B[36m';
const String ansiReset = '\x1B[0m';

String consoleError(String msg) => '$ansiRed$msg$ansiReset';
String consoleWarn(String msg) => '$ansiYellow$msg$ansiReset';
String consoleSuccess(String msg) => '$ansiGreen$msg$ansiReset';
String consoleInfo(String msg) => '$ansiCyan$msg$ansiReset';

bool isConsoleErrorMessage(String message) {
  final lower = message.toLowerCase();
  return lower.contains('failed') ||
      lower.contains('error') ||
      lower.contains('exception') ||
      lower.contains('fatal') ||
      lower.contains('crash') ||
      lower.contains('unhandled') ||
      lower.contains('rejected') ||
      lower.contains('assertion') ||
      lower.contains('失败') ||
      lower.contains('错误') ||
      lower.contains('异常');
}

bool isConsoleWarningMessage(String message) {
  final lower = message.toLowerCase();
  return lower.contains('warn') ||
      lower.contains('warning') ||
      lower.contains('警告');
}

bool isConsoleSuccessMessage(String message) {
  final lower = message.toLowerCase();
  return lower.contains('success') ||
      lower.contains('connected') ||
      lower.contains('succeeded') ||
      lower.contains('成功');
}

/// Sets up ANSI colored debugPrint output so:
/// - Errors/failures appear in bold red
/// - Warnings appear in yellow
/// - Success/connected appear in green
void setupConsoleColorLogger() {
  final originalDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message == null) return;
    if (message.contains('\x1B[')) {
      originalDebugPrint(message, wrapWidth: wrapWidth);
    } else if (isConsoleErrorMessage(message)) {
      originalDebugPrint('$ansiRed$message$ansiReset', wrapWidth: wrapWidth);
    } else if (isConsoleWarningMessage(message)) {
      originalDebugPrint('$ansiYellow$message$ansiReset', wrapWidth: wrapWidth);
    } else if (isConsoleSuccessMessage(message)) {
      originalDebugPrint('$ansiGreen$message$ansiReset', wrapWidth: wrapWidth);
    } else {
      originalDebugPrint(message, wrapWidth: wrapWidth);
    }
  };
}
