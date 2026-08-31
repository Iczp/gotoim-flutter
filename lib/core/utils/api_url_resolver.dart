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
