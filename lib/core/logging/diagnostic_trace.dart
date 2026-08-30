import 'package:uuid/uuid.dart';

class DiagnosticTrace {
  static const _uuid = Uuid();

  static String create(String operation) =>
      '${operation.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '-')}-${_uuid.v7()}';
}
