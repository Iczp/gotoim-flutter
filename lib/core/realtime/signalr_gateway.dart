import 'dart:async';

/// Application-level real-time transport boundary.
///
/// Repositories own event-to-database synchronization; UI never listens to a
/// SignalR client directly.
abstract class SignalRGateway {
  Stream<SignalRAppEvent> get events;

  SignalRConnectionState get connectionState;

  SignalRConnectionInfo get connectionInfo;

  Future<void> connect();

  Future<void> disconnect();

  Future<T?> invoke<T>(String method, {List<Object>? arguments});

  Future<void> dispose();
}

enum SignalRConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  disconnecting,
}

class SignalRConnectionInfo {
  const SignalRConnectionInfo({
    required this.hubUrl,
    required this.state,
    required this.connectionId,
    required this.keepAliveInterval,
    required this.serverTimeout,
    this.lastReceivedAt,
  });

  final String hubUrl;
  final SignalRConnectionState state;
  final String? connectionId;
  final Duration keepAliveInterval;
  final Duration serverTimeout;
  final DateTime? lastReceivedAt;
}

enum SignalRCommand {
  offlineMe('offline@me'),
  onlineMe('online@me'),
  offlineFriend('offline@friend'),
  onlineFriend('online@friend'),
  messageCreated('created@message'),
  messageForwarded('forwarded@message'),
  messageUpdated('updated@message'),
  messageBadgeUpdated('updated-badge@message'),
  messageRollbacked('rollbacked@message'),
  kicked('kicked'),
  welcome('welcome'),
  sessionUnitChanged('changed@session-unit');

  const SignalRCommand(this.value);
  final String value;

  static SignalRCommand? fromValue(String value) {
    for (final command in SignalRCommand.values) {
      if (command.value == value) return command;
    }
    return null;
  }
}

abstract class SignalRAppEvent {
  const SignalRAppEvent(this.receivedAt);
  final DateTime receivedAt;
}

class SignalRCommandEvent extends SignalRAppEvent {
  const SignalRCommandEvent({
    required this.command,
    required this.envelope,
    required DateTime receivedAt,
  }) : super(receivedAt);

  final SignalRCommand command;
  final Map<String, dynamic> envelope;

  Object? get payload => envelope['payload'];
  List<Object?> get scopes =>
      (envelope['scopes'] as List?)?.cast<Object?>() ?? const [];
}

class SignalRUnknownCommandEvent extends SignalRAppEvent {
  const SignalRUnknownCommandEvent({
    required this.command,
    required this.envelope,
    required DateTime receivedAt,
  }) : super(receivedAt);

  final String? command;
  final Map<String, dynamic> envelope;
}

class SignalRConnectionEvent extends SignalRAppEvent {
  const SignalRConnectionEvent({
    required this.state,
    required DateTime receivedAt,
    this.error,
    this.connectionId,
  }) : super(receivedAt);

  final SignalRConnectionState state;
  final Object? error;
  final String? connectionId;
}

extension SignalRCommandEvents on Stream<SignalRAppEvent> {
  Stream<SignalRCommandEvent> forCommand(SignalRCommand command) {
    return where((event) => event is SignalRCommandEvent)
        .cast<SignalRCommandEvent>()
        .where((event) => event.command == command);
  }
}
