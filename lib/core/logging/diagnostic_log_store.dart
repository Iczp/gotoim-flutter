import 'dart:async';

import 'diagnostic_log_entry.dart';

class DiagnosticLogStore {
  DiagnosticLogStore({this.maxEntries = 5000});

  final int maxEntries;
  final List<DiagnosticLogEntry> _entries = <DiagnosticLogEntry>[];
  final StreamController<List<DiagnosticLogEntry>> _changes =
      StreamController<List<DiagnosticLogEntry>>.broadcast();

  Stream<List<DiagnosticLogEntry>> get changes => _changes.stream;
  int get length => _entries.length;
  List<DiagnosticLogEntry> get entries => List.unmodifiable(_entries);

  void add(DiagnosticLogEntry entry) {
    _entries.add(entry);
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
    _changes.add(<DiagnosticLogEntry>[entry]);
  }

  void clear() {
    _entries.clear();
    _changes.add(const <DiagnosticLogEntry>[]);
  }

  List<DiagnosticLogEntry> search({
    String? query,
    String? level,
    String? category,
    String? traceId,
    int limit = 500,
  }) {
    final needle = query?.trim().toLowerCase();
    return _entries.reversed
        .where((entry) {
          if (level != null && level.isNotEmpty && entry.level.value != level) {
            return false;
          }
          if (category != null &&
              category.isNotEmpty &&
              entry.category != category) {
            return false;
          }
          if (traceId != null &&
              traceId.isNotEmpty &&
              entry.traceId != traceId) {
            return false;
          }
          if (needle == null || needle.isEmpty) return true;
          return '${entry.message} ${entry.event} ${entry.category} ${entry.error?.message ?? ''}'
              .toLowerCase()
              .contains(needle);
        })
        .take(limit)
        .toList()
        .reversed
        .toList();
  }

  Future<void> dispose() => _changes.close();
}
