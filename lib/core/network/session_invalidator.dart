import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Decoupled session invalidator bus/handler.
///
/// Allows transport layers (e.g. [DioApiClient]) to trigger session invalidation
/// without establishing a direct Riverpod dependency on [AuthController],
/// which prevents circular dependency errors in Riverpod's DAG.
class SessionInvalidator {
  Future<void> Function({String? reason})? _handler;

  void register(Future<void> Function({String? reason}) handler) {
    _handler = handler;
  }

  void unregister(Future<void> Function({String? reason}) handler) {
    if (_handler == handler) {
      _handler = null;
    }
  }

  Future<void> invalidate({String? reason}) async {
    final handler = _handler;
    if (handler != null) {
      try {
        await handler(reason: reason);
      } catch (e, st) {
        debugPrint('[SessionInvalidator] Error handling invalidation: $e\n$st');
      }
    }
  }
}

final Provider<SessionInvalidator> sessionInvalidatorProvider =
    Provider<SessionInvalidator>((ref) {
  return SessionInvalidator();
});
