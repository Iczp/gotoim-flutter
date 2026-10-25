import 'desktop_window_capabilities.dart';

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

// Keep capability discovery additive: existing PlatformFacade implementations
// (including downstream integrations and test doubles) remain source-compatible.
extension DesktopPlatformCapabilities on PlatformFacade {
  DesktopWindowCapabilities get desktopCapabilities {
    if (isWeb) return DesktopWindowCapabilities.fallback('Web');
    return switch (kind) {
      PlatformKind.windows => DesktopWindowCapabilities.windows(),
      PlatformKind.macos => DesktopWindowCapabilities.macos(),
      PlatformKind.linux => DesktopWindowCapabilities.linux(),
      _ => DesktopWindowCapabilities.fallback(kind.name),
    };
  }
}
