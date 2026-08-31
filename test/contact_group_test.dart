import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/features/contact/data/models/contact_group.dart';

void main() {
  test(
    'server contact group keeps contacts and de-duplicates surname initials',
    () {
      final group = ContactGroup.fromJson(<String, dynamic>{
        'index': 'a',
        'list': <Map<String, dynamic>>[
          <String, dynamic>{'id': '1', 'name': 'Alice'},
          <String, dynamic>{'id': '2', 'rename': 'Annie', 'name': 'Ignored'},
          <String, dynamic>{'id': '3', 'name': 'Bob'},
        ],
      });

      expect(group.index, 'A');
      expect(group.count, 3);
      expect(group.contacts[1].displayName, 'Annie');
      expect(group.surnameInitials, <String>['A', 'B']);
    },
  );

  test('local fallback produces stable alphabet groups', () {
    final groups = localContactGroups(
      <({String id, int? ownerId, String title, Map<String, dynamic> raw})>[
        (id: 'b', ownerId: 1, title: 'Bob', raw: const <String, dynamic>{}),
        (id: 'a', ownerId: 1, title: 'Alice', raw: const <String, dynamic>{}),
        (id: 'c', ownerId: 1, title: '中文', raw: const <String, dynamic>{}),
      ],
    );

    expect(groups.map((group) => group.index), <String>['A', 'B', '#']);
    expect(groups.first.contacts.single.displayName, 'Alice');
  });

  test('local fallback preserves cached contact avatar and rename', () {
    final groups = localContactGroups(
      <({String id, int? ownerId, String title, Map<String, dynamic> raw})>[
        (
          id: 'a',
          ownerId: 1,
          title: 'Alice',
          raw: const <String, dynamic>{
            'destination': <String, dynamic>{
              'memberName': '阿丽丝',
              'thumbnail': '/cached-avatar.png',
            },
          },
        ),
      ],
    );

    expect(groups.single.contacts.single.displayName, '阿丽丝');
    expect(groups.single.contacts.single.avatarUrl, '/cached-avatar.png');
  });
}
