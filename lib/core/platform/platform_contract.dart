enum PlatformKind { android, ios, windows, macos, linux, web, unknown }

abstract class PlatformFacade {
  const PlatformFacade();

  PlatformKind get kind;

  bool get isWeb;

  bool get supportsMultipleWindows;

  bool get supportsNativeFilePaths;

  bool get isDesktop =>
      kind == PlatformKind.windows ||
      kind == PlatformKind.macos ||
      kind == PlatformKind.linux;
}
