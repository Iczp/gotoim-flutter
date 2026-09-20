import 'dart:async';

/// Application-level real-time transport boundary.
///
/// Repositories own event-to-database synchronization; UI never listens to a
/// SignalR client directly.
abstract class SignalRGateway {
  Stream<SignalRAppEvent> get events;

  SignalRConnectionState get connectionState;

  SignalRConnectionInfo get connectionInfo;

  Object? get lastError;

  String? get lastErrorDescription;

  Future<void> connect();

  Future<void> disconnect();

  /// 快速重连（例如网络切换或强制重置连接时调用，避免等待旧 Socket 超时）。
  Future<void> restart({bool fast = true});

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
    this.lastError,
    this.lastErrorDescription,
  });

  final String hubUrl;
  final SignalRConnectionState state;
  final String? connectionId;
  final Duration keepAliveInterval;
  final Duration serverTimeout;
  final DateTime? lastReceivedAt;
  final Object? lastError;
  final String? lastErrorDescription;
}

String formatSignalRError(Object? error) {
  if (error == null) return '';
  final msg = error.toString();
  if (msg.contains('401') || msg.contains('Unauthorized')) {
    return '认证失败 (HTTP 401)：登录凭据或 Token 已失效，请重新登录。';
  }
  if (msg.contains('502') || msg.contains('Bad Gateway')) {
    return '网关错误 (HTTP 502)：后端服务或 SignalR Hub 网关暂不可用。';
  }
  if (msg.contains('500') || msg.contains('Internal Server Error')) {
    return '服务端内部错误 (HTTP 500)：服务器处理实时长连接时出现异常。';
  }
  if (msg.contains('Failed host lookup') ||
      msg.contains('SocketException') ||
      msg.contains('Network is unreachable')) {
    return '网络异常或无法解析主机：设备未连网或无法访问该域名。';
  }
  if (msg.contains('Connection refused')) {
    return '连接被拒绝：目标端口未开放或后端 SignalR 服务未启动。';
  }
  if (msg.contains('timed out') || msg.contains('TimeoutException')) {
    return '连接超时：网络延时过大或服务端响应超时。';
  }
  if (msg.contains('Handshake') || msg.contains('handshake')) {
    return 'SignalR 握手失败：协议版本不匹配或凭证校验异常。';
  }
  return msg;
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
  aiStarted('started@ai'),
  aiDelta('delta@ai'),
  aiCompleted('completed@ai'),
  aiFailed('failed@ai'),
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
    return where(
      (event) => event is SignalRCommandEvent,
    ).cast<SignalRCommandEvent>().where((event) => event.command == command);
  }
}
