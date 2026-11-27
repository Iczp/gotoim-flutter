import 'dart:collection';

class AttachmentReuseEntry {
  const AttachmentReuseEntry({
    required this.reuseToken,
    this.expireTime,
  });

  final String reuseToken;
  final DateTime? expireTime;
}

/// 账号级内存态附件复用令牌注册表（同一账号多身份共用同一物理 Blob 凭证，按 SHA-256 + 媒体类型 + 原图标识隔离）
class AttachmentReuseRegistry {
  AttachmentReuseRegistry({
    this.maxEntries = 200,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final int maxEntries;
  final DateTime Function() _now;
  final LinkedHashMap<String, AttachmentReuseEntry> _entries =
      LinkedHashMap<String, AttachmentReuseEntry>();

  static const Duration _expirySafetyMargin = Duration(seconds: 60);

  static String buildKey({
    required String accountScope,
    String chatObjectId = '',
    required int messageType,
    required String sha256Hex,
    required int fileLength,
    bool isOriginal = false,
    String outputVariant = '',
  }) {
    final normalizedAccount = accountScope.trim();
    final normalizedChatObject = chatObjectId.trim();
    final normalizedHash = sha256Hex.trim().toLowerCase();
    final normalizedVariant = outputVariant.trim();
    return '$normalizedAccount|$normalizedChatObject|$messageType|$normalizedHash|$fileLength|${isOriginal ? 1 : 0}|$normalizedVariant';
  }

  AttachmentReuseEntry? lookup({
    required String accountScope,
    String chatObjectId = '',
    required int messageType,
    required String sha256Hex,
    required int fileLength,
    bool isOriginal = false,
    String outputVariant = '',
  }) {
    final key = buildKey(
      accountScope: accountScope,
      chatObjectId: chatObjectId,
      messageType: messageType,
      sha256Hex: sha256Hex,
      fileLength: fileLength,
      isOriginal: isOriginal,
      outputVariant: outputVariant,
    );
    final entry = _entries.remove(key);
    if (entry == null) return null;

    if (entry.reuseToken.trim().isEmpty) {
      return null;
    }

    final expireTime = entry.expireTime;
    if (expireTime != null &&
        !expireTime.isAfter(_now().add(_expirySafetyMargin))) {
      return null;
    }

    // Re-insert at tail to preserve LRU recency.
    _entries[key] = entry;
    return entry;
  }

  void remember({
    required String accountScope,
    String chatObjectId = '',
    required int messageType,
    required String sha256Hex,
    required int fileLength,
    bool isOriginal = false,
    String outputVariant = '',
    required String reuseToken,
    DateTime? expireTime,
  }) {
    final trimmedToken = reuseToken.trim();
    final trimmedAccount = accountScope.trim();
    if (trimmedToken.isEmpty || trimmedAccount.isEmpty) return;

    final key = buildKey(
      accountScope: accountScope,
      chatObjectId: chatObjectId,
      messageType: messageType,
      sha256Hex: sha256Hex,
      fileLength: fileLength,
      isOriginal: isOriginal,
      outputVariant: outputVariant,
    );
    _entries.remove(key);
    _entries[key] = AttachmentReuseEntry(
      reuseToken: trimmedToken,
      expireTime: expireTime,
    );

    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  void invalidate({
    required String accountScope,
    String chatObjectId = '',
    required int messageType,
    required String sha256Hex,
    required int fileLength,
    bool isOriginal = false,
    String outputVariant = '',
  }) {
    final key = buildKey(
      accountScope: accountScope,
      chatObjectId: chatObjectId,
      messageType: messageType,
      sha256Hex: sha256Hex,
      fileLength: fileLength,
      isOriginal: isOriginal,
      outputVariant: outputVariant,
    );
    _entries.remove(key);
  }

  void clearAccount(String accountScope) {
    final prefix = '${accountScope.trim()}|';
    if (prefix == '|') return;
    _entries.removeWhere((key, _) => key.startsWith(prefix));
  }
}
