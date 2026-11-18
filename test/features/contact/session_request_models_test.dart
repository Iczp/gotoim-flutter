import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/features/contact/data/models/session_request_models.dart';

void main() {
  group('parseSessionRequestDetailId', () {
    test('parses backend typo scheme app://sesson-request/detail?id=...', () {
      expect(
        parseSessionRequestDetailId(
          'app://sesson-request/detail?id=8f4c1f40-1111-2222-3333-444455556666',
        ),
        '8f4c1f40-1111-2222-3333-444455556666',
      );
    });

    test('parses standard scheme app://session-request/detail?id=...', () {
      expect(
        parseSessionRequestDetailId(
          'app://session-request/detail?id=8f4c1f40-1111-2222-3333-444455556666',
        ),
        '8f4c1f40-1111-2222-3333-444455556666',
      );
    });

    test('returns null for unrelated URLs or missing id', () {
      expect(parseSessionRequestDetailId('https://example.com/detail?id=1'), isNull);
      expect(parseSessionRequestDetailId('app://session-request/detail'), isNull);
      expect(parseSessionRequestDetailId(''), isNull);
    });
  });

  group('SessionRequestItem.fromJson', () {
    test('parses owner, destination, and approval fields', () {
      final item = SessionRequestItem.fromJson(<String, dynamic>{
        'id': 'req-123',
        'ownerId': 1001,
        'destinationId': 2002,
        'requestMessage': '请允许我加入群聊',
        'handleMessage': '',
        'isAgreed': null,
        'isHandled': false,
        'isExpired': false,
        'owner': <String, dynamic>{
          'id': 1001,
          'name': '张三',
          'code': 'zhangsan',
          'objectType': 1,
        },
        'destination': <String, dynamic>{
          'id': 2002,
          'name': '测试群',
          'objectType': 2,
        },
      });

      expect(item.id, 'req-123');
      expect(item.ownerId, 1001);
      expect(item.destinationId, 2002);
      expect(item.requestMessage, '请允许我加入群聊');
      expect(item.isHandled, isFalse);
      expect(item.isAgreed, isNull);
      expect(item.owner?.name, '张三');
      expect(item.destination?.name, '测试群');
      expect(item.destination?.objectType, 2);
    });
  });
}
