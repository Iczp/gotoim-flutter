import '../data/models/app_version_dto.dart';

enum UpdateAction {
  installAndroidApk,
  installWindowsExe,
  installWindowsMsi,
  openUrl,
}

({UpdateAction action, Uri url}) planAppUpdate(
  AppVersionDto version, {
  required String platform,
}) {
  final package = version.pkgUrl?.trim() ?? '';
  final page = version.pageUrl?.trim() ?? '';
  final packageUrl = package.isEmpty ? null : checkedUpdateUrl(package);
  final isApk =
      packageUrl != null &&
      (packageUrl.path.toLowerCase().endsWith('.apk') ||
          packageUrl.queryParameters['contentType']?.toLowerCase() ==
              'application/vnd.android.package-archive');
  if (platform == 'android' && !version.isWidget && isApk) {
    return (action: UpdateAction.installAndroidApk, url: packageUrl);
  }
  if (platform == 'windows' && !version.isWidget && packageUrl != null) {
    final path = packageUrl.path.toLowerCase();
    if (path.endsWith('.exe')) {
      return (action: UpdateAction.installWindowsExe, url: packageUrl);
    }
    if (path.endsWith('.msi')) {
      return (action: UpdateAction.installWindowsMsi, url: packageUrl);
    }
  }
  final target = page.isNotEmpty ? page : package;
  if (target.isEmpty) throw StateError('未配置更新地址');
  return (action: UpdateAction.openUrl, url: checkedUpdateUrl(target));
}

Uri checkedUpdateUrl(String value) {
  if (value.contains('\\') || value.runes.any((c) => c < 32 || c == 127)) {
    throw const FormatException('更新地址必须是完整的 HTTP(S) 地址');
  }
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.userInfo.isNotEmpty) {
    throw const FormatException('更新地址必须是完整的 HTTP(S) 地址');
  }
  return uri;
}
