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
  try {
    await dotenv.load(fileName: '.env.${flavor.name}');
  } catch (_) {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {}
  }

  final environment = AppEnvironment.fromDotEnv(flavor);
  final platformFacade = createPlatformFacade();

  // Get initial launch payload from native side.
  const channel = MethodChannel('com.gotoim.mini_app');

  MiniAppLaunchRequest? initialRequest;
  try {
    final payload = await channel.invokeMapMethod<String, dynamic>(
      'getLaunchPayload',
    );
    if (payload != null) {
      initialRequest = MiniAppLaunchRequest(
        appId: payload['appId'] as String? ?? '',
        url: Uri.parse(payload['url'] as String? ?? ''),
        title: payload['title'] as String?,
      );
    }
  } catch (e) {
    debugPrint('[MiniApp] Failed to get launch payload: $e');
  }

  runApp(
    MiniAppApp(
      environment: environment,
      platformFacade: platformFacade,
      initialRequest: initialRequest,
      channel: channel,
    ),
  );
}
