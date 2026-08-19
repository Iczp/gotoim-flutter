import 'dart:async';

import 'js_api_dispatcher.dart';

/// Minimal transport contract implemented by a WebView JavaScriptChannel
/// adapter. Keeping it plugin-free lets Android/iOS and desktop WebViews share
/// the same request/response and event behavior.
abstract class JsBridgeTransport {
  Future<void> postMessage(String message);
}

/// Binds a [JsApiDispatcher] to a WebView-like bidirectional text channel.
///
/// Call [handleIncoming] from the host JavaScriptChannel callback and [start]
/// after the channel has been registered. The host owns the session lifecycle
/// and must call [dispose] when its WebView is disposed.
class JsBridgeSession {
  JsBridgeSession({
    required JsApiDispatcher dispatcher,
    required JsBridgeTransport transport,
  }) : _dispatcher = dispatcher,
       _transport = transport;

  final JsApiDispatcher _dispatcher;
  final JsBridgeTransport _transport;
  StreamSubscription? _eventSubscription;

  void start() {
    _eventSubscription ??= _dispatcher.events.listen((event) {
      unawaited(_transport.postMessage(event.encode()));
    });
  }

  Future<void> handleIncoming(String message) async {
    await _transport.postMessage(await _dispatcher.handleRaw(message));
  }

  Future<void> dispose() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
  }
}
