import 'dart:convert';

Map<String, dynamic> asMap(Object? value) {
  if (value is Map) {
    return value.cast<String, dynamic>();
  }
  return const <String, dynamic>{};
}

int? asInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value');

DateTime? asDate(Object? value) {
  if (value is String) return DateTime.tryParse(value)?.toLocal();
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt()).toLocal();
  }
  return null;
}

String firstNonEmpty(List<Object?> values) {
  for (final value in values) {
    final text = value?.toString().trim() ?? '';
    if (text.isNotEmpty) {
      return text;
    }
  }
  return '';
}

String messagePreview(Object? content) {
  if (content is String) return content.trim();
  if (content is Map) {
    return firstNonEmpty(<Object?>[
      content['text'],
      content['content'],
      content['message'],
    ]);
  }
  return content?.toString().trim() ?? '';
}

String messageContentType(Map<String, dynamic> message) {
  if (message['isRollbacked'] == true || message['rollbackTime'] != null) {
    return '';
  }
  return switch (asInt(message['messageType'])) {
    1 => '[系统]',
    2 => '[图片]',
    3 => '[语音]',
    4 => '[视频]',
    5 => '[文件]',
    6 => '[链接]',
    7 => '[位置]',
    8 => '[名片]',
    10 => '[HTML]',
    12 => '[聊天记录]',
    _ => '',
  };
}

String messageContentText(Map<String, dynamic> message) {
  if (message['isRollbacked'] == true || message['rollbackTime'] != null) {
    return '消息已撤回';
  }
  final content = asMap(message['content']);
  return switch (asInt(message['messageType'])) {
    0 || 1 => firstNonEmpty([content['text'], content['content']]),
    3 => content['time']?.toString() ?? '',
    5 => content['fileName']?.toString() ?? '',
    6 => content['url']?.toString() ?? '',
    10 || 12 => content['title']?.toString() ?? '',
    null => messagePreview(message['content']),
    _ => '',
  };
}

Map<String, dynamic> decodeJsonObject(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw const FormatException('Friends.raw is not an object');
  }
  return decoded.cast<String, dynamic>();
}

String encodeJson(Map<String, dynamic> value) => jsonEncode(value);

int? millis(Object? value) => asDate(value)?.millisecondsSinceEpoch;
