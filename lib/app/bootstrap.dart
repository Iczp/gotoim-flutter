import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_environment.dart';
import '../core/device/client_device_context.dart';
import '../core/notifications/local_notification_service.dart';
import '../core/platform/platform_facade.dart';
import 'app.dart';
import 'application_providers.dart';

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
  final platformFacade = createPlatformFacade();
  final deviceContext = await ClientDeviceContextFactory().create(
    environment: environment,
    platformFacade: platformFacade,
  );
  final localNotificationService = createLocalNotificationService(
    platformFacade: platformFacade,
  );
  await localNotificationService.initialize();

  runApp(
    ProviderScope(
      overrides: [
        appEnvironmentProvider.overrideWithValue(environment),
        platformFacadeProvider.overrideWithValue(platformFacade),
        clientDeviceContextProvider.overrideWithValue(deviceContext),
        localNotificationServiceProvider.overrideWithValue(
          localNotificationService,
        ),
      ],
      child: const GotoImApp(),
    ),
  );
}
