import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/application_providers.dart';
import '../../session/data/models/session_summary.dart';
import '../../session/data/models/session_summary_helpers.dart';
import '../../session/data/repositories/session_repository.dart';
import '../data/datasources/chat_member_api.dart';
import '../data/datasources/chat_member_dao.dart';
import '../data/models/chat_member.dart';
import '../data/repositories/chat_settings_repository.dart';

final chatSettingsRepositoryProvider = Provider<ChatSettingsRepository>(
  (ref) => ChatSettingsRepository(
    api: ChatMemberApi(ref.watch(apiClientProvider)),
    dao: ChatMemberDao(ref.watch(unifiedDatabaseProvider)),
  ),
);

class ChatSettingsController extends ChangeNotifier {
  ChatSettingsController(
    this._repository,
    this._sessionRepository, {
    required this.ownerId,
    required this.sessionUnitId,
  });

  final ChatSettingsRepository _repository;
  final SessionRepository _sessionRepository;
  final int ownerId;
  final String sessionUnitId;
  final List<ChatMember> members = <ChatMember>[];
  SessionSummary? friend;
  bool loading = false;
  bool updating = false;
  Object? error;
  int totalCount = 0;

  String get title => friend?.title ?? '聊天设置';
  Map<String, dynamic> get setting => asMap(friend?.raw['setting']);
  bool get isTopping =>
      setting['isTopping'] == true || setting['isTop'] == true;
  bool get isImmersed => setting['isImmersed'] == true;
  int get objectType =>
      asInt(asMap(friend?.raw['destination'])['objectType']) ?? -1;
  String get objectTypeLabel => switch (objectType) {
    1 => '个人',
    2 => '群聊',
    3 => '服务号',
    4 => '订阅号',
    5 => '广场',
    6 => '机器人',
    7 => '掌柜',
    8 => '店小二',
    9 => '客户',
    _ => '未知',
  };

  Future<void> initialize() async {
    loading = true;
    notifyListeners();
    friend = await _sessionRepository.loadLocalFriendDetail(sessionUnitId);
    notifyListeners();
    try {
      final page = await _repository.loadMembers(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
        limit: 13,
      );
      members
        ..clear()
        ..addAll(page.items);
      totalCount =
          page.totalCount ??
          asInt(friend?.raw['sessionUnitCount']) ??
          members.length;
    } catch (exception) {
      error = exception;
    } finally {
      loading = false;
      notifyListeners();
    }
    unawaited(_refreshFriendSafely());
  }

  Future<void> refresh() async {
    error = null;
    loading = true;
    notifyListeners();
    try {
      await _refreshFriend();
      final page = await _repository.loadMembers(
        ownerId: ownerId,
        sessionUnitId: sessionUnitId,
        limit: 13,
        forceRemote: true,
      );
      members
        ..clear()
        ..addAll(page.items);
      totalCount = page.totalCount ?? members.length;
    } catch (exception) {
      error = exception;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _refreshFriend() async {
    friend = await _sessionRepository.loadRemoteFriendDetail(
      ownerId: ownerId,
      sessionUnitId: sessionUnitId,
    );
    notifyListeners();
  }

  Future<void> _refreshFriendSafely() async {
    try {
      await _refreshFriend();
    } catch (exception) {
      debugPrint(
        '[chatSettings][remote-friend-failed] session=$sessionUnitId '
        'keepLocal=${friend != null} error=$exception',
      );
    }
  }

  Future<void> setTopping(bool value) =>
      _updateSetting(() => _repository.setTopping(sessionUnitId, value));

  Future<void> setImmersed(bool value) =>
      _updateSetting(() => _repository.setImmersed(sessionUnitId, value));

  Future<void> _updateSetting(Future<void> Function() action) async {
    if (updating) return;
    updating = true;
    error = null;
    notifyListeners();
    try {
      await action();
      await _refreshFriend();
    } catch (exception) {
      error = exception;
    } finally {
      updating = false;
      notifyListeners();
    }
  }

  Future<void> clearMessages() =>
      _repository.clearMessages(ownerId, sessionUnitId);
}
