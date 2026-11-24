import '../../../core/network/api_client.dart';
import 'models/session_announcement.dart';

class AnnouncementApi {
  AnnouncementApi(this._client);
  final ApiClient _client;

  Future<SessionAnnouncement?> getPinned(String sessionId) async {
    try {
      final json = await _client.get<Map<String, dynamic>>(
        '/api/chat/session-announcement/pinned',
        query: <String, Object?>{'sessionId': sessionId},
      );
      if (json.isEmpty || json['id'] == null) return null;
      return SessionAnnouncement.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<List<SessionAnnouncement>> getPinnedList(String sessionId) async {
    try {
      final res = await _client.get<List<dynamic>>(
        '/api/chat/session-announcement/pinned-list/$sessionId',
      );
      return res
          .whereType<Map<String, dynamic>>()
          .map(SessionAnnouncement.fromJson)
          .toList(growable: false);
    } catch (_) {
      final single = await getPinned(sessionId);
      return single != null ? [single] : const [];
    }
  }

  Future<List<SessionAnnouncement>> getList({
    required String sessionId,
    String? keyword,
    bool? isPinned,
    bool includeDrafts = false,
    int maxResultCount = 50,
    int skipCount = 0,
  }) async {
    try {
      final json = await _client.get<Map<String, dynamic>>(
        '/api/chat/session-announcement',
        query: <String, Object?>{
          'SessionId': sessionId,
          if (keyword != null && keyword.isNotEmpty) 'Keyword': keyword,
          if (isPinned != null) 'IsPinned': isPinned,
          if (includeDrafts) 'IncludeDrafts': true,
          'MaxResultCount': maxResultCount,
          'SkipCount': skipCount,
        },
      );
      final rawItems = json['items'];
      if (rawItems is List) {
        return rawItems
            .map((item) => SessionAnnouncement.fromJson(item as Map<String, dynamic>))
            .toList(growable: false);
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  Future<SessionAnnouncement?> getDetail(String id) async {
    try {
      final json = await _client.get<Map<String, dynamic>>(
        '/api/chat/session-announcement/$id',
      );
      return SessionAnnouncement.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<SessionAnnouncement> create({
    required String sessionId,
    required String title,
    required String content,
    int editorType = 0,
    bool isPinned = false,
    double? sorting,
    String? expireTime,
    String? publishTime,
    bool saveAsDraft = false,
    bool applyToNewMembers = false,
    bool isPopup = false,
    bool requireConfirm = false,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/api/chat/session-announcement',
      data: <String, Object?>{
        'sessionId': sessionId,
        'title': title,
        'content': content,
        'editorType': editorType,
        'isPinned': isPinned,
        'sorting': ?sorting,
        'expireTime': expireTime,
        'publishTime': publishTime,
        'saveAsDraft': saveAsDraft,
        'applyToNewMembers': applyToNewMembers,
        'isPopup': isPopup,
        'requireConfirm': requireConfirm,
      },
    );
    return SessionAnnouncement.fromJson(json);
  }

  Future<SessionAnnouncement> update({
    required String id,
    required String title,
    required String content,
    int editorType = 0,
    bool isPinned = false,
    double? sorting,
    String? expireTime,
    String? publishTime,
    bool saveAsDraft = false,
    bool resetReceipts = false,
    bool applyToNewMembers = false,
    bool isPopup = false,
    bool requireConfirm = false,
  }) async {
    final json = await _client.put<Map<String, dynamic>>(
      '/api/chat/session-announcement/$id',
      data: <String, Object?>{
        'title': title,
        'content': content,
        'editorType': editorType,
        'isPinned': isPinned,
        'sorting': ?sorting,
        'expireTime': expireTime,
        'publishTime': publishTime,
        'saveAsDraft': saveAsDraft,
        'resetReceipts': resetReceipts,
        'applyToNewMembers': applyToNewMembers,
        'isPopup': isPopup,
        'requireConfirm': requireConfirm,
      },
    );
    return SessionAnnouncement.fromJson(json);
  }

  Future<void> setPinned({
    required String id,
    required bool isPinned,
    double? sorting,
  }) async {
    await _client.post<dynamic>(
      '/api/chat/session-announcement/$id/pinned',
      query: <String, Object?>{
        'isPinned': isPinned,
        'sorting': ?sorting,
      },
    );
  }

  Future<void> delete(String id) async {
    await _client.delete<dynamic>('/api/chat/session-announcement/$id');
  }

  Future<SessionAnnouncement> publish(String id, {String? sessionUnitId}) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/api/chat/session-announcement/$id/publish',
      query: <String, Object?>{'sessionUnitId': ?sessionUnitId},
    );
    return SessionAnnouncement.fromJson(json);
  }

  Future<void> revoke(String id, {String? sessionUnitId}) async {
    await _client.post<dynamic>(
      '/api/chat/session-announcement/$id/revoke',
      query: <String, Object?>{'sessionUnitId': ?sessionUnitId},
    );
  }

  Future<int> remindUnconfirmed(String id, {required String sessionUnitId}) async {
    final res = await _client.post<dynamic>(
      '/api/chat/session-announcement/$id/remind-unconfirmed',
      data: <String, Object?>{'sessionUnitId': sessionUnitId},
    );
    return (res as num?)?.toInt() ?? 0;
  }

  Future<void> confirm(String id, {String? deviceId}) async {
    await _client.post<dynamic>(
      '/api/chat/session-announcement/$id/confirm',
      data: <String, Object?>{
        if (deviceId != null) 'deviceId': deviceId,
      },
    );
  }

  Future<void> recordView(String id, {String? deviceId}) async {
    await _client.post<dynamic>(
      '/api/chat/session-announcement/$id/view',
      data: <String, Object?>{
        if (deviceId != null) 'deviceId': deviceId,
      },
    );
  }

  Future<SessionAnnouncementStat> getStat(String id) async {
    final json = await _client.get<Map<String, dynamic>>(
      '/api/chat/session-announcement/$id/stat',
    );
    return SessionAnnouncementStat.fromJson(json);
  }

  Future<({int totalCount, List<SessionAnnouncementMember> items})> getMembers({
    required String id,
    int filterType = 0,
    String? keyword,
    int maxResultCount = 50,
    int skipCount = 0,
  }) async {
    try {
      final json = await _client.get<Map<String, dynamic>>(
        '/api/chat/session-announcement/$id/members',
        query: <String, Object?>{
          'FilterType': filterType,
          if (keyword != null && keyword.isNotEmpty) 'Keyword': keyword,
          'MaxResultCount': maxResultCount,
          'SkipCount': skipCount,
        },
      );
      final rawItems = json['items'];
      final totalCount = (json['totalCount'] as num?)?.toInt() ?? 0;
      if (rawItems is List) {
        final items = rawItems
            .map((item) => SessionAnnouncementMember.fromJson(item as Map<String, dynamic>))
            .toList(growable: false);
        return (totalCount: totalCount, items: items);
      }
      return (totalCount: 0, items: const <SessionAnnouncementMember>[]);
    } catch (_) {
      return (totalCount: 0, items: const <SessionAnnouncementMember>[]);
    }
  }
}
