import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

Future<void> launchWindowsInstaller(String path, {required bool msi}) async {
  if (!Platform.isWindows) throw UnsupportedError('当前平台不支持 Windows 安装包');
  await Process.start(
    msi ? 'msiexec.exe' : path,
    msi ? ['/i', path] : const [],
    mode: ProcessStartMode.detached,
    runInShell: false,
  );
}

Future<void> openUpdateUrl(Uri url) async {
  if (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS) {
    await InAppBrowser.openWithSystemBrowser(url: WebUri(url.toString()));
    return;
  }
  final command = switch (defaultTargetPlatform) {
    TargetPlatform.windows => 'explorer.exe',
    TargetPlatform.macOS => 'open',
    TargetPlatform.linux => 'xdg-open',
    _ => throw UnsupportedError('当前平台不支持打开更新地址'),
  };
  if (defaultTargetPlatform == TargetPlatform.windows) {
    await Process.start(
      command,
      [url.toString()],
      mode: ProcessStartMode.detached,
      runInShell: false,
    );
    return;
  }
  final result = await Process.run(command, [
    url.toString(),
  ], runInShell: false);
  if (result.exitCode != 0) throw StateError('无法打开更新地址');
}
