import 'diagnostic_log_entry.dart';

class StackTraceParser {
  static final RegExp _frame = RegExp(
    r'^#\d+\s+(.+?)\s+\((package:gotoim_flutter/)?([^\s\)]+):(\d+)(?::(\d+))?\)',
  );

  static List<SourceLocation> parse(StackTrace trace) {
    final result = <SourceLocation>[];
    for (final line in trace.toString().split('\n')) {
      final match = _frame.firstMatch(line.trim());
      if (match == null) continue;
      final packageFrame = match.group(2) != null;
      final rawFile = match.group(3)!;
      final file = packageFrame ? 'lib/$rawFile' : rawFile;
      if (!file.startsWith('lib/')) continue;
      result.add(SourceLocation(
        file: file,
        line: int.tryParse(match.group(4)!),
        column: int.tryParse(match.group(5) ?? ''),
        function: match.group(1),
      ));
    }
    return result;
  }

  static SourceLocation? firstApplicationFrame(StackTrace trace) {
    final frames = parse(trace);
    return frames.cast<SourceLocation?>().firstWhere(
          (frame) =>
              frame != null && !frame.file.startsWith('lib/core/logging/'),
          orElse: () => frames.isEmpty ? null : frames.first,
        );
  }
}
