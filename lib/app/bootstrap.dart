import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform/platform_facade.dart';
import 'app.dart';

void bootstrap() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    ProviderScope(
      overrides: [
        platformFacadeProvider.overrideWithValue(createPlatformFacade()),
      ],
      child: const GotoImApp(),
    ),
  );
}
