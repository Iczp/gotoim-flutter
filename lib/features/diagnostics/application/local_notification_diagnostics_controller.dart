import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/application_providers.dart';
import '../../../core/notifications/local_notification_service.dart';

enum LocalNotificationTestStatus { idle, working, success, failure }

class LocalNotificationDiagnosticEntry {
  const LocalNotificationDiagnosticEntry({
    required this.receivedAt,
    required this.actionId,
    required this.payload,
  });

  final DateTime receivedAt;
  final String? actionId;
  final String payload;
}

class LocalNotificationDiagnosticsController extends ChangeNotifier {
  LocalNotificationDiagnosticsController(this._service) {
    _tapSubscription = _service.tapEvents.listen(_onTapEvent);
  }

  final LocalNotificationService _service;
  late final StreamSubscription<LocalNotificationTapEvent> _tapSubscription;
  final List<LocalNotificationDiagnosticEntry> _tapEvents =
      <LocalNotificationDiagnosticEntry>[];

  LocalNotificationTestStatus _permissionStatus =
      LocalNotificationTestStatus.idle;
  LocalNotificationTestStatus _dispatchStatus =
      LocalNotificationTestStatus.idle;
  LocalNotificationTestStatus _cancelStatus = LocalNotificationTestStatus.idle;
  String? _permissionResult;
  String? _dispatchResult;
  String? _cancelResult;
  String? _error;

  LocalNotificationSupport get support => _service.support;
  LocalNotificationTestStatus get permissionStatus => _permissionStatus;
  LocalNotificationTestStatus get dispatchStatus => _dispatchStatus;
  LocalNotificationTestStatus get cancelStatus => _cancelStatus;
  String? get permissionResult => _permissionResult;
  String? get dispatchResult => _dispatchResult;
  String? get cancelResult => _cancelResult;
  String? get error => _error;
  List<LocalNotificationDiagnosticEntry> get tapEvents =>
      List<LocalNotificationDiagnosticEntry>.unmodifiable(_tapEvents);

  Future<void> requestPermission() async {
    _permissionStatus = LocalNotificationTestStatus.working;
    _error = null;
    notifyListeners();
    try {
      final result = await _service.requestPermission();
      _permissionResult = '${result.status.name}: ${result.message}';
      _permissionStatus = LocalNotificationTestStatus.success;
    } catch (error) {
      _permissionStatus = LocalNotificationTestStatus.failure;
      _error = _safeError(error);
    }
    notifyListeners();
  }

  Future<void> show(LocalNotificationRequest request) async {
    _dispatchStatus = LocalNotificationTestStatus.working;
    _error = null;
    notifyListeners();
    try {
      final result = await _service.show(request);
      _dispatchResult = '${result.status.name}: ${result.message}';
      _dispatchStatus = LocalNotificationTestStatus.success;
    } catch (error) {
      _dispatchStatus = LocalNotificationTestStatus.failure;
      _error = _safeError(error);
    }
    notifyListeners();
  }

  Future<void> cancel(int id) async {
    _cancelStatus = LocalNotificationTestStatus.working;
    _error = null;
    notifyListeners();
    try {
      await _service.cancel(id);
      _cancelResult = '已取消通知 ID=$id（包括尚未触发的进程内延迟任务）。';
      _cancelStatus = LocalNotificationTestStatus.success;
    } catch (error) {
      _cancelStatus = LocalNotificationTestStatus.failure;
      _error = _safeError(error);
    }
    notifyListeners();
  }

  Future<void> cancelAll() async {
    _cancelStatus = LocalNotificationTestStatus.working;
    _error = null;
    notifyListeners();
    try {
      await _service.cancelAll();
      _cancelResult = '已取消全部通知和全部进程内延迟任务。';
      _cancelStatus = LocalNotificationTestStatus.success;
    } catch (error) {
      _cancelStatus = LocalNotificationTestStatus.failure;
      _error = _safeError(error);
    }
    notifyListeners();
  }

  void clearTapEvents() {
    _tapEvents.clear();
    notifyListeners();
  }

  void _onTapEvent(LocalNotificationTapEvent event) {
    _tapEvents.insert(
      0,
      LocalNotificationDiagnosticEntry(
        receivedAt: event.receivedAt,
        actionId: event.actionId,
        payload: event.payload,
      ),
    );
    if (_tapEvents.length > 100) _tapEvents.removeLast();
    notifyListeners();
  }

  String _safeError(Object error) => error.toString();

  @override
  void dispose() {
    _tapSubscription.cancel();
    super.dispose();
  }
}

final localNotificationDiagnosticsControllerProvider =
    ChangeNotifierProvider<LocalNotificationDiagnosticsController>((ref) {
  return LocalNotificationDiagnosticsController(
    ref.watch(localNotificationServiceProvider),
  );
});
