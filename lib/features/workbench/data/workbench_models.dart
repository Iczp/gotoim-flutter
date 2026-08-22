/// Data models for workbench dynamic applications.
///
/// These models are shared between the workbench UI, the task manager,
/// and the diagnostics center. They are deliberately plain Dart classes
/// without code-gen dependencies so that the MiniApp lightweight bootstrap
/// can use them without pulling in the full build_runner toolchain.
library;

/// The type of a workbench application.
enum WorkbenchAppType {
  /// A web application loaded in a WebView container.
  web,

  /// A Flutter-native feature module (future).
  flutter,

  /// A platform-native application launched via intent/scheme (future).
  native,
}

/// How the application should be opened.
enum AppOpenMode {
  /// Open inside the current container (e.g. replace current WebView URL).
  current,

  /// Open as a Flutter page within the main app navigator.
  page,

  /// Open as an independent system task (Android Document Task).
  systemTask,
}

/// Authentication mode for a MiniApp.
enum MiniAppAuthMode {
  /// No authentication required.
  none,

  /// Silently inject credentials (future).
  silent,

  /// Require explicit user authorization (future).
  userAuthorization,
}

/// A workbench application entry returned by the server or local cache.
class WorkbenchApp {
  const WorkbenchApp({
    required this.appId,
    required this.name,
    required this.url,
    this.iconUrl,
    this.type = WorkbenchAppType.web,
    this.openMode = AppOpenMode.systemTask,
    this.reuseExisting = true,
    this.authMode = MiniAppAuthMode.none,
    this.sort = 0,
    this.enabled = true,
  });

  final String appId;
  final String name;
  final Uri url;
  final String? iconUrl;
  final WorkbenchAppType type;
  final AppOpenMode openMode;
  final bool reuseExisting;
  final MiniAppAuthMode authMode;
  final int sort;
  final bool enabled;

  WorkbenchApp copyWith({
    String? appId,
    String? name,
    Uri? url,
    String? iconUrl,
    WorkbenchAppType? type,
    AppOpenMode? openMode,
    bool? reuseExisting,
    MiniAppAuthMode? authMode,
    int? sort,
    bool? enabled,
  }) =>
      WorkbenchApp(
        appId: appId ?? this.appId,
        name: name ?? this.name,
        url: url ?? this.url,
        iconUrl: iconUrl ?? this.iconUrl,
        type: type ?? this.type,
        openMode: openMode ?? this.openMode,
        reuseExisting: reuseExisting ?? this.reuseExisting,
        authMode: authMode ?? this.authMode,
        sort: sort ?? this.sort,
        enabled: enabled ?? this.enabled,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'appId': appId,
    'name': name,
    'url': url.toString(),
    'iconUrl': iconUrl,
    'type': type.name,
    'openMode': openMode.name,
    'reuseExisting': reuseExisting,
    'authMode': authMode.name,
    'sort': sort,
    'enabled': enabled,
  };

  factory WorkbenchApp.fromJson(Map<String, dynamic> json) => WorkbenchApp(
    appId: json['appId'] as String,
    name: json['name'] as String,
    url: Uri.parse(json['url'] as String),
    iconUrl: json['iconUrl'] as String?,
    type: WorkbenchAppType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => WorkbenchAppType.web,
    ),
    openMode: AppOpenMode.values.firstWhere(
      (e) => e.name == json['openMode'],
      orElse: () => AppOpenMode.systemTask,
    ),
    reuseExisting: json['reuseExisting'] as bool? ?? true,
    authMode: MiniAppAuthMode.values.firstWhere(
      (e) => e.name == json['authMode'],
      orElse: () => MiniAppAuthMode.none,
    ),
    sort: json['sort'] as int? ?? 0,
    enabled: json['enabled'] as bool? ?? true,
  );
}

/// Request to open a MiniApp as an independent system task.
class MiniAppTaskRequest {
  const MiniAppTaskRequest({
    required this.appId,
    required this.title,
    required this.url,
    this.iconUrl,
    this.reuseExisting = true,
    this.arguments,
  });

  final String appId;
  final String title;
  final Uri url;
  final String? iconUrl;
  final bool reuseExisting;
  final Map<String, String>? arguments;

  Map<String, Object?> toJson() => <String, Object?>{
    'appId': appId,
    'title': title,
    'url': url.toString(),
    if (iconUrl != null) 'iconUrl': iconUrl,
    'reuseExisting': reuseExisting,
    if (arguments != null) 'arguments': arguments,
  };
}

/// Payload delivered to a MiniApp when it receives a new intent / deep link.
class MiniAppLaunchRequest {
  const MiniAppLaunchRequest({
    required this.appId,
    required this.url,
    this.title,
    this.arguments,
  });

  final String appId;
  final Uri url;
  final String? title;
  final Map<String, String>? arguments;

  factory MiniAppLaunchRequest.fromJson(Map<String, dynamic> json) =>
      MiniAppLaunchRequest(
        appId: json['appId'] as String,
        url: Uri.parse(json['url'] as String),
        title: json['title'] as String?,
        arguments:
            json['arguments'] != null
                ? Map<String, String>.from(json['arguments'] as Map)
                : null,
      );
}
