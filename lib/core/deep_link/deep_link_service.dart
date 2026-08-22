import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../config/app_environment.dart';
import 'deep_link_handler.dart';
import 'deep_link_parser.dart';

/// Single logged deep link event record for diagnostics.
class DeepLinkEventLog {
  const DeepLinkEventLog({
    required this.timestamp,
    required this.source,
    required this.rawUri,
    required this.parseResult,
    this.executionResult,
  });

  final DateTime timestamp;
  final String source;
  final Uri rawUri;
  final DeepLinkParseResult parseResult;
  final DeepLinkExecutionResult? executionResult;

  Map<String, dynamic> toMap() => {
        'timestamp': timestamp.toIso8601String(),
        'source': source,
        'rawUri': rawUri.toString(),
        'parseResult': parseResult.toMap(),
        if (executionResult != null)
          'executionResult': executionResult!.toMap(),
      };

  @override
  String toString() =>
      '[$source] ${rawUri.toString()} -> ${parseResult.status.name} (${executionResult?.status.name})';
}

/// Core service managing incoming Deep Links and Universal Links via `app_links`.
///
/// Responsibilities:
/// 1. Initializes `AppLinks` and captures cold-start URIs (`getInitialLink`).
/// 2. Listens to warm-start URI stream (`uriLinkStream`).
/// 3. Normalizes and parses incoming URIs with [DeepLinkParser].
/// 4. Dispatches parsed targets via [DeepLinkHandler].
/// 5. Maintains an in-memory event log buffer for the Development Diagnostics Center.
/// 6. Catches all exceptions to ensure app stability.
class DeepLinkService extends ChangeNotifier {
  DeepLinkService({
    required this.parser,
    required this.handler,
    AppLinks? appLinks,
  }) : _appLinks = appLinks ?? AppLinks();

  final DeepLinkParser parser;
  final DeepLinkHandler handler;
  final AppLinks _appLinks;

  StreamSubscription<Uri>? _linkSubscription;
  final List<DeepLinkEventLog> _eventLogs = [];
  bool _isInitialized = false;

  /// Read-only snapshot of recently recorded deep link events.
  List<DeepLinkEventLog> get eventLogs => List.unmodifiable(_eventLogs);

  /// Whether the service has completed cold-start and stream initialization.
  bool get isInitialized => _isInitialized;

  /// Initializes deep link listening.
  ///
  /// Call as early as possible during bootstrap.
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    try {
      // 1. Warm start stream listener
      _linkSubscription = _appLinks.uriLinkStream.listen(
        (uri) {
          debugPrint('[DeepLinkService] Received stream link: $uri');
          handleUri(uri, source: 'app_links_stream');
        },
        onError: (Object error, StackTrace stack) {
          debugPrint('[DeepLinkService] Stream error: $error\n$stack');
        },
      );

      // 2. Cold start initial link check
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        debugPrint('[DeepLinkService] Received initial link: $initialUri');
        await handleUri(initialUri, source: 'app_links_cold_start');
      }
    } catch (e, stack) {
      debugPrint('[DeepLinkService] Failed to initialize AppLinks: $e\n$stack');
    }
  }

  /// Handles an incoming URI from any source (cold start, stream, test, JSBridge).
  ///
  /// [execute] controls whether [DeepLinkHandler] performs route dispatch.
  Future<DeepLinkExecutionResult> handleUri(
    Uri uri, {
    String source = 'manual',
    bool execute = true,
  }) async {
    DeepLinkParseResult parseResult;
    try {
      parseResult = parser.parse(uri);
    } catch (e, stack) {
      debugPrint('[DeepLinkService] Parse exception: $e\n$stack');
      parseResult = DeepLinkParseResult.invalid(
        rawUri: uri,
        reason: 'Unexpected parser exception: $e',
      );
    }

    DeepLinkExecutionResult? executionResult;
    if (execute) {
      try {
        executionResult = await handler.handleParseResult(parseResult);
      } catch (e, stack) {
        debugPrint('[DeepLinkService] Execution exception: $e\n$stack');
        executionResult = DeepLinkExecutionResult(
          status: DeepLinkExecutionStatus.failed,
          target: parseResult.target,
          message: 'Handler exception: $e',
        );
      }
    }

    _recordEvent(
      DeepLinkEventLog(
        timestamp: DateTime.now(),
        source: source,
        rawUri: uri,
        parseResult: parseResult,
        executionResult: executionResult,
      ),
    );

    return executionResult ??
        DeepLinkExecutionResult(
          status: parseResult.isSuccess
              ? DeepLinkExecutionStatus.success
              : DeepLinkExecutionStatus.failed,
          target: parseResult.target,
          message: parseResult.reason ?? 'Parsed only without execution.',
        );
  }

  /// Appends an event to the log buffer (keeps last 50 events).
  void _recordEvent(DeepLinkEventLog event) {
    _eventLogs.insert(0, event);
    if (_eventLogs.length > 50) {
      _eventLogs.removeLast();
    }
    notifyListeners();
  }

  /// Clears all recorded event logs.
  void clearEventLogs() {
    _eventLogs.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _linkSubscription = null;
    super.dispose();
  }
}

/// Provider for [DeepLinkParser].
final deepLinkParserProvider = Provider<DeepLinkParser>((ref) {
  final env = ref.watch(appEnvironmentProvider);
  return DeepLinkParser(
    allowedCustomSchemes: env.deepLinkCustomSchemes,
    allowedHosts: env.deepLinkAllowedHosts,
  );
});

/// Provider for [DeepLinkHandler].
final deepLinkHandlerProvider = Provider<DeepLinkHandler>((ref) {
  return DeepLinkHandler();
});

/// Provider for [DeepLinkService].
final deepLinkServiceProvider = ChangeNotifierProvider<DeepLinkService>((ref) {
  final parser = ref.watch(deepLinkParserProvider);
  final handler = ref.watch(deepLinkHandlerProvider);
  final service = DeepLinkService(
    parser: parser,
    handler: handler,
  );
  ref.onDispose(service.dispose);
  return service;
});
