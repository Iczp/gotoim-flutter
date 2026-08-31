import 'connected_terminal.dart';

enum LocalFileServerStatus { stopped, starting, running, failed, unsupported }

class LocalFileServerState {
  const LocalFileServerState({
    required this.status,
    this.address,
    this.qrLoginUrl,
    this.verificationCode,
    this.error,
    this.terminals = const [],
  });

  const LocalFileServerState.stopped()
    : status = LocalFileServerStatus.stopped,
      address = null,
      qrLoginUrl = null,
      verificationCode = null,
      error = null,
      terminals = const [];

  final LocalFileServerStatus status;
  final String? address;
  final String? qrLoginUrl;
  final String? verificationCode;
  final String? error;
  final List<ConnectedTerminal> terminals;

  LocalFileServerState copyWith({
    LocalFileServerStatus? status,
    String? address,
    String? qrLoginUrl,
    String? verificationCode,
    String? error,
    List<ConnectedTerminal>? terminals,
  }) => LocalFileServerState(
    status: status ?? this.status,
    address: address ?? this.address,
    qrLoginUrl: qrLoginUrl ?? this.qrLoginUrl,
    verificationCode: verificationCode ?? this.verificationCode,
    error: error,
    terminals: terminals ?? this.terminals,
  );
}
