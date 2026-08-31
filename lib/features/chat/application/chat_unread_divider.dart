import '../data/models/chat_message.dart';

/// Returns the read-position captured when a chat is opened, if the initial
/// local timeline already contains newer incoming messages.
///
/// This is intentionally calculated once. A live [readMessageId] changes as
/// the user reads or receives messages, and using it directly would make a
/// newly received message incorrectly create an “以下为新消息” divider.
int? findInitialUnreadDividerMessageId({
  required Iterable<ChatMessage> messages,
  required int? readMessageId,
}) {
  if (readMessageId == null || readMessageId <= 0) return null;
  final hasInitialUnreadMessage = messages.any(
    (message) =>
        !message.isMine &&
        message.serverId != null &&
        message.serverId! > readMessageId,
  );
  return hasInitialUnreadMessage ? readMessageId : null;
}
