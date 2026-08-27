import 'session_summary_helpers.dart';

class ChatOwner {
  const ChatOwner({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.typeDescription,
    this.unreadCount = 0,
    this.immersedCount = 0,
  });

  factory ChatOwner.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final id = rawId is num ? rawId.toInt() : int.tryParse('$rawId');
    if (id == null || id <= 0) {
      throw const FormatException('ChatObjectDto.id is missing');
    }
    final name = (json['displayName'] ?? json['name'] ?? '').toString().trim();
    return ChatOwner(
      id: id,
      name: name,
      imageUrl: (json['thumbnail'] ?? json['portrait'])?.toString(),
      typeDescription: json['objectTypeDescription']?.toString() ?? '',
    );
  }

  final int id;
  final String name;
  final String? imageUrl;
  final String typeDescription;
  final int unreadCount;
  final int immersedCount;

  factory ChatOwner.fromDatabaseRow(Map<String, Object?> row) {
    final raw = row['raw'];
    if (raw is String && raw.isNotEmpty) {
      return ChatOwner.fromJson(decodeJsonObject(raw));
    }
    return ChatOwner(
      id: (row['id'] as num).toInt(),
      name: row['name']?.toString() ?? '',
      imageUrl: null,
      typeDescription: row['objectType']?.toString() ?? '',
    );
  }

  Map<String, Object?> toDatabaseValues() => <String, Object?>{
    'id': id,
    'name': name,
    'objectType': typeDescription,
    'raw': encodeJson(<String, Object?>{
      'id': id,
      'displayName': name,
      'thumbnail': imageUrl,
      'objectTypeDescription': typeDescription,
    }),
  };

  ChatOwner withOverview({required int unread, required int immersed}) =>
      ChatOwner(
        id: id,
        name: name,
        imageUrl: imageUrl,
        typeDescription: typeDescription,
        unreadCount: unread,
        immersedCount: immersed,
      );
}
