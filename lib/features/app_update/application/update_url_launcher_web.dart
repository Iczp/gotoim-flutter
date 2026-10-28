// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

Future<void> launchWindowsInstaller(String path, {required bool msi}) =>
    throw UnsupportedError('当前平台不支持 Windows 安装包');

Future<void> openUpdateUrl(Uri url) async {
  final location = globalContext['location'] as JSObject?;
  if (location == null) throw StateError('无法打开更新地址');
  location.callMethod('assign'.toJS, url.toString().toJS);
}
