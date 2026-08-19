import 'dart:convert';

class JsBridgeRequest {
  const JsBridgeRequest({
    required this.id,
    required this.action,
    this.data = const <String, dynamic>{},
  });

  final String id;
  final String action;
  final Map<String, dynamic> data;

  factory JsBridgeRequest.parse(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const JsBridgeException('INVALID_REQUEST', '请求必须是 JSON 对象。');
    }
    final id = decoded['id'];
    final action = decoded['action'];
    final data = decoded['data'];
    if (id is! String || id.trim().isEmpty) {
      throw const JsBridgeException('INVALID_REQUEST', 'id 必须是非空字符串。');
    }
    if (action is! String || action.trim().isEmpty) {
      throw const JsBridgeException('INVALID_REQUEST', 'action 必须是非空字符串。');
    }
    if (data != null && data is! Map) {
      throw const JsBridgeException('INVALID_REQUEST', 'data 必须是对象。');
    }
    return JsBridgeRequest(
      id: id,
      action: action,
      data:
          data == null
              ? const <String, dynamic>{}
              : Map<String, dynamic>.from(data),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'action': action,
    'data': data,
  };
}

class JsBridgeResponse {
  const JsBridgeResponse.success({required this.id, required this.data})
    : success = true,
      error = null;

  const JsBridgeResponse.failure({required this.id, required this.error})
    : success = false,
      data = null;

  final String id;
  final bool success;
  final Object? data;
  final JsBridgeError? error;

  String encode() => jsonEncode(toJson());

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'success': success,
    if (success) 'data': data,
    if (!success) 'error': error!.toJson(),
  };
}

class JsBridgeError {
  const JsBridgeError({
    required this.code,
    required this.message,
    this.details,
  });

  final String code;
  final String message;
  final Object? details;

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'message': message,
    if (details != null) 'details': details,
  };
}

class JsBridgeException implements Exception {
  const JsBridgeException(this.code, this.message, {this.details});

  final String code;
  final String message;
  final Object? details;
}

class JsBridgeEvent {
  const JsBridgeEvent({required this.name, required this.data});

  final String name;
  final Map<String, Object?> data;

  String encode() => jsonEncode(toJson());

  Map<String, Object?> toJson() => <String, Object?>{
    'event': name,
    'data': data,
  };
}
