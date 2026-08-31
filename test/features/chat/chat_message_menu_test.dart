import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/features/chat/data/models/chat_message.dart';
import 'package:gotoim_flutter/features/chat/presentation/message_menu/chat_message_menu.dart';

ChatMessage _message({
  int type = 0,
  String state = 'sent',
  int? serverId = 1,
  bool mine = true,
  bool rollbacked = false,
}) => ChatMessage(
  localId: 'local',
  serverId: serverId,
  clientMessageId: 'client',
  ownerId: 1,
  sessionUnitId: 'mine',
  senderSessionUnitId: mine ? 'mine' : 'other',
  messageType: type,
  state: state,
  score: 1,
  createdAt: DateTime(2026),
  raw: <String, dynamic>{
    if (rollbacked) 'isRollbacked': true,
    'content': {'text': 'hello'},
  },
);

void main() {
  const builder = ChatMessageMenuBuilder();

  test('sent self text offers reply copy forward recall and delete', () {
    final items = builder.build(
      ChatMessageMenuContext(message: _message(), canRecall: true),
    );
    expect(
      items.map((item) => item.id),
      containsAll(<String>['reply', 'copy', 'forward', 'recall', 'delete']),
    );
  });

  test('failed message only offers retry when the controller can retry it', () {
    final context = ChatMessageMenuContext(
      message: _message(state: 'failed', serverId: null),
      canRetry: true,
    );
    expect(builder.build(context).map((item) => item.id), <String>[
      'retry',
      'delete',
    ]);
    expect(
      builder
          .build(
            ChatMessageMenuContext(
              message: _message(state: 'failed', serverId: null),
            ),
          )
          .map((item) => item.id),
      <String>['delete'],
    );
  });

  test('recalled and system messages cannot expose invalid actions', () {
    expect(
      builder
          .build(ChatMessageMenuContext(message: _message(rollbacked: true)))
          .map((item) => item.id),
      <String>['delete'],
    );
    expect(
      builder.build(ChatMessageMenuContext(message: _message(type: 1))),
      isEmpty,
    );
  });
}
