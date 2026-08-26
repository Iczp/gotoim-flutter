class ChatOwner {
  const ChatOwner({required this.id, required this.name});

  factory ChatOwner.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final id = rawId is num ? rawId.toInt() : int.tryParse('$rawId');
    if (id == null || id <= 0) {
      throw const FormatException('ChatObjectDto.id is missing');
    }
    final name = (json['displayName'] ?? json['name'] ?? '').toString().trim();
    return ChatOwner(id: id, name: name);
  }

  final int id;
  final String name;
}
