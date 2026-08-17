import 'platform_contract.dart';

PlatformFacade createPlatformFacade() => const _StubPlatformFacade();

class _StubPlatformFacade implements PlatformFacade {
  const _StubPlatformFacade();

  @override
  PlatformKind get kind => PlatformKind.unknown;

  @override
  bool get isWeb => false;

  @override
  bool get supportsMultipleWindows => false;

  @override
  bool get supportsNativeFilePaths => false;
}
