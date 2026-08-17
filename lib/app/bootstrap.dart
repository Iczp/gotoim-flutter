import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_environment.dart';
import '../core/platform/platform_facade.dart';
import 'app.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  const flavorName = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );
  final flavor = AppEnvironment.parseFlavor(flavorName);
  await dotenv.load(fileName: '.env.${flavor.name}');
  final environment = AppEnvironment.fromDotEnv(flavor);
  environment.validate();

  runApp(
    ProviderScope(
      overrides: [
        appEnvironmentProvider.overrideWithValue(environment),
        platformFacadeProvider.overrideWithValue(createPlatformFacade()),
      ],
      child: const GotoImApp(),
    ),
  );
}
