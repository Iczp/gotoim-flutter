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
