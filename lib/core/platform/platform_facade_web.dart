import 'platform_contract.dart';

PlatformFacade createPlatformFacade() => const _WebPlatformFacade();

class _WebPlatformFacade implements PlatformFacade {
  const _WebPlatformFacade();

  @override
  PlatformKind get kind => PlatformKind.web;

  @override
  bool get isWeb => true;

  @override
  bool get supportsMultipleWindows => false;

  @override
  bool get supportsNativeFilePaths => false;
}
