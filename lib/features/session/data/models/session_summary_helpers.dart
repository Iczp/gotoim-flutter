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

Map<String, dynamic> decodeJsonObject(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw const FormatException('Friends.raw is not an object');
  }
  return decoded.cast<String, dynamic>();
}

String encodeJson(Map<String, dynamic> value) => jsonEncode(value);

int? millis(Object? value) => asDate(value)?.millisecondsSinceEpoch;
