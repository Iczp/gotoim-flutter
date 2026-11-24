import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/application_providers.dart';
import '../data/announcement_api.dart';
import '../data/models/session_announcement.dart';

final announcementApiProvider = Provider<AnnouncementApi>(
  (ref) => AnnouncementApi(ref.watch(apiClientProvider)),
);

class PinnedAnnouncementController extends ChangeNotifier {
  PinnedAnnouncementController(this._api, this.sessionId) {
    refresh();
  }

  final AnnouncementApi _api;
  final String sessionId;

  List<SessionAnnouncement> pinnedList = const [];
  int pinnedIndex = 0;
  SessionAnnouncement? get pinned =>
      pinnedList.isEmpty ? null : pinnedList[pinnedIndex.clamp(0, pinnedList.length - 1)];
  bool loading = false;
  bool isDismissed = false;

  Future<void> refresh() async {
    if (sessionId.isEmpty) return;
    loading = true;
    notifyListeners();
    try {
      pinnedList = await _api.getPinnedList(sessionId);
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
    if (item == null) return;
    try {
      await _api.confirm(item.id);
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
  AnnouncementListController(this._api, this.sessionId, {this.includeDrafts = false}) {
    loadList();
  }

  final AnnouncementApi _api;
  final String sessionId;
  final bool includeDrafts;

  List<SessionAnnouncement> items = const [];
  bool loading = false;

  Future<void> loadList() async {
    if (sessionId.isEmpty) return;
    loading = true;
    notifyListeners();
    try {
      items = await _api.getList(
        sessionId: sessionId,
        includeDrafts: includeDrafts,
        maxResultCount: 100,
      );
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> togglePin(SessionAnnouncement item) async {
    final newPinned = !item.isPinned;
    await _api.setPinned(id: item.id, isPinned: newPinned);
    await loadList();
  }

  Future<void> delete(String id) async {
    await _api.delete(id);
    items = items.where((element) => element.id != id).toList(growable: false);
    notifyListeners();
  }
}

class AnnouncementStatController extends ChangeNotifier {
  AnnouncementStatController(this._api, this.announcementId) {
    initialize();
  }

  final AnnouncementApi _api;
  final String announcementId;

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
    loadingStat = true;
    notifyListeners();
    try {
      stat = await _api.getStat(announcementId);
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
    loadingMembers = true;
    notifyListeners();
    final skipCount = reset ? 0 : members.length;
    try {
      final res = await _api.getMembers(
        id: announcementId,
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
