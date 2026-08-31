enum DiagnosticLogLevel {
  debug,
  info,
  warning,
  error,
  fatal;

  String get value => name;

  bool get isError => this == error || this == fatal;
}
