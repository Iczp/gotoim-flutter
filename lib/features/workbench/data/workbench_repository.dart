import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'workbench_models.dart';

/// Data source for workbench applications.
///
/// The first implementation uses in-memory mock data. When the backend API
/// is ready, swap to an `ApiWorkbenchRepository` that fetches from the
/// server and caches to Drift.
abstract interface class WorkbenchRepository {
  /// Returns the list of enabled workbench applications.
  ///
  /// When [forceRefresh] is true, bypasses any local cache and fetches
  /// from the upstream data source (currently the mock list).
  Future<List<WorkbenchApp>> getApps({bool forceRefresh = false});
}

/// Mock implementation for development and diagnostics.
///
/// Supports dynamic add/remove so the diagnostics page can verify that
/// new applications work without modifying the Android Manifest.
class MockWorkbenchRepository implements WorkbenchRepository {
  MockWorkbenchRepository() : _apps = List<WorkbenchApp>.of(_defaultApps);

  static final List<WorkbenchApp> _defaultApps = <WorkbenchApp>[
    WorkbenchApp(
      appId: 'crm',
      name: 'CRM',
      url: Uri.parse('https://crm.gotoim.com'),
      sort: 10,
    ),
    WorkbenchApp(
      appId: 'oa',
      name: 'OA',
      url: Uri.parse('https://oa.gotoim.com'),
      sort: 20,
    ),
  ];

  final List<WorkbenchApp> _apps;

  @override
  Future<List<WorkbenchApp>> getApps({bool forceRefresh = false}) async {
    // Simulate network latency on force refresh.
    if (forceRefresh) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return List<WorkbenchApp>.unmodifiable(
      _apps.where((app) => app.enabled).toList()
        ..sort((a, b) => a.sort.compareTo(b.sort)),
    );
  }

  /// Adds a workbench app dynamically (for diagnostics testing).
  void addApp(WorkbenchApp app) {
    _apps.removeWhere((existing) => existing.appId == app.appId);
    _apps.add(app);
  }

  /// Removes a workbench app by [appId] (for diagnostics testing).
  bool removeApp(String appId) {
    final before = _apps.length;
    _apps.removeWhere((app) => app.appId == appId);
    return _apps.length < before;
  }

  /// Resets to the default app list.
  void reset() {
    _apps
      ..clear()
      ..addAll(_defaultApps);
  }
}

final workbenchRepositoryProvider = Provider<WorkbenchRepository>(
  (ref) => throw UnimplementedError(
    'WorkbenchRepository must be provided at bootstrap.',
  ),
);
