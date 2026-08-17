enum PlatformKind { android, ios, windows, macos, linux, web, unknown }

abstract class PlatformFacade {
  PlatformKind get kind;

  bool get isWeb;

  bool get supportsMultipleWindows;

  bool get supportsNativeFilePaths;
}
