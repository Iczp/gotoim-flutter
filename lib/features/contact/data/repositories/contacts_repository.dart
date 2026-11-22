import 'dart:convert';

import '../../../../core/database/unified_database.dart';
import '../datasources/contacts_api.dart';
import '../models/contact_group.dart';
import '../models/online_friend.dart';

class ContactsRepository {
  ContactsRepository(this._api, this._database);

  final ContactsApi _api;
  final UnifiedDatabase _database;

  Future<List<ContactGroup>> loadIndexedFriends({required int ownerId}) =>
      _api.getIndexedFriends(ownerId: ownerId);

  Future<List<OnlineFriend>> loadOnlineFriends({required int ownerId}) =>
      _api.getOnlineFriends(ownerId: ownerId);

  Future<List<ContactGroup>> loadLocalIndexedFriends({
    required int ownerId,
  }) async {
    final value = await _database.readSettingValue(_cacheKey(ownerId));
    if (value == null || value.isEmpty) return const <ContactGroup>[];
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) return const <ContactGroup>[];
      return decoded
          .whereType<Map>()
          .map((item) => ContactGroup.fromJson(Map<String, dynamic>.from(item)))
          .where((group) => group.contacts.isNotEmpty)
          .toList(growable: false);
    } on FormatException {
      return const <ContactGroup>[];
    }
  }

  Future<void> saveIndexedFriends({
    required int ownerId,
    required List<ContactGroup> groups,
  }) {
    final maxTicks = computeMaxTicks(groups);
    if (maxTicks > 0) {
      saveLastSyncTicks(ownerId, maxTicks);
    }
    return _database.writeSettingValue(
      id: _cacheKey(ownerId),
      group: 'contacts',
      value: jsonEncode(groups.map((item) => item.toJson()).toList()),
    );
  }

  Future<int> readLastSyncTicks(int ownerId) async {
    final value = await _database.readSettingValue(_syncTicksKey(ownerId));
    if (value == null || value.isEmpty) return 0;
    return int.tryParse(value) ?? 0;
  }

  Future<void> saveLastSyncTicks(int ownerId, int ticks) =>
      _database.writeSettingValue(
        id: _syncTicksKey(ownerId),
        group: 'contacts',
        value: ticks.toString(),
      );

  Future<Map<String, dynamic>> loadContactChanges({
    required int ownerId,
    required int minTicks,
    int maxResultCount = 100,
  }) => _api.getContactChanges(
    ownerId: ownerId,
    minTicks: minTicks,
    maxResultCount: maxResultCount,
  );

  int computeMaxTicks(List<ContactGroup> groups) {
    var max = 0;
    for (final group in groups) {
      for (final contact in group.contacts) {
        if (contact.ticks > max) {
          max = contact.ticks;
        }
      }
    }
    return max;
  }

  /// 获取联系人详情
  Future<Map<String, dynamic>> loadContactDetail(String sessionUnitId) =>
      _api.getContactDetail(sessionUnitId: sessionUnitId);

  /// 获取系统字段定义
  Future<Map<String, dynamic>> loadEntryNames() => _api.getEntryNames();

  /// 保存会话单元自定义条目
  Future<Map<String, dynamic>> saveSessionUnitEntries(
    String sessionUnitId,
    Map<String, List<String>> entries,
  ) =>
      _api.setSessionUnitEntries(
        sessionUnitId: sessionUnitId,
        entries: entries,
      );

  String _cacheKey(int ownerId) => 'contacts-indexed-$ownerId';
  String _syncTicksKey(int ownerId) => 'contacts-sync-ticks-$ownerId';
}
