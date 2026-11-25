import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/application_providers.dart';
import '../data/announcement_api.dart';
import '../data/models/session_announcement.dart';

final announcementApiProvider = Provider<AnnouncementApi>(
  (ref) => AnnouncementApi(ref.watch(apiClientProvider)),
);

class PinnedAnnouncementController extends ChangeNotifier {
  PinnedAnnouncementController(
    this._api,
    this.sessionId, {
    this.sessionUnitId,
  }) {
    refresh();
  }

  final AnnouncementApi _api;
  final String sessionId;
  final String? sessionUnitId;

  String get _effectiveSessionUnitId =>
      (sessionUnitId != null && sessionUnitId!.isNotEmpty)
          ? sessionUnitId!
          : sessionId;

  List<SessionAnnouncement> pinnedList = const [];
  int pinnedIndex = 0;
  SessionAnnouncement? get pinned =>
      pinnedList.isEmpty ? null : pinnedList[pinnedIndex.clamp(0, pinnedList.length - 1)];
  bool loading = false;
  bool isDismissed = false;

  Future<void> loadPinned() => refresh();

  Future<void> refresh() async {
    final uid = _effectiveSessionUnitId;
    if (uid.isEmpty) return;
    loading = true;
    notifyListeners();
    try {
      pinnedList = await _api.getPinnedList(uid);
      pinnedIndex = 0;
      isDismissed = false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void prevPinned() {
    if (pinnedList.length <= 1) return;
    pinnedIndex = (pinnedIndex - 1 + pinnedList.length) % pinnedList.length;
    notifyListeners();
  }

  void nextPinned() {
    if (pinnedList.length <= 1) return;
    pinnedIndex = (pinnedIndex + 1) % pinnedList.length;
    notifyListeners();
  }

  void dismiss() {
    isDismissed = true;
    notifyListeners();
  }

  Future<void> confirm() async {
    final item = pinned;
    final uid = _effectiveSessionUnitId;
    if (item == null || uid.isEmpty) return;
    try {
      await _api.confirm(item.id, sessionUnitId: uid);
      final updated = item.copyWith(
        isSelfConfirmed: true,
        confirmedCount: item.confirmedCount + 1,
      );
      pinnedList = [
        for (var i = 0; i < pinnedList.length; i++)
          if (i == pinnedIndex) updated else pinnedList[i],
      ];
      notifyListeners();
    } catch (_) {}
  }
}

class AnnouncementListController extends ChangeNotifier {
  AnnouncementListController(
    this._api,
    this.sessionId, {
    this.sessionUnitId,
    this.includeDrafts = false,
    this.statusFilter,
  }) {
    loadList();
  }

  final AnnouncementApi _api;
  final String sessionId;
  final String? sessionUnitId;
  final bool includeDrafts;
  final int? statusFilter;

  String get _effectiveSessionUnitId {
    if (sessionUnitId != null && sessionUnitId!.isNotEmpty) {
      return sessionUnitId!;
    }
    if (permissions?.sessionUnitId.isNotEmpty == true) {
      return permissions!.sessionUnitId;
    }
    return sessionId;
  }

  List<SessionAnnouncement> items = const [];
  SessionAnnouncementPermissions? permissions;
  bool loading = false;

  Future<void> loadList() async {
    final uid = _effectiveSessionUnitId;
    if (uid.isEmpty) return;
    loading = true;
    notifyListeners();
    try {
      final results = await Future.wait([
        _api.getList(
          sessionUnitId: uid,
          includeDrafts: includeDrafts,
          status: statusFilter,
          maxResultCount: 100,
        ),
        _api.getPermissions(uid),
      ]);
      items = results[0] as List<SessionAnnouncement>;
      permissions = results[1] as SessionAnnouncementPermissions?;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> togglePin(SessionAnnouncement item) async {
    final unitId = _effectiveSessionUnitId;
    if (unitId.isEmpty) {
      throw StateError('缺少当前会话成员身份 ID');
    }
    final newPinned = !item.isPinned;
    await _api.setPinned(
      id: item.id,
      sessionUnitId: unitId,
      isPinned: newPinned,
    );
    await loadList();
  }

  Future<void> submitReview(String id) async {
    final unitId = _effectiveSessionUnitId;
    if (unitId.isEmpty) {
      throw StateError('缺少当前会话成员身份 ID');
    }
    await _api.submitReview(id, sessionUnitId: unitId);
    await loadList();
  }

  Future<void> review(
    String id, {
    required bool approved,
    String? remark,
    bool sendMessageNotification = true,
  }) async {
    final unitId = _effectiveSessionUnitId;
    if (unitId.isEmpty) {
      throw StateError('缺少当前会话成员身份 ID');
    }
    await _api.review(
      id,
      sessionUnitId: unitId,
      approved: approved,
      remark: remark,
      sendMessageNotification: sendMessageNotification,
    );
    await loadList();
  }

  Future<void> publish(String id) async {
    final unitId = _effectiveSessionUnitId;
    if (unitId.isEmpty) {
      throw StateError('缺少当前会话成员身份 ID');
    }
    await _api.publish(id, sessionUnitId: unitId);
    await loadList();
  }

  Future<void> revoke(String id) async {
    final unitId = _effectiveSessionUnitId;
    if (unitId.isEmpty) {
      throw StateError('缺少当前会话成员身份 ID');
    }
    await _api.revoke(id, sessionUnitId: unitId);
    await loadList();
  }

  Future<int> remindUnconfirmed(String id) async {
    final unitId = _effectiveSessionUnitId;
    if (unitId.isEmpty) return 0;
    return await _api.remindUnconfirmed(id, sessionUnitId: unitId);
  }

  Future<void> delete(String id) async {
    final unitId = _effectiveSessionUnitId;
    if (unitId.isEmpty) {
      throw StateError('缺少当前会话成员身份 ID');
    }
    await _api.delete(id, sessionUnitId: unitId);
    items = items.where((element) => element.id != id).toList(growable: false);
    notifyListeners();
  }
}

class AnnouncementStatController extends ChangeNotifier {
  AnnouncementStatController(
    this._api,
    this.announcementId, {
    this.sessionUnitId = '',
  }) {
    initialize();
  }

  final AnnouncementApi _api;
  final String announcementId;
  final String sessionUnitId;

  SessionAnnouncementStat? stat;
  List<SessionAnnouncementMember> members = const [];
  int totalCount = 0;
  bool loadingStat = false;
  bool loadingMembers = false;
  int activeFilterType = 0; // 0: All, 1: Read, 2: Unread, 3: Confirmed
  String keyword = '';

  Future<void> initialize() async {
    await Future.wait([
      loadStat(),
      loadMembers(reset: true),
    ]);
  }

  Future<void> loadStat() async {
    if (sessionUnitId.isEmpty) return;
    loadingStat = true;
    notifyListeners();
    try {
      stat = await _api.getStat(announcementId, sessionUnitId: sessionUnitId);
    } finally {
      loadingStat = false;
      notifyListeners();
    }
  }

  Future<void> setFilterType(int type) async {
    if (activeFilterType == type) return;
    activeFilterType = type;
    await loadMembers(reset: true);
  }

  Future<void> setKeyword(String text) async {
    keyword = text;
    await loadMembers(reset: true);
  }

  Future<void> loadMembers({bool reset = false}) async {
    if (sessionUnitId.isEmpty) return;
    loadingMembers = true;
    notifyListeners();
    final skipCount = reset ? 0 : members.length;
    try {
      final res = await _api.getMembers(
        id: announcementId,
        sessionUnitId: sessionUnitId,
        filterType: activeFilterType,
        keyword: keyword.isEmpty ? null : keyword,
        skipCount: skipCount,
        maxResultCount: 50,
      );
      if (reset) {
        members = res.items;
      } else {
        members = [...members, ...res.items];
      }
      totalCount = res.totalCount;
    } finally {
      loadingMembers = false;
      notifyListeners();
    }
  }
}
