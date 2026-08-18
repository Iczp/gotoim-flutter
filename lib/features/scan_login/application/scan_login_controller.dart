import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/application_providers.dart';
import '../../../core/config/app_environment.dart';
import '../data/http_scan_login_repository.dart';
import '../domain/scan_login_models.dart';
import '../domain/scan_login_repository.dart';

class ScanLoginController extends ChangeNotifier {
  ScanLoginController(this._repository, this.scanText);

  final ScanLoginRepository _repository;
  final String scanText;
  ScanLoginRequest? _request;
  Object? _error;
  bool _loading = false;
  bool _submitting = false;
  bool _completed = false;

  ScanLoginRequest? get request => _request;
  Object? get error => _error;
  bool get loading => _loading;
  bool get submitting => _submitting;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _request = await _repository.inspect(scanText);
    } catch (error) {
      _error = error;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> grant() => _submit(() => _repository.grant(scanText));

  Future<bool> reject() => _submit(() => _repository.reject(scanText));

  Future<bool> _submit(Future<void> Function() action) async {
    if (_submitting || _request == null || !_request!.canAuthorize) {
      return false;
    }
    _submitting = true;
    _error = null;
    notifyListeners();
    try {
      await action();
      _completed = true;
      return true;
    } catch (error) {
      _error = error;
      return false;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  Future<void> cancelIfNeeded() async {
    final connectionId = _request?.connectionId;
    if (_completed || connectionId == null || connectionId.isEmpty) return;
    _completed = true;
    try {
      await _repository.cancel(connectionId, reason: 'User cancelled');
    } catch (_) {
      // Closing the local confirmation screen must not be blocked by a
      // best-effort cancellation network failure.
    }
  }
}

final scanLoginRepositoryProvider = Provider<ScanLoginRepository>((ref) {
  return HttpScanLoginRepository(
    ref.watch(apiClientProvider),
    scanLoginTemplate: ref.watch(appEnvironmentProvider).scanLoginTemplate,
  );
});

final scanLoginControllerProvider = ChangeNotifierProvider.autoDispose
    .family<ScanLoginController, String>((ref, scanText) {
  final controller = ScanLoginController(
    ref.watch(scanLoginRepositoryProvider),
    scanText,
  );
  ref.onDispose(controller.cancelIfNeeded);
  return controller;
});
