import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/network/api_exception.dart';
import '../../auth/application/auth_controller.dart';
import '../../session/application/session_list_controller.dart';
import '../data/social_repository.dart';

final socialCurrentChatObjectProvider = Provider<({int? id, String? name})>(
  (ref) => ref.watch(
    sessionListControllerProvider.select(
      (state) => (id: state.currentOwner?.id, name: state.currentOwner?.name),
    ),
  ),
);

final socialIdentityProvider = ChangeNotifierProvider<SocialIdentityController>(
  (ref) {
    final account = ref.watch(
      authControllerProvider.select(
        (state) => (state.status, state.currentUser?.id),
      ),
    );
    final chat = ref.watch(socialCurrentChatObjectProvider);
    final controller = SocialIdentityController(
      ref.watch(socialRepositoryProvider),
      chatObjectId: chat.id,
      name: chat.name ?? '当前聊天身份',
    );
    if (account.$1 == AuthStatus.authenticated && chat.id != null) {
      Future.microtask(controller.load);
    }
    return controller;
  },
);

class SocialIdentityController extends ChangeNotifier {
  SocialIdentityController(
    this.repository, {
    required this.chatObjectId,
    required this.name,
  });
  final SocialRepository repository;
  final int? chatObjectId;
  final String name;
  SocialActor? actor;
  bool loading = false;
  String? error;
  int _generation = 0;
  bool _disposed = false;
  Future<SocialActor?>? _entering;

  /// Startup and identity-switch checks are read-only. Never call getMyActor.
  Future<void> load() async {
    await _run(null);
  }

  Future<SocialActor?> enter({bool create = false}) =>
      _entering ??= _run(create).whenComplete(() => _entering = null);

  Future<SocialActor?> _run(bool? create) async {
    if (_disposed || chatObjectId == null) return null;
    final generation = ++_generation;
    // Keep the current actor while revalidating the same ChatObject.
    // Replacing it with null destroys the retained feed and its session.
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result =
          create == null
              ? await repository.getChatObjectActor(chatObjectId!)
              : await repository.resolveChatObject(
                chatObjectId!,
                create: create,
              );
      if (_disposed || generation != _generation) return null;
      actor = result;
      return result;
    } catch (failure) {
      if (!_disposed && generation == _generation) {
        actor = null;
        error =
            failure is ApiException ? failure.message : 'Social 身份加载失败，请稍后重试。';
      }
      return null;
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
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
