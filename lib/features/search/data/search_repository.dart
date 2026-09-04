import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/application_providers.dart';
import '../../../core/database/unified_database.dart';
import '../../contact/data/contact_api.dart';
import '../domain/search_models.dart';

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  final database = ref.watch(unifiedDatabaseProvider);
  final contactApi = ref.watch(contactApiProvider);
  return SearchRepository(database: database, contactApi: contactApi);
});

class SearchRepository {
  SearchRepository({
    required UnifiedDatabase database,
    required ContactApi contactApi,
  })  : _database = database,
        _contactApi = contactApi;

  final UnifiedDatabase _database;
  final ContactApi _contactApi;

  // ========== 历史记录 ==========

  Future<List<String>> getSearchHistory() => _database.readSearchHistory();

  Future<List<String>> addSearchHistory(String keyword) =>
      _database.addSearchKeyword(keyword);

  Future<List<String>> deleteSearchHistory(String keyword) =>
      _database.deleteSearchKeyword(keyword);

  Future<void> clearSearchHistory() => _database.clearSearchHistory();

  // ========== 本地搜索 ==========

  Future<List<SearchContactItem>> searchLocalContacts({
    required int ownerId,
    required String keyword,
  }) async {
    final rows = await _database.searchFriendRows(
      ownerId: ownerId,
      keyword: keyword,
    );

    final results = <SearchContactItem>[];
    final term = keyword.trim().toLowerCase();

    for (final row in rows) {
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty) continue;

      String title = id;
      String? subtitle;
      String? avatarUrl;
      int? objectType;
      bool isRoom = false;

      final rawStr = row['raw'] as String?;
      if (rawStr != null && rawStr.isNotEmpty) {
        try {
          final json = jsonDecode(rawStr);
          if (json is Map) {
            final dest = json['destination'];
            if (dest is Map) {
              title = (dest['name'] ?? dest['displayName'] ?? json['displayName'] ?? id).toString();
              avatarUrl = dest['portraitUrl']?.toString() ?? dest['avatar']?.toString();
              objectType = (dest['objectType'] as num?)?.toInt();
              isRoom = objectType == 2;
            } else {
              title = (json['displayName'] ?? json['name'] ?? id).toString();
              avatarUrl = json['portraitUrl']?.toString();
            }

            final lastMsg = json['lastMessage'];
            if (lastMsg is Map) {
              subtitle = lastMsg['text']?.toString();
            }
          }
        } catch (_) {}
      }

      // 验证标题或副标题是否匹配关键字
      if (title.toLowerCase().contains(term) ||
          (subtitle != null && subtitle.toLowerCase().contains(term))) {
        results.add(SearchContactItem(
          id: id,
          ownerId: ownerId,
          title: title,
          subtitle: subtitle,
          avatarUrl: avatarUrl,
          objectType: objectType,
          isRoom: isRoom,
        ));
      }
    }

    return results;
  }

  Future<List<SearchMessageItem>> searchLocalMessages({
    required int ownerId,
    required String keyword,
  }) async {
    final rows = await _database.searchMessageRows(
      ownerId: ownerId,
      keyword: keyword,
    );

    final results = <SearchMessageItem>[];

    for (final row in rows) {
      final id = row['id']?.toString() ?? '';
      final sessionUnitId = row['sessionUnitId']?.toString() ?? '';
      final serverId = (row['serverId'] as num?)?.toInt();
      final sessionId = row['sessionId']?.toString();
      final createTimeMs = (row['createTime'] as num?)?.toInt();
      final timestamp = createTimeMs != null
          ? DateTime.fromMillisecondsSinceEpoch(createTimeMs)
          : null;

      String snippet = '';
      String? senderName;
      String? senderAvatarUrl;

      final rawStr = row['raw'] as String?;
      if (rawStr != null && rawStr.isNotEmpty) {
        try {
          final json = jsonDecode(rawStr);
          if (json is Map) {
            final text = (json['text'] ?? json['content'] ?? '').toString();
            snippet = _extractSnippet(text, keyword);
            senderName = (json['senderName'] ?? json['senderDisplayName'])?.toString();
            senderAvatarUrl = json['senderAvatar']?.toString();
          }
        } catch (_) {}
      }

      if (snippet.isEmpty) {
        snippet = keyword;
      }

      results.add(SearchMessageItem(
        id: id,
        sessionUnitId: sessionUnitId,
        serverId: serverId,
        sessionId: sessionId,
        sessionTitle: senderName,
        senderName: senderName,
        senderAvatarUrl: senderAvatarUrl,
        contentSnippet: snippet,
        matchedKeyword: keyword,
        timestamp: timestamp,
      ));
    }

    return results;
  }

  // ========== 线上搜索预览 ==========

  Future<List<SearchRemoteContactItem>> searchRemoteContacts({
    required int ownerId,
    required String keyword,
  }) async {
    try {
      final res = await _contactApi.searchContacts(
        ownerId: ownerId,
        keyword: keyword,
        maxResultCount: 20,
      );

      final items = res['items'];
      if (items is! List) return const <SearchRemoteContactItem>[];

      final results = <SearchRemoteContactItem>[];
      for (final item in items) {
        if (item is! Map) continue;
        final dest = item['destination'];
        final name = (dest is Map
                ? (dest['name'] ?? dest['displayName'])
                : (item['name'] ?? item['displayName']))
            ?.toString() ??
            '-';
        final avatar = (dest is Map
                ? (dest['portraitUrl'] ?? dest['avatar'])
                : (item['portraitUrl'] ?? item['avatar']))
            ?.toString();
        final objectType = ((dest is Map ? dest['objectType'] : item['objectType']) as num?)?.toInt();
        final objectTypeDesc = (dest is Map ? dest['objectTypeDescription'] : item['objectTypeDescription'])?.toString();
        final isFriend = item['isFriendship'] == true;
        final id = (item['id'] ?? dest?['id'] ?? '').toString();
        final code = (dest is Map ? dest['code'] : item['code'])?.toString();

        results.add(SearchRemoteContactItem(
          id: id,
          name: name,
          avatarUrl: avatar,
          objectType: objectType,
          objectTypeDescription: objectTypeDesc,
          isFriend: isFriend,
          code: code,
        ));
      }
      return results;
    } catch (_) {
      return const <SearchRemoteContactItem>[];
    }
  }

  String _extractSnippet(String text, String keyword) {
    if (text.isEmpty) return '';
    final lower = text.toLowerCase();
    final index = lower.indexOf(keyword.toLowerCase());
    if (index == -1) return text.length > 50 ? '${text.substring(0, 50)}...' : text;

    final start = (index - 15).clamp(0, text.length);
    final end = (index + keyword.length + 25).clamp(0, text.length);

    String snippet = text.substring(start, end);
    if (start > 0) snippet = '...$snippet';
    if (end < text.length) snippet = '$snippet...';
    return snippet;
  }
}
