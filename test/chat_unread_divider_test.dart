import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/features/chat/application/chat_unread_divider.dart';
import 'package:gotoim_flutter/features/chat/data/models/chat_message.dart';

void main() {
  ChatMessage message(int id, {bool isMine = false}) => ChatMessage(
    localId: 'local-$id',
    serverId: id,
    clientMessageId: null,
    ownerId: 1,
    sessionUnitId: 'mine',
    senderSessionUnitId: isMine ? 'mine' : 'peer',
    messageType: 0,
    state: 'received',
    score: id,
    createdAt: null,
    raw: const <String, dynamic>{},
  );

  test(
    'keeps the initial read boundary when cached incoming messages are newer',
    () {
      expect(
        findInitialUnreadDividerMessageId(
          messages: <ChatMessage>[message(12), message(11), message(10)],
          readMessageId: 10,
        ),
        10,
      );
    },
  );

  test('does not create a divider for messages sent by the current user', () {
    expect(
      findInitialUnreadDividerMessageId(
        messages: <ChatMessage>[message(12, isMine: true), message(10)],
        readMessageId: 10,
      ),
      isNull,
    );
  });

  test('does not create a divider without a cached read position', () {
    expect(
      findInitialUnreadDividerMessageId(
        messages: <ChatMessage>[message(12), message(11)],
        readMessageId: null,
      ),
      isNull,
    );
  });
}
