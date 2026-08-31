import 'dart:convert';

import '../../../../core/database/unified_database.dart';
import '../datasources/contacts_api.dart';
import '../models/contact_group.dart';

class ContactsRepository {
  ContactsRepository(this._api, this._database);

  final ContactsApi _api;
  final UnifiedDatabase _database;

  Future<List<ContactGroup>> loadIndexedFriends({required int ownerId}) =>
      _api.getIndexedFriends(ownerId: ownerId);

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
  }) => _database.writeSettingValue(
    id: _cacheKey(ownerId),
    group: 'contacts',
    value: jsonEncode(groups.map((item) => item.toJson()).toList()),
  );

  String _cacheKey(int ownerId) => 'contacts-indexed-$ownerId';
}
