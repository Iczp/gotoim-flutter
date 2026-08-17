import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'platform_contract.dart';

export 'platform_contract.dart';
export 'platform_facade_stub.dart'
    if (dart.library.io) 'platform_facade_io.dart'
    if (dart.library.html) 'platform_facade_web.dart';

final Provider<PlatformFacade> platformFacadeProvider =
    Provider<PlatformFacade>(
  (ref) =>
      throw UnimplementedError('PlatformFacade must be provided at bootstrap.'),
);
