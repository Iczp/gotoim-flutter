import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../core/config/app_environment.dart';
import '../core/platform/platform_facade.dart';
import '../features/workbench/data/workbench_models.dart';
import 'mini_app_app.dart';

/// Lightweight bootstrap for MiniApp FlutterEngines.
///
/// Only initializes: Theme, Localization, HTTP basics, WebView/JSBridge.
/// Does NOT start: SignalR, message sync, session sync, badge jobs,
/// or any main-app background services.
Future<void> miniAppBootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment for API base URLs (needed by WebView/JSBridge).
  const flavorName = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );
  final flavor = AppEnvironment.parseFlavor(flavorName);

  // Concurrently load environment and fetch native launch payload to minimize white screen.
  const channel = MethodChannel('com.gotoim.mini_app');

  final results = await Future.wait<dynamic>([
    () async {
      try {
        await dotenv.load(fileName: '.env.${flavor.name}');
      } catch (_) {
        try {
          await dotenv.load(fileName: '.env');
        } catch (_) {}
      }
      return AppEnvironment.fromDotEnv(flavor);
    }(),
    () async {
      try {
        final payload = await channel.invokeMapMethod<String, dynamic>(
          'getLaunchPayload',
        );
        if (payload != null) {
          return MiniAppLaunchRequest(
            appId: payload['appId'] as String? ?? '',
            url: Uri.parse(payload['url'] as String? ?? ''),
            title: payload['title'] as String?,
          );
        }
      } catch (e) {
        debugPrint('[MiniApp] Failed to get launch payload: $e');
      }
      return null;
    }(),
  ]);

  final environment = results[0] as AppEnvironment;
  final initialRequest = results[1] as MiniAppLaunchRequest?;
  final platformFacade = createPlatformFacade();

  runApp(
    MiniAppApp(
      environment: environment,
      platformFacade: platformFacade,
      initialRequest: initialRequest,
      channel: channel,
    ),
  );
}
