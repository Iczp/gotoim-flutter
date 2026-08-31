import 'diagnostic_log_level.dart';

class SourceLocation {
  const SourceLocation({
    required this.file,
    this.line,
    this.column,
    this.function,
  });

  final String file;
  final int? line;
  final int? column;
  final String? function;

  Map<String, Object?> toJson() => <String, Object?>{
        'file': file,
        'line': line,
        'column': column,
        'function': function,
      };
}

class DiagnosticError {
  const DiagnosticError(
      {required this.type, required this.message, this.stack});

  final String type;
  final String message;
  final String? stack;

  Map<String, Object?> toJson() => <String, Object?>{
        'type': type,
        'message': message,
        'stack': stack,
      };
}

class DiagnosticHint {
  const DiagnosticHint({
    required this.summary,
    this.suspectedArea,
    this.inspectReason,
  });

  final String summary;
  final String? suspectedArea;
  final String? inspectReason;

  Map<String, Object?> toJson() => <String, Object?>{
        'summary': summary,
        'suspectedArea': suspectedArea,
        'inspectReason': inspectReason,
      };
}

class DiagnosticLogEntry {
  const DiagnosticLogEntry({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.category,
    required this.event,
    required this.message,
    this.traceId,
    this.spanId,
    this.source,
    this.callSites = const <SourceLocation>[],
    this.relatedFiles = const <String>[],
    this.context = const <String, Object?>{},
    this.error,
    this.diagnostic,
    this.tags = const <String>[],
  });

  final String id;
  final DateTime timestamp;
  final DiagnosticLogLevel level;
  final String category;
  final String event;
  final String message;
  final String? traceId;
  final String? spanId;
  final SourceLocation? source;
  final List<SourceLocation> callSites;
  final List<String> relatedFiles;
  final Map<String, Object?> context;
  final DiagnosticError? error;
  final DiagnosticHint? diagnostic;
  final List<String> tags;

  Map<String, Object?> toJson() => <String, Object?>{
        'schema': 'gotoim-diagnostic/v1',
        'id': id,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'level': level.value,
        'category': category,
        'event': event,
        'message': message,
        'traceId': traceId,
        'spanId': spanId,
        'source': source?.toJson(),
        'callSites': callSites.map((item) => item.toJson()).toList(),
        'relatedFiles': relatedFiles,
        'context': context,
        'error': error?.toJson(),
        'diagnostic': diagnostic?.toJson(),
        'tags': tags,
      };
}
