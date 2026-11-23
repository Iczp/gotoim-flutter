import 'chat_object_type.dart';
import 'session_summary_helpers.dart';

class ChatOwner {
  const ChatOwner({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.typeDescription,
    this.objectType,
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
    final avatar = firstNonEmpty([json['thumbnail'], json['portrait']]);
    return ChatOwner(
      id: id,
      name: name,
      imageUrl: avatar.isEmpty ? null : avatar,
      typeDescription: json['objectTypeDescription']?.toString() ?? '',
      objectType: int.tryParse('${json['objectType'] ?? ''}'),
    );
  }

  final int id;
  final String name;
  final String? imageUrl;
  final String typeDescription;
  final int? objectType;
  final int unreadCount;
  final int immersedCount;

  /// 优先返回合法的非数字描述，否则回退至权威 `ChatObjectType` 中文标签。
  String get displayTypeDescription {
    final trimmed = typeDescription.trim();
    if (trimmed.isNotEmpty && int.tryParse(trimmed) == null) {
      return trimmed;
    }
    return chatObjectTypeLabel(objectType);
  }

  factory ChatOwner.fromDatabaseRow(Map<String, Object?> row) {
    final raw = row['raw'];
    if (raw is String && raw.isNotEmpty) {
      return ChatOwner.fromJson(decodeJsonObject(raw));
    }
    final parsedObjectType = int.tryParse('${row['objectType'] ?? ''}');
    return ChatOwner(
      id: (row['id'] as num).toInt(),
      name: row['name']?.toString() ?? '',
      imageUrl: null,
      typeDescription: chatObjectTypeLabel(parsedObjectType),
      objectType: parsedObjectType,
    );
  }

  Map<String, Object?> toDatabaseValues() => <String, Object?>{
    'id': id,
    'name': name,
    'objectType': objectType?.toString() ?? typeDescription,
    'raw': encodeJson(<String, Object?>{
      'id': id,
      'displayName': name,
      'thumbnail': imageUrl,
      'objectTypeDescription': typeDescription,
      'objectType': objectType,
    }),
  };

  ChatOwner withOverview({required int unread, required int immersed}) =>
      ChatOwner(
        id: id,
        name: name,
        imageUrl: imageUrl,
        typeDescription: typeDescription,
        objectType: objectType,
        unreadCount: unread,
        immersedCount: immersed,
      );

  ChatOwner copyWith({String? name, String? imageUrl}) => ChatOwner(
    id: id,
    name: name ?? this.name,
    imageUrl: imageUrl ?? this.imageUrl,
    typeDescription: typeDescription,
    objectType: objectType,
    unreadCount: unreadCount,
    immersedCount: immersedCount,
  );
}
