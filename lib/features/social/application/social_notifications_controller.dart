import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/network/api_exception.dart';
import '../../auth/application/auth_controller.dart';
import 'social_identity_controller.dart';
import '../data/social_repository.dart';

final socialNotificationsProvider =
    ChangeNotifierProvider<SocialNotificationsController>((ref) {
      final account = ref.watch(
        authControllerProvider.select(
          (auth) => (auth.status, auth.currentUser?.id),
        ),
      );
      final actor = ref.watch(
        socialIdentityProvider.select((state) => state.actor),
      );
      final controller = SocialNotificationsController(
        ref.watch(socialRepositoryProvider),
        actor: actor,
      );
      if (account.$1 == AuthStatus.authenticated && actor != null) {
        Future.microtask(controller.start);
      }
      return controller;
    });

class SocialNotificationsController extends ChangeNotifier
    with WidgetsBindingObserver {
  SocialNotificationsController(
    this._repository, {
    this.actor,
    this.pollInterval = const Duration(seconds: 30),
  });
  final SocialRepository _repository;
  final Duration pollInterval;
  int unreadCount = 0;
  int newMessageVersion = 0;
  bool hasSnapshot = false;
  bool loading = false;
  bool marking = false;
  String? error;
  String? unreadError;
  List<SocialNotification> items = [];
  bool hasMore = false;
  SocialActor? actor;
  Future<void>? _unreadRequest;
  String? _cursor;
  Timer? _timer;
  bool _started = false;
  bool _foreground = true;
  bool _disposed = false;
  int _listGeneration = 0;

  Future<SocialActor> _viewer() async {
    final result = actor;
    if (result == null) {
      throw const ApiException('请先创建当前 ChatObject 的 Social 身份。');
    }
    return result;
  }

  void start() {
    if (_disposed || _started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    didChangeAppLifecycleState(
      WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _timer?.cancel();
    _timer = null;
    if (_disposed || state != AppLifecycleState.resumed) return;
    unawaited(refreshUnread());
    _timer = Timer.periodic(pollInterval, (_) => unawaited(refreshUnread()));
  }

  Future<void> refreshUnread() {
    if (_disposed) return Future.value();
    return _unreadRequest ??= _refreshUnread().whenComplete(
      () => _unreadRequest = null,
    );
  }

  Future<void> _refreshUnread() async {
    try {
      final viewer = await _viewer();
      if (_disposed) return;
      final count = await _repository.getUnreadCount(viewer.id);
      if (_disposed) return;
      if (_foreground && hasSnapshot && count > unreadCount) {
        newMessageVersion++;
      }
      unreadCount = count < 0 ? 0 : count;
      hasSnapshot = true;
      unreadError = null;
    } catch (failure) {
      if (_disposed) return;
      unreadError = _message(failure);
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> load({bool more = false}) async {
    if (_disposed || loading || (more && !hasMore)) return;
    loading = true;
    final generation = _listGeneration;
    error = null;
    notifyListeners();
    try {
      final viewer = await _viewer();
      if (_disposed) return;
      final cursor = more ? _cursor : null;
      final page = await _repository.getNotifications(
        viewer.id,
        cursor: cursor,
      );
      if (_disposed || generation != _listGeneration) return;
      final existing = more ? items : <SocialNotification>[];
      final ids = existing.map((item) => item.id).toSet();
      items = [...existing, ...page.items.where((item) => ids.add(item.id))];
      _cursor = page.nextCursor;
      hasMore =
          page.hasMore &&
          _cursor != null &&
          _cursor!.isNotEmpty &&
          _cursor != cursor;
      unawaited(refreshUnread());
    } catch (failure) {
      if (!_disposed) error = _message(failure);
    } finally {
      if (!_disposed) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> markRead({String? id}) async {
    if (_disposed || marking) return false;
    marking = true;
    error = null;
    notifyListeners();
    try {
      final viewer = await _viewer();
      if (_disposed) return false;
      if (id == null) {
        await _repository.markAllNotificationsRead(viewer.id);
      } else {
        await _repository.markNotificationRead(id);
      }
      if (_disposed) return false;
      _listGeneration++;
      items =
          items
              .map((item) => id == null || item.id == id ? item.read() : item)
              .toList();
      // Finish an older poll before fetching the canonical count after this mutation.
      await _unreadRequest;
      await refreshUnread();
      return true;
    } catch (failure) {
      if (!_disposed) error = _message(failure);
      return false;
    } finally {
      if (!_disposed) {
        marking = false;
        notifyListeners();
      }
    }
  }

  String _message(Object failure) =>
      failure is ApiException ? failure.message : 'Social 通知加载失败，请稍后重试。';

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    if (_started) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
