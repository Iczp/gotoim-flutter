import 'package:flutter/foundation.dart';

/// Contact index data returned by the existing `friends-indexed` contract.
///
/// The server owns Chinese-name/pinyin collation. `localContactGroups` is only
/// the offline fallback when that indexed response is temporarily unavailable.
@immutable
class ContactEntry {
  const ContactEntry({
    required this.id,
    required this.ownerId,
    required this.objectType,
    required this.name,
    required this.rename,
    required this.abbr,
    required this.nameSpelling,
    required this.portrait,
    required this.thumbnail,
    required this.raw,
  });

  factory ContactEntry.fromJson(Map<String, dynamic> json) => ContactEntry(
    id: json['id']?.toString() ?? '',
    ownerId: _asInt(json['ownerId']),
    objectType: _asInt(json['objectType']),
    name: json['name']?.toString() ?? '',
    rename: json['rename']?.toString() ?? '',
    abbr: json['abbr']?.toString() ?? '',
    nameSpelling: json['nameSpelling']?.toString() ?? '',
    portrait: json['portrait']?.toString() ?? '',
    thumbnail: json['thumbnail']?.toString() ?? '',
    raw: Map<String, dynamic>.unmodifiable(json),
  );

  final String id;
  final int? ownerId;
  final int? objectType;
  final String name;
  final String rename;
  final String abbr;
  final String nameSpelling;
  final String portrait;
  final String thumbnail;
  final Map<String, dynamic> raw;

  Map<String, dynamic> toJson() => Map<String, dynamic>.from(raw);

  String get displayName => rename.trim().isNotEmpty ? rename.trim() : name;
  String get avatarUrl => thumbnail.trim().isNotEmpty ? thumbnail : portrait;
  int? get destinationId {
    final destination = raw['destination'];
    final value =
        destination is Map
            ? (destination['id'] ?? destination['Id'])
            : (raw['destinationId'] ?? raw['DestinationId']);
    return _asInt(value);
  }

  String get surnameInitial {
    final value = displayName.trim();
    return value.isEmpty
        ? '#'
        : String.fromCharCode(value.runes.first).toUpperCase();
  }
}

@immutable
class ContactGroup {
  const ContactGroup({required this.index, required this.contacts});

  factory ContactGroup.fromJson(Map<String, dynamic> json) {
    final rawList = json['list'];
    return ContactGroup(
      index: _normalizedIndex(json['index']?.toString() ?? '#'),
      contacts:
          rawList is List
              ? rawList
                  .whereType<Map>()
                  .map(
                    (item) =>
                        ContactEntry.fromJson(Map<String, dynamic>.from(item)),
                  )
                  .where((item) => item.id.isNotEmpty)
                  .toList(growable: false)
              : const <ContactEntry>[],
    );
  }

  final String index;
  final List<ContactEntry> contacts;
  int get count => contacts.length;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'index': index,
    'list': contacts.map((contact) => contact.toJson()).toList(),
  };

  /// A group header shows every distinct surname/first character once, in the
  /// same ordering as the server response.
  List<String> get surnameInitials {
    final seen = <String>{};
    return contacts
        .map((contact) => contact.surnameInitial)
        .where(seen.add)
        .toList(growable: false);
  }
}

List<ContactGroup> localContactGroups(
  Iterable<({String id, int? ownerId, String title, Map<String, dynamic> raw})>
  friends,
) {
  final grouped = <String, List<ContactEntry>>{};
  for (final friend in friends) {
    final destination =
        friend.raw['destination'] is Map
            ? Map<String, dynamic>.from(friend.raw['destination'] as Map)
            : const <String, dynamic>{};
    final entry = ContactEntry(
      id: friend.id,
      ownerId: friend.ownerId,
      objectType: _asInt(
        friend.raw['destination'] is Map
            ? (friend.raw['destination'] as Map)['objectType']
            : null,
      ),
      name: friend.title,
      rename: destination['memberName']?.toString() ?? '',
      abbr: '',
      nameSpelling: '',
      portrait: destination['portrait']?.toString() ?? '',
      thumbnail: destination['thumbnail']?.toString() ?? '',
      raw: friend.raw,
    );
    final initial = _normalizedIndex(entry.surnameInitial);
    grouped.putIfAbsent(initial, () => <ContactEntry>[]).add(entry);
  }
  final groups =
      grouped.entries.map((entry) {
        entry.value.sort(
          (left, right) => left.displayName.compareTo(right.displayName),
        );
        return ContactGroup(index: entry.key, contacts: entry.value);
      }).toList();
  groups.sort(
    (left, right) =>
        _indexOrder(left.index).compareTo(_indexOrder(right.index)),
  );
  return groups;
}

String _normalizedIndex(String value) {
  final initial = value.trim().toUpperCase();
  return RegExp(r'^[A-Z]$').hasMatch(initial) ? initial : '#';
}

int _indexOrder(String index) => index == '#' ? 27 : index.codeUnitAt(0) - 65;

int? _asInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value');
