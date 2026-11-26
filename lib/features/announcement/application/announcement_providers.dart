import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/application_providers.dart';
import '../../../core/database/unified_database.dart';
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
    UnifiedDatabase? database,
  }) : _database = database {
    refresh();
  }

  final AnnouncementApi _api;
  final String sessionId;
  final String? sessionUnitId;
  final UnifiedDatabase? _database;

  String get _effectiveSessionUnitId =>
      (sessionUnitId != null && sessionUnitId!.isNotEmpty)
          ? sessionUnitId!
          : sessionId;

  static String signatureOf(SessionAnnouncement item) =>
      '${item.version}|${item.title.trim()}';

  String get _dismissedKey =>
      'announcement-banner-dismissed:$_effectiveSessionUnitId';

  List<SessionAnnouncement> pinnedList = const [];
  int pinnedIndex = 0;
  SessionAnnouncement? get pinned =>
      pinnedList.isEmpty
          ? null
          : pinnedList[pinnedIndex.clamp(0, pinnedList.length - 1)];
  bool loading = false;
  bool get isDismissed => pinnedList.isEmpty;
  final Map<String, String> _dismissedSignatures = <String, String>{};
  bool _dismissedLoaded = false;
  bool _disposed = false;

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> ensureDismissedLoaded() async {
    if (_dismissedLoaded) return;
    _dismissedLoaded = true;
    final db = _database;
    if (db == null || _effectiveSessionUnitId.isEmpty) return;
    try {
      final raw = await db.readSettingValue(_dismissedKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          final k = entry.key?.toString() ?? '';
          final v = entry.value?.toString() ?? '';
          if (k.isNotEmpty && v.isNotEmpty) {
            _dismissedSignatures[k] = v;
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _persistDismissed() async {
    final db = _database;
    if (db == null || _effectiveSessionUnitId.isEmpty) return;
    await db.writeSettingValue(
      id: _dismissedKey,
      group: 'announcement-banner',
      value: jsonEncode(_dismissedSignatures),
    );
  }

  bool isDismissedItem(SessionAnnouncement item) =>
      _dismissedSignatures[item.id] == signatureOf(item);

  Future<void> loadPinned() => refresh();

  Future<void> refresh() async {
    final uid = _effectiveSessionUnitId;
    if (uid.isEmpty) return;
    loading = true;
    _safeNotify();
    try {
      await ensureDismissedLoaded();
      final raw = await _api.getPinnedList(uid);
      if (_disposed) return;
      pinnedList = raw.where((item) {
        if (item.isExpired || !item.isEffectiveForCurrentUser) return false;
        if (isDismissedItem(item)) return false;
        if (item.requireConfirm && item.isSelfConfirmed) return false;
        if (!item.requireConfirm && item.isSelfRead) return false;
        return true;
      }).toList(growable: false);
      if (pinnedList.isEmpty) {
        pinnedIndex = 0;
      } else if (pinnedIndex >= pinnedList.length) {
        pinnedIndex = pinnedList.length - 1;
      }
    } finally {
      loading = false;
      _safeNotify();
    }
  }

  void prevPinned() {
    if (pinnedList.length <= 1) return;
    pinnedIndex = (pinnedIndex - 1 + pinnedList.length) % pinnedList.length;
    _safeNotify();
  }

  void nextPinned() {
    if (pinnedList.length <= 1) return;
    pinnedIndex = (pinnedIndex + 1) % pinnedList.length;
    _safeNotify();
  }

  void dismiss() {
    final item = pinned;
    if (item == null) return;
    _dismissedSignatures[item.id] = signatureOf(item);
    pinnedList = pinnedList
        .where((e) => e.id != item.id)
        .toList(growable: false);
    if (pinnedList.isEmpty) {
      pinnedIndex = 0;
    } else if (pinnedIndex >= pinnedList.length) {
      pinnedIndex = pinnedList.length - 1;
    }
    _safeNotify();
    unawaited(_persistDismissed().catchError((_) {}));
  }

  Future<void> markViewed(SessionAnnouncement item) async {
    if (item.requireConfirm && !item.isSelfConfirmed) return;
    _dismissedSignatures[item.id] = signatureOf(item);
    pinnedList = pinnedList
        .where((e) => e.id != item.id)
        .toList(growable: false);
    if (pinnedList.isEmpty) {
      pinnedIndex = 0;
    } else if (pinnedIndex >= pinnedList.length) {
      pinnedIndex = pinnedList.length - 1;
    }
    _safeNotify();
    await _persistDismissed().catchError((_) {});
  }

  Future<void> confirm() async {
    final item = pinned;
    final uid = _effectiveSessionUnitId;
    if (item == null || uid.isEmpty) return;
    try {
      await _api.confirm(item.id, sessionUnitId: uid);
      _dismissedSignatures[item.id] = signatureOf(item);
      pinnedList = pinnedList
          .where((e) => e.id != item.id)
          .toList(growable: false);
      if (pinnedList.isEmpty) {
        pinnedIndex = 0;
      } else if (pinnedIndex >= pinnedList.length) {
        pinnedIndex = pinnedList.length - 1;
      }
      _safeNotify();
      await _persistDismissed().catchError((_) {});
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
    int initialFilterType = 0,
  }) : activeFilterType = initialFilterType.clamp(0, 4) {
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
  int activeFilterType; // 0: All, 1: Read, 2: Unread, 3: Confirmed, 4: Unconfirmed
  String keyword = '';
  int _membersRequestSeq = 0;
  bool _disposed = false;

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> initialize() async {
    await Future.wait([
      loadStat(),
      loadMembers(reset: true),
    ]);
  }

  Future<void> loadStat() async {
    if (sessionUnitId.isEmpty) return;
    loadingStat = true;
    _safeNotify();
    try {
      stat = await _api.getStat(announcementId, sessionUnitId: sessionUnitId);
    } finally {
      loadingStat = false;
      _safeNotify();
    }
  }

  Future<void> setFilterType(int type) async {
    final normalized = type.clamp(0, 4);
    if (activeFilterType == normalized) return;
    activeFilterType = normalized;
    await loadMembers(reset: true);
  }

  Future<void> setKeyword(String text) async {
    keyword = text;
    await loadMembers(reset: true);
  }

  Future<void> loadMembers({bool reset = false}) async {
    if (sessionUnitId.isEmpty) return;
    final seq = ++_membersRequestSeq;
    loadingMembers = true;
    _safeNotify();
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
      if (seq != _membersRequestSeq || _disposed) return;
      if (reset) {
        members = res.items;
      } else {
        members = [...members, ...res.items];
      }
      totalCount = res.totalCount;
    } finally {
      if (seq == _membersRequestSeq && !_disposed) {
        loadingMembers = false;
        _safeNotify();
      }
    }
  }
}
