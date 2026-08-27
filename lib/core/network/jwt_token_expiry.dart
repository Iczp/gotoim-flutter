import 'dart:convert';

DateTime? readJwtExpiry(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    if (payload is! Map) return null;
    final raw = payload['exp'];
    final seconds = raw is num ? raw.toInt() : int.tryParse('$raw');
    return seconds == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  } catch (_) {
    return null;
  }
}

bool shouldRefreshJwt(
  String token, {
  DateTime? now,
  Duration refreshBefore = const Duration(minutes: 5),
}) {
  final expiry = readJwtExpiry(token);
  if (expiry == null) return false;
  return !expiry.isAfter((now ?? DateTime.now()).toUtc().add(refreshBefore));
}
