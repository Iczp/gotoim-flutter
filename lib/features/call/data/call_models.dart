class CallJoinResultDto {
  const CallJoinResultDto({
    required this.callId,
    required this.sessionId,
    required this.stateVersion,
    required this.callMode,
    required this.mediaType,
    required this.roomName,
    required this.roomEpoch,
    required this.rtcUrl,
    required this.token,
    required this.iceTransportPolicy,
    this.expireAt,
  });

  final String callId;
  final String sessionId;
  final String stateVersion;
  final int callMode;
  final int mediaType;
  final String roomName;
  final int roomEpoch;
  final String rtcUrl;
  final String token;
  final String iceTransportPolicy;
  final int? expireAt;

  factory CallJoinResultDto.fromJson(Map<String, dynamic> json) {
    return CallJoinResultDto(
      callId: json['callId']?.toString() ?? '',
      sessionId: json['sessionId']?.toString() ?? '',
      stateVersion: json['stateVersion']?.toString() ?? '0',
      callMode: (json['callMode'] as num?)?.toInt() ?? 1,
      mediaType: (json['mediaType'] as num?)?.toInt() ?? 2,
      roomName: json['roomName']?.toString() ?? '',
      roomEpoch: (json['roomEpoch'] as num?)?.toInt() ?? 1,
      rtcUrl: json['rtcUrl']?.toString() ?? '',
      token: json['token']?.toString() ?? '',
      iceTransportPolicy: json['iceTransportPolicy']?.toString() ?? 'all',
      expireAt: (json['expireAt'] as num?)?.toInt(),
    );
  }
}

class CallHeartbeatResultDto {
  const CallHeartbeatResultDto({
    required this.serverTime,
    required this.stateVersion,
    required this.roomEpoch,
    required this.state,
  });

  final int serverTime;
  final String stateVersion;
  final int roomEpoch;
  final int state;

  factory CallHeartbeatResultDto.fromJson(Map<String, dynamic> json) {
    return CallHeartbeatResultDto(
      serverTime: (json['serverTime'] as num?)?.toInt() ?? 0,
      stateVersion: json['stateVersion']?.toString() ?? '0',
      roomEpoch: (json['roomEpoch'] as num?)?.toInt() ?? 1,
      state: (json['state'] as num?)?.toInt() ?? 1,
    );
  }
}
