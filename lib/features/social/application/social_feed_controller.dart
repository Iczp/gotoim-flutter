import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_exception.dart';
import '../../auth/application/auth_controller.dart';
import 'social_identity_controller.dart';
import '../data/social_repository.dart';

final socialFeedControllerProvider = ChangeNotifierProvider.autoDispose.family<
  SocialFeedController,
  bool
>((ref, diagnostics) {
  // Dispose account-bound actor/cursor state when the user changes or logs out.
  ref.watch(
    authControllerProvider.select(
      (auth) => (auth.status, auth.currentUser?.id),
    ),
  );
  final actor = ref.watch(
    socialIdentityProvider.select((state) => state.actor),
  );
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
  bool _disposed = false;

  Future<void> refresh({bool? followingFeed}) async {
    following = followingFeed ?? following;
    _generation++;
    _cursor = null;
    items = [];
    hasMore = false;
    _requestId = const Uuid().v4();
    await _load(_generation);
  }

  Future<void> loadMore() async {
    if (loading || !hasMore || _cursor == null) return;
    await _load(_generation);
  }

  Future<void> retry() => items.isEmpty ? _load(_generation) : loadMore();

  Future<void> _load(int generation) async {
    if (_disposed) return;
    loading = true;
    error = null;
    notifyListeners();
    final timer = Stopwatch()..start();
    final requestedCursor = _cursor;
    final requestedFeed = following;
    try {
      final viewer = actor;
      if (viewer == null) {
        throw const ApiException('请先创建当前 ChatObject 的 Social 身份。');
      }
      if (_disposed || generation != _generation) return;
      actor = viewer;
      final page = await _repository.getFeed(
        actorId: viewer.id,
        following: requestedFeed,
        clientRequestId: _requestId,
        cursor: requestedCursor,
        pageSize: pageSize,
      );
      if (_disposed || generation != _generation) return;
      final ids = items.map((post) => post.id).toSet();
      items = [...items, ...page.items.where((post) => ids.add(post.id))];
      _cursor = page.nextCursor;
      hasMore =
          page.hasMore &&
          _cursor != null &&
          _cursor!.isNotEmpty &&
          _cursor != requestedCursor;
      isPartial = page.isPartial;
    } catch (failure) {
      if (_disposed || generation != _generation) return;
      error =
          failure is ApiException ? failure.message : 'Social 加载失败，请检查网络后重试。';
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
    _generation++;
    super.dispose();
  }
}
