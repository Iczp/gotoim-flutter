import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_environment.dart';
import '../core/capabilities/client_capability_service.dart';
import '../core/device/client_device_context.dart';
import '../core/database/unified_database.dart';
import '../core/jsbridge/js_api_dispatcher.dart';
import '../core/notifications/local_notification_service.dart';
import '../core/platform/platform_facade.dart';
import '../core/services/clipboard_service.dart';
import '../core/services/file/file_picker_service.dart';
import '../core/services/file/file_upload_service.dart';
import '../core/services/media/media_service.dart';
import '../core/services/scan/scan_code_service.dart';
import 'app.dart';
import 'app_navigation.dart';
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
  final database = UnifiedDatabase.openDefault();
  await database.initialize();
  final mediaService = DefaultMediaService(platformFacade: platformFacade);
  final fileUploadService = DioFileUploadService(
    allowedHosts: environment.jsBridgeUploadAllowedHosts,
  );
  final capabilities = DefaultClientCapabilityService(
    environment: environment,
    deviceContext: deviceContext,
    platformFacade: platformFacade,
    clipboardService: SystemClipboardService(),
    filePickerService: SystemFilePickerService(),
    scanCodeService: const NavigatorScanCodeService(),
    imageCodeService: const ZxingImageCodeService(),
    mediaService: mediaService,
    localNotificationService: localNotificationService,
  );
  final jsApiDispatcher = JsApiDispatcher(
    capabilities: capabilities,
    navigatorProvider: () => rootNavigatorKey.currentState,
    uploadService: fileUploadService,
  );

  runApp(
    ProviderScope(
      overrides: [
        appEnvironmentProvider.overrideWithValue(environment),
        platformFacadeProvider.overrideWithValue(platformFacade),
        clientDeviceContextProvider.overrideWithValue(deviceContext),
        localNotificationServiceProvider.overrideWithValue(
          localNotificationService,
        ),
        clientCapabilityServiceProvider.overrideWithValue(capabilities),
        jsApiDispatcherProvider.overrideWithValue(jsApiDispatcher),
        unifiedDatabaseProvider.overrideWithValue(database),
        mediaServiceProvider.overrideWithValue(mediaService),
      ],
      child: const GotoImApp(),
    ),
  );
}
