import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/features/session/data/models/chat_owner.dart';

void main() {
  test('掌柜数值身份在本地存取和概览更新后保留', () {
    final owner = ChatOwner.fromJson({
      'id': 7,
      'displayName': '店长',
      'objectType': 7,
      'objectTypeDescription': '掌柜',
    });
    expect(owner.objectType, 7);
    expect(owner.withOverview(unread: 2, immersed: 0).objectType, 7);
    expect(owner.copyWith(name: '新名称').objectType, 7);
    expect(ChatOwner.fromDatabaseRow(owner.toDatabaseValues()).objectType, 7);
  });
}
