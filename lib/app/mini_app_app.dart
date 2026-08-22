import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/config/app_environment.dart';
import '../core/platform/platform_contract.dart';
import '../features/workbench/data/workbench_models.dart';
import '../features/workbench/presentation/mini_app_host_page.dart';

/// A lightweight [MaterialApp] for MiniApp FlutterEngines.
///
/// This does not use GoRouter or the full application shell. It directly
/// displays [MiniAppHostPage] with the launch payload received from native.
class MiniAppApp extends StatefulWidget {
  const MiniAppApp({
    required this.environment,
    required this.platformFacade,
    required this.channel,
    this.initialRequest,
    super.key,
  });

  final AppEnvironment environment;
  final PlatformFacade platformFacade;
  final MiniAppLaunchRequest? initialRequest;
  final MethodChannel channel;

  @override
  State<MiniAppApp> createState() => _MiniAppAppState();
}

class _MiniAppAppState extends State<MiniAppApp> {
  late MiniAppLaunchRequest? _currentRequest;

  @override
  void initState() {
    super.initState();
    _currentRequest = widget.initialRequest;

    // Listen for new intents (when an existing task is reactivated
    // with a different URL).
    widget.channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onLaunch':
      case 'onNewIntent':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        setState(() {
          _currentRequest = MiniAppLaunchRequest(
            appId: args['appId'] as String? ?? _currentRequest?.appId ?? '',
            url: Uri.parse(
              args['url'] as String? ??
                  _currentRequest?.url.toString() ??
                  '',
            ),
            title: args['title'] as String? ?? _currentRequest?.title,
          );
        });
        debugPrint(
          '[MiniApp] ${call.method} appId=${_currentRequest?.appId} '
          'url=${_currentRequest?.url}',
        );
    }
  }

  @override
  void dispose() {
    widget.channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: _currentRequest?.title ?? 'MiniApp',
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: _currentRequest != null
          ? MiniAppHostPage(
              request: _currentRequest!,
              channel: widget.channel,
            )
          : const Scaffold(
              body: Center(
                child: Text('Waiting for launch payload...'),
              ),
            ),
    );
  }
}
