import 'dart:developer' as developer;

import 'package:uuid/uuid.dart';

import 'diagnostic_log_entry.dart';
import 'diagnostic_log_level.dart';
import 'diagnostic_log_store.dart';
import 'log_sanitizer.dart';
import 'stack_trace_parser.dart';

class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();
  static const _uuid = Uuid();
  final DiagnosticLogStore store = DiagnosticLogStore();
  bool _captureEnabled = true;
  bool get captureEnabled => _captureEnabled;

  void setCaptureEnabled(bool value) {
    _captureEnabled = value;
    _write(
        DiagnosticLogLevel.info, value ? 'capture_started' : 'capture_stopped',
        category: 'devtools', force: true);
  }

  void debug(String message,
          {String category = 'app',
          String event = 'debug',
          String? traceId,
          Map<String, Object?>? context}) =>
      _write(DiagnosticLogLevel.debug, message,
          category: category, event: event, traceId: traceId, context: context);
  void info(String message,
          {String category = 'app',
          String event = 'info',
          String? traceId,
          Map<String, Object?>? context}) =>
      _write(DiagnosticLogLevel.info, message,
          category: category, event: event, traceId: traceId, context: context);
  void warning(String message,
          {String category = 'app',
          String event = 'warning',
          String? traceId,
          Map<String, Object?>? context}) =>
      _write(DiagnosticLogLevel.warning, message,
          category: category, event: event, traceId: traceId, context: context);
  void error(String message,
          {String category = 'app',
          String event = 'error',
          String? traceId,
          Map<String, Object?>? context,
          Object? error,
          StackTrace? stackTrace,
          SourceLocation? source,
          List<String> relatedFiles = const [],
          DiagnosticHint? diagnostic}) =>
      _write(DiagnosticLogLevel.error, message,
          category: category,
          event: event,
          traceId: traceId,
          context: context,
          error: error,
          stackTrace: stackTrace,
          source: source,
          relatedFiles: relatedFiles,
          diagnostic: diagnostic);
  void fatal(String message,
          {String category = 'app',
          String event = 'fatal',
          String? traceId,
          Map<String, Object?>? context,
          Object? error,
          StackTrace? stackTrace,
          SourceLocation? source,
          List<String> relatedFiles = const [],
          DiagnosticHint? diagnostic}) =>
      _write(DiagnosticLogLevel.fatal, message,
          category: category,
          event: event,
          traceId: traceId,
          context: context,
          error: error,
          stackTrace: stackTrace,
          source: source,
          relatedFiles: relatedFiles,
          diagnostic: diagnostic);

  void marker(String message) => _write(DiagnosticLogLevel.info, message,
      category: 'marker', event: 'marker', force: true);

  void _write(DiagnosticLogLevel level, String message,
      {String category = 'app',
      String event = 'log',
      String? traceId,
      Map<String, Object?>? context,
      Object? error,
      StackTrace? stackTrace,
      SourceLocation? source,
      List<String> relatedFiles = const [],
      DiagnosticHint? diagnostic,
      bool force = false}) {
    developer.log(message,
        name: category,
        level: level.index * 200,
        error: error,
        stackTrace: stackTrace);
    if (!_captureEnabled && !force) return;
    final trace = stackTrace ?? (level.isError ? StackTrace.current : null);
    final frames = trace == null
        ? const <SourceLocation>[]
        : StackTraceParser.parse(trace);
    final entry = DiagnosticLogEntry(
      id: _uuid.v7(),
      timestamp: DateTime.now(),
      level: level,
      category: category,
      event: event,
      message: message,
      traceId: traceId,
      source: source ??
          (trace == null
              ? null
              : StackTraceParser.firstApplicationFrame(trace)),
      callSites: frames,
      relatedFiles: relatedFiles.take(5).toList(),
      context: Map<String, Object?>.from(
          LogSanitizer.sanitize(context ?? const <String, Object?>{}) as Map),
      error: error == null
          ? null
          : DiagnosticError(
              type: error.runtimeType.toString(),
              message: error.toString(),
              stack: trace?.toString()),
      diagnostic: diagnostic,
    );
    store.add(entry);
  }
}
