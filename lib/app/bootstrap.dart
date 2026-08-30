import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_environment.dart';
import '../core/capabilities/client_capability_service.dart';
import '../core/device/client_device_context.dart';
import '../core/database/unified_database.dart';
import '../core/deep_link/deep_link_handler.dart';
import '../core/deep_link/deep_link_parser.dart';
import '../core/deep_link/deep_link_service.dart';
import '../core/devtools/remote_debug/remote_dev_server.dart';
import '../core/jsbridge/js_api_dispatcher.dart';
import '../core/logging/app_logger.dart';
import '../core/notifications/local_notification_service.dart';
import '../core/platform/platform_facade.dart';
import '../core/services/clipboard_service.dart';
import '../core/services/file/file_picker_service.dart';
import '../core/services/file/file_upload_service.dart';
import '../core/services/media/media_service.dart';
import '../core/services/scan/scan_code_service.dart';
import '../core/services/task/app_task_manager.dart';
import '../core/services/task/app_task_manager_android.dart';
import '../core/services/task/app_task_manager_stub.dart';
import '../features/workbench/data/workbench_repository.dart';
import 'app.dart';
import 'app_navigation.dart';
import 'application_providers.dart';
import 'bootstrap_error_app.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    const flavorName = String.fromEnvironment(
      'APP_ENV',
      defaultValue: 'development',
    );
    final flavor = AppEnvironment.parseFlavor(flavorName);
    try {
      await dotenv.load(fileName: '.env.${flavor.name}');
    } catch (dotenvError) {
      debugPrint('Warning: Could not load .env.${flavor.name}: $dotenvError');
      try {
        await dotenv.load(fileName: '.env');
      } catch (_) {}
    }
    final environment = AppEnvironment.fromDotEnv(flavor);
    // The server is deliberately created, but not started, at bootstrap. A
    // developer must explicitly start it from the diagnostics center.
    final remoteDevServer = RemoteDevServer();
    try {
      environment.validate();
    } catch (validationError) {
      debugPrint('Warning: Environment validation: $validationError');
    }
    final platformFacade = createPlatformFacade();
    final deviceContext = await ClientDeviceContextFactory().create(
      environment: environment,
      platformFacade: platformFacade,
    );
    final localNotificationService = createLocalNotificationService(
      platformFacade: platformFacade,
    );
    try {
      await localNotificationService.initialize();
    } catch (e) {
      debugPrint('Warning: Notification service initialization failed: $e');
    }
    final database = UnifiedDatabase.openDefault();
    try {
      await database.initialize();
    } catch (e) {
      debugPrint('Warning: Database initialization failed: $e');
    }
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
    final appTaskManager = platformFacade.kind == PlatformKind.android
        ? AndroidAppTaskManager()
        : StubAppTaskManager(
            navigatorProvider: () => rootNavigatorKey.currentState,
          );
    final workbenchRepository = MockWorkbenchRepository();
    final deepLinkParser = DeepLinkParser(
      allowedCustomSchemes: environment.deepLinkCustomSchemes,
      allowedHosts: environment.deepLinkAllowedHosts,
    );
    final deepLinkHandler = DeepLinkHandler(
      navigatorProvider: () => rootNavigatorKey.currentState,
      workbenchRepositoryProvider: () => workbenchRepository,
      appTaskManagerProvider: () => appTaskManager,
    );
    final deepLinkService = DeepLinkService(
      parser: deepLinkParser,
      handler: deepLinkHandler,
    );
    try {
      await deepLinkService.initialize();
    } catch (e) {
      debugPrint('Warning: Deep link service initialization failed: $e');
    }

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
          appTaskManagerProvider.overrideWithValue(appTaskManager),
          workbenchRepositoryProvider.overrideWithValue(workbenchRepository),
          deepLinkServiceProvider.overrideWith((ref) => deepLinkService),
          remoteDevServerProvider.overrideWithValue(remoteDevServer),
        ],
        child: const GotoImApp(),
      ),
    );
  } catch (error, stackTrace) {
    AppLogger.instance.fatal(
      'Application bootstrap error',
      category: 'bootstrap',
      event: 'bootstrap_error',
      error: error,
      stackTrace: stackTrace,
    );
    debugPrint('Fatal bootstrap error: $error\n$stackTrace');
    runApp(BootstrapErrorApp(error: error, stackTrace: stackTrace));
  }
}
