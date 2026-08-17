import 'dart:io' show Platform;

import 'platform_contract.dart';

PlatformFacade createPlatformFacade() => const _IoPlatformFacade();

class _IoPlatformFacade implements PlatformFacade {
  const _IoPlatformFacade();

  @override
  PlatformKind get kind {
    if (Platform.isAndroid) return PlatformKind.android;
    if (Platform.isIOS) return PlatformKind.ios;
    if (Platform.isWindows) return PlatformKind.windows;
    if (Platform.isMacOS) return PlatformKind.macos;
    if (Platform.isLinux) return PlatformKind.linux;
    return PlatformKind.unknown;
  }

  @override
  bool get isWeb => false;

  @override
  bool get supportsMultipleWindows =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  bool get supportsNativeFilePaths => true;
}
