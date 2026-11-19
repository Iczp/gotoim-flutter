/// Global auth header resolver for protected media endpoints (`/api/chat/file/`).
abstract final class MediaAuthHeaders {
  static Future<Map<String, String>> Function()? provider;

  static Future<Map<String, String>> resolveForUrl(String url) async {
    final fn = provider;
    if (fn == null || url.isEmpty) return const <String, String>{};
    try {
      return await fn();
    } catch (_) {
      return const <String, String>{};
    }
  }

  /// Appends `?su=<sessionUnitId>&msg=<serverMessageId>` when missing on `/api/chat/file/` URLs.
  static String withAccessContext(
    String url, {
    required String sessionUnitId,
    int? serverMessageId,
  }) {
    if (url.isEmpty || !url.contains('/api/chat/file/')) return url;
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final query = Map<String, String>.from(uri.queryParameters);
    if (sessionUnitId.isNotEmpty && !query.containsKey('su')) {
      query['su'] = sessionUnitId;
    }
    if (serverMessageId != null &&
        serverMessageId > 0 &&
        !query.containsKey('msg')) {
      query['msg'] = '$serverMessageId';
    }
    return uri.replace(queryParameters: query).toString();
  }
}
