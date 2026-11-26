/// Resolves a backend-relative URL against the configured API base URL.
///
/// File URLs and fully qualified URLs are kept unchanged so callers can use
/// the same helper for avatar, image, video, and audio resources.
String resolveApiUrl(String? source, String apiBaseUrl) {
  final value = source?.trim() ?? '';
  if (value.isEmpty) return '';
  final uri = Uri.tryParse(value);
  if (uri?.hasScheme == true || apiBaseUrl.isEmpty) return value;
  return Uri.parse(apiBaseUrl).resolve(value).toString();
}

/// Resolves a media/attachment URL and appends access context query parameters
/// (`su`, `msg`, `rootMsg`) when missing on protected `/api/chat/file/` or `/file` endpoints.
String resolveAttachmentUrl(
  String? source,
  String apiBaseUrl, {
  String? sessionUnitId,
  int? messageId,
  int? rootMessageId,
}) {
  final resolved = resolveApiUrl(source, apiBaseUrl);
  if (resolved.isEmpty) return '';
  final uri = Uri.tryParse(resolved);
  if (uri == null) return resolved;
  final pathLower = uri.path.toLowerCase();
  final isChatFileRoute =
      pathLower.contains('/api/chat/file/') ||
      pathLower == '/file' ||
      pathLower.endsWith('/file');
  if (!isChatFileRoute) return resolved;

  final query = Map<String, String>.from(uri.queryParameters);
  var changed = false;
  final su = sessionUnitId?.trim() ?? '';
  if (su.isNotEmpty && !query.containsKey('su')) {
    query['su'] = su;
    changed = true;
  }
  if (messageId != null && messageId > 0 && !query.containsKey('msg')) {
    query['msg'] = '$messageId';
    changed = true;
  }
  if (rootMessageId != null &&
      rootMessageId > 0 &&
      !query.containsKey('rootMsg')) {
    query['rootMsg'] = '$rootMessageId';
    changed = true;
  }
  return changed ? uri.replace(queryParameters: query).toString() : resolved;
}
