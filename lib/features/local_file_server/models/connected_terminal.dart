enum TerminalStatus { online, idle, uploading, downloading, offline }

class TerminalActivity {
  const TerminalActivity({
    required this.occurredAt,
    required this.action,
    required this.description,
  });

  final DateTime occurredAt;
  final String action;
  final String description;
}

class ConnectedTerminal {
  const ConnectedTerminal({
    required this.id,
    required this.name,
    required this.platform,
    required this.ip,
    required this.connectedAt,
    required this.lastActiveAt,
    required this.status,
    this.transferLabel,
    this.receivedBytes,
    this.totalBytes,
  });

  final String id;
  final String name;
  final String platform;
  final String ip;
  final DateTime connectedAt;
  final DateTime lastActiveAt;
  final TerminalStatus status;
  final String? transferLabel;
  final int? receivedBytes;
  final int? totalBytes;

  ConnectedTerminal copyWith({
    DateTime? lastActiveAt,
    TerminalStatus? status,
    String? transferLabel,
    int? receivedBytes,
    int? totalBytes,
  }) => ConnectedTerminal(
    id: id,
    name: name,
    platform: platform,
    ip: ip,
    connectedAt: connectedAt,
    lastActiveAt: lastActiveAt ?? this.lastActiveAt,
    status: status ?? this.status,
    transferLabel: transferLabel,
    receivedBytes: receivedBytes,
    totalBytes: totalBytes,
  );
}
