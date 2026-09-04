import 'package:flutter/foundation.dart';

/// 搜索匹配到的联系人/群聊
@immutable
class SearchContactItem {
  const SearchContactItem({
    required this.id,
    required this.title,
    this.ownerId,
    this.subtitle,
    this.avatarUrl,
    this.objectType,
    this.isRoom = false,
  });

  final String id;
  final int? ownerId;
  final String title;
  final String? subtitle;
  final String? avatarUrl;
  final int? objectType;
  final bool isRoom;
}

/// 搜索匹配到的聊天记录
@immutable
class SearchMessageItem {
  const SearchMessageItem({
    required this.id,
    required this.sessionUnitId,
    required this.contentSnippet,
    required this.matchedKeyword,
    this.serverId,
    this.sessionId,
    this.sessionTitle,
    this.senderName,
    this.senderAvatarUrl,
    this.timestamp,
  });

  final String id;
  final String sessionUnitId;
  final String contentSnippet;
  final String matchedKeyword;
  final int? serverId;
  final String? sessionId;
  final String? sessionTitle;
  final String? senderName;
  final String? senderAvatarUrl;
  final DateTime? timestamp;
}

/// 线上搜索匹配到的联系人/群聊
@immutable
class SearchRemoteContactItem {
  const SearchRemoteContactItem({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.objectType,
    this.objectTypeDescription,
    this.isFriend = false,
    this.code,
  });

  final String id;
  final String name;
  final String? avatarUrl;
  final int? objectType;
  final String? objectTypeDescription;
  final bool isFriend;
  final String? code;
}

/// 全局搜索聚合状态
@immutable
class SearchResultState {
  const SearchResultState({
    this.keyword = '',
    this.isLocalLoading = false,
    this.isRemoteLoading = false,
    this.localContacts = const <SearchContactItem>[],
    this.localMessages = const <SearchMessageItem>[],
    this.remoteContacts = const <SearchRemoteContactItem>[],
    this.history = const <String>[],
    this.error,
  });

  final String keyword;
  final bool isLocalLoading;
  final bool isRemoteLoading;
  final List<SearchContactItem> localContacts;
  final List<SearchMessageItem> localMessages;
  final List<SearchRemoteContactItem> remoteContacts;
  final List<String> history;
  final String? error;

  bool get isEmptyQuery => keyword.trim().isEmpty;
  bool get hasAnyResult =>
      localContacts.isNotEmpty ||
      localMessages.isNotEmpty ||
      remoteContacts.isNotEmpty;

  SearchResultState copyWith({
    String? keyword,
    bool? isLocalLoading,
    bool? isRemoteLoading,
    List<SearchContactItem>? localContacts,
    List<SearchMessageItem>? localMessages,
    List<SearchRemoteContactItem>? remoteContacts,
    List<String>? history,
    String? error,
  }) {
    return SearchResultState(
      keyword: keyword ?? this.keyword,
      isLocalLoading: isLocalLoading ?? this.isLocalLoading,
      isRemoteLoading: isRemoteLoading ?? this.isRemoteLoading,
      localContacts: localContacts ?? this.localContacts,
      localMessages: localMessages ?? this.localMessages,
      remoteContacts: remoteContacts ?? this.remoteContacts,
      history: history ?? this.history,
      error: error,
    );
  }
}
