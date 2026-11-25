import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/features/chat/data/models/chat_message.dart';

void main() {
  const unitA = 'AAAAAAAA-0000-0000-0000-000000000001';
  const unitB = 'bbbbbbbb-0000-0000-0000-000000000002';
  final senders = {
    unitA: {
      'id': unitA,
      'ownerId': 11,
      'memberName': '张三',
      'owner': {'id': 11, 'name': 'zhangsan'},
    },
    unitB: {
      'id': unitB,
      'ownerId': 22,
      'memberName': '李四',
      'owner': {'id': 22, 'name': 'lisi'},
    },
  };

  test('没有 senders 字典时原样返回', () {
    final page = {
      'items': [
        {'id': 1, 'senderSessionUnitId': unitA},
      ],
    };
    expect(identical(hydrateCompactSenders(page), page), isTrue);
  });

  test('同页多条消息共享少量发送人，回填后与旧协议一致', () {
    final page = {
      'items': [
        for (var i = 1; i <= 4; i++)
          {
            'id': 100 + i,
            'senderSessionUnitId': i.isOdd ? unitA : unitB,
            'creationTime': '2026-11-25T12:00:00Z',
          },
      ],
      'extra': {'senders': senders},
    };
    final hydrated = hydrateCompactSenders(page);
    final messages = (hydrated['items'] as List)
        .map(
          (e) => ChatMessage.fromJson(
            Map<String, dynamic>.from(e as Map),
            ownerId: 99,
            sessionUnitId: 'unit',
          ),
        )
        .toList();
    expect(messages.map((m) => m.senderChatObjectId), [11, 22, 11, 22]);
    expect(messages.first.senderSessionUnit['memberName'], '张三');
  });

  test('引用消息的发送人同样回填，且不覆盖已有对象', () {
    final page = {
      'items': [
        {
          'id': 1,
          'senderSessionUnitId': unitA,
          'senderSessionUnit': {'id': unitA, 'memberName': '已有'},
          'quoteMessage': {'id': 2, 'senderSessionUnitId': unitB},
        },
      ],
      'extra': {'Senders': senders},
    };
    final row = (hydrateCompactSenders(page)['items'] as List).first as Map;
    expect((row['senderSessionUnit'] as Map)['memberName'], '已有');
    expect(((row['quoteMessage'] as Map)['senderSessionUnit'] as Map)['memberName'], '李四');
  });
}
