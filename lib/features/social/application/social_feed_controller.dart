import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/logging/app_logger.dart';
import '../../auth/application/auth_controller.dart';
import 'social_identity_controller.dart';
import '../data/social_repository.dart';

final socialFeedControllerProvider = ChangeNotifierProvider.family<
  SocialFeedController,
  bool
>((ref, diagnostics) {
  // Dispose account-bound actor/cursor state when the user changes or logs out.
  ref.watch(
    authControllerProvider.select(
      (auth) => (auth.status, auth.currentUser?.id),
    ),
  );
  final actorId = ref.watch(
    socialIdentityProvider.select((state) => state.actor?.id),
  );
  final actor = actorId == null ? null : ref.read(socialIdentityProvider).actor;
  final controller = SocialFeedController(
    ref.watch(socialRepositoryProvider),
    actor: actor,
  );
  if (actor != null) Future.microtask(controller.refresh);
  return controller;
});

class SocialFeedController extends ChangeNotifier {
  SocialFeedController(this._repository, {this.actor});
  final SocialRepository _repository;
  SocialActor? actor;
  List<SocialPost> items = [];
  bool following = false;
  bool loading = false;
  bool hasMore = false;
  bool isPartial = false;
  String? error;
  int pageSize = 20;
  int? elapsedMs;
  String? _cursor;
  String _requestId = const Uuid().v4();
  int _generation = 0;
  String? _pendingRequestId;
  DateTime? retryAt;
  bool _disposed = false;
  final Map<bool, _FeedSnapshot> _snapshots = {};
  String? _recommendationRequest;
  bool _sessionExpired = false;
  bool showingPreviousFeed = false;
  Timer? _cooldownTimer;
  int get retrySeconds =>
      retryAt == null
          ? 0
          : ((retryAt!.difference(DateTime.now()).inMilliseconds + 999) ~/ 1000)
              .clamp(0, 900);

  void _save() {
    _snapshots[following] = _FeedSnapshot(
      List.of(items),
      _cursor,
      hasMore,
      isPartial,
      _requestId,
    );
  }

  void _restore(_FeedSnapshot snapshot) {
    items = List.of(snapshot.items);
    _cursor = snapshot.cursor;
    hasMore = snapshot.hasMore;
    isPartial = snapshot.isPartial;
    _requestId = snapshot.requestId;
  }

  void _log(String event, {Map<String, Object?> context = const {}}) {
    AppLogger.instance.info(
      'Social feed $event',
      category: 'social-feed',
      event: event,
      context: {'feed': following ? 'following' : 'for-you', ...context},
    );
  }

  Future<void> refresh({bool? followingFeed}) async {
    final target = followingFeed ?? following;
    if (followingFeed != null && target == following) {
      _log('tab_reselected');
      return;
    }
    if (followingFeed != null && target != following) {
      if (!showingPreviousFeed &&
          (items.isNotEmpty ||
              _cursor != null ||
              _snapshots.containsKey(following))) {
        _save();
      }
      ++_generation;
      following = target;
      loading = false;
      error = null;
      retryAt = null;
      _pendingRequestId = null;
      final saved = _snapshots[target];
      if (saved != null) {
        showingPreviousFeed = false;
        _restore(saved);
        _log('tab_restored', context: {'itemCount': items.length});
        notifyListeners();
        return;
      }
      showingPreviousFeed = items.isNotEmpty;
      _cursor = null;
      hasMore = false;
      isPartial = false;
    } else if (loading ||
        (retryAt != null && DateTime.now().isBefore(retryAt!))) {
      return;
    }
    _pendingRequestId ??=
        following
            ? const Uuid().v4()
            : (_recommendationRequest ??= const Uuid().v4());
    _log(
      'load_start',
      context: {'requestId': _pendingRequestId, 'reset': true},
    );
    await _load(++_generation, reset: true);
  }

  Future<void> loadMore() async {
    if (loading ||
        !hasMore ||
        _cursor == null ||
        (retryAt != null && DateTime.now().isBefore(retryAt!))) {
      return;
    }
    await _load(_generation);
  }

  Future<void> retry() async {
    if (retryAt != null && DateTime.now().isBefore(retryAt!)) return;
    if (_sessionExpired) {
      _sessionExpired = false;
      await refresh();
    } else if (_pendingRequestId != null) {
      await _load(++_generation, reset: true);
    } else if (items.isEmpty) {
      await _load(_generation);
    } else {
      await loadMore();
    }
  }

  Future<void> _load(int generation, {bool reset = false}) async {
    if (_disposed || loading) return;
    loading = true;
    error = null;
    notifyListeners();
    final timer = Stopwatch()..start();
    final requestedCursor = reset ? null : _cursor;
    final requestedFeed = following;
    final requestId = reset ? _pendingRequestId! : _requestId;
    try {
      final viewer = actor;
      if (viewer == null) {
        throw const ApiException('请先创建当前 ChatObject 的 Social 身份。');
      }
      final page = await _repository.getFeed(
        actorId: viewer.id,
        following: requestedFeed,
        clientRequestId: requestId,
        cursor: requestedCursor,
        pageSize: pageSize,
      );
      if (_disposed || generation != _generation) return;
      if (reset) {
        items = [];
        showingPreviousFeed = false;
        _requestId = requestId;
        _pendingRequestId = null;
      }
      retryAt = null;
      final ids = items.map((post) => post.id).toSet();
      items = [...items, ...page.items.where((post) => ids.add(post.id))];
      _cursor = page.nextCursor;
      hasMore =
          page.hasMore &&
          _cursor != null &&
          _cursor!.isNotEmpty &&
          _cursor != requestedCursor;
      isPartial = page.isPartial;
      _save();
      _log(
        'load_success',
        context: {
          'requestId': requestId,
          'itemCount': page.items.length,
          'elapsedMs': timer.elapsedMilliseconds,
        },
      );
    } catch (failure) {
      if (_disposed || generation != _generation) return;
      if (failure is ApiException &&
          failure.statusCode == 410 &&
          !requestedFeed) {
        _recommendationRequest = null;
        _sessionExpired = true;
        _pendingRequestId = null;
        _snapshots.remove(false);
        _log('session_expired', context: {'requestId': requestId});
      }
      if (failure is ApiException && failure.statusCode == 429) {
        final wait = failure.retryAfter ?? const Duration(seconds: 5);
        retryAt = DateTime.now().add(wait);
        _cooldownTimer?.cancel();
        _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (_disposed || retrySeconds == 0) timer.cancel();
          if (!_disposed) notifyListeners();
        });
        _log(
          'rate_limited',
          context: {
            'requestId': requestId,
            'status': failure.statusCode,
            'code': failure.code,
            'retryAfterSeconds': wait.inSeconds,
          },
        );
        error = '请求过于频繁，请等待 ${wait.inSeconds} 秒后重试。';
      } else {
        error =
            failure is ApiException ? failure.message : 'Social 加载失败，请检查网络后重试。';
      }
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        elapsedMs = timer.elapsedMilliseconds;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cooldownTimer?.cancel();
    _generation++;
    super.dispose();
  }
}

class _FeedSnapshot {
  _FeedSnapshot(
    this.items,
    this.cursor,
    this.hasMore,
    this.isPartial,
    this.requestId,
  );
  final List<SocialPost> items;
  final String? cursor;
  final bool hasMore;
  final bool isPartial;
  final String requestId;
}
