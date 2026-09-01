import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/database/unified_database.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/features/contact/data/datasources/contacts_api.dart';
import 'package:gotoim_flutter/features/contact/data/models/contact_group.dart';
import 'package:gotoim_flutter/features/contact/data/repositories/contacts_repository.dart';

void main() {
  test('indexed contacts survive offline repository restart', () async {
    final database = UnifiedDatabase(
      DatabaseConnection(NativeDatabase.memory()),
    );
    addTearDown(database.close);
    final repository = ContactsRepository(
      ContactsApi(_NoNetworkClient()),
      database,
    );
    final groups = <ContactGroup>[
      ContactGroup.fromJson(<String, dynamic>{
        'index': 'A',
        'list': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'friend-1',
            'ownerId': 7,
            'name': 'Alice',
            'thumbnail': '/alice.png',
          },
        ],
      }),
    ];

    await repository.saveIndexedFriends(ownerId: 7, groups: groups);
    final restored = await repository.loadLocalIndexedFriends(ownerId: 7);

    expect(restored.single.index, 'A');
    expect(restored.single.contacts.single.displayName, 'Alice');
    expect(restored.single.contacts.single.avatarUrl, '/alice.png');
  });
}

class _NoNetworkClient implements ApiClient {
  @override
  Future<void> cancelByTag(Object tag) async {}

  @override
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    bool retryOnUnauthorized = true,
  }) => throw StateError('Network must not be used by this test');

  @override
  Future<List<int>> getBytes(
    String path, {
    Object? cancelTag,
    void Function(int, int)? onProgress,
  }) => throw StateError('Network must not be used by this test');

  @override
  Future<T> post<T>(
    String path, {
    Map<String, Object?>? query,
    Object? data,
    Map<String, String>? headers,
    bool retryOnUnauthorized = true,
  }) => throw StateError('Network must not be used by this test');

  @override
  Future<T> postMultipart<T>(
    String path, {
    Map<String, Object?>? query,
    Map<String, Object?>? extraFields,
    required MultipartUploadFile file,
    String fieldName = 'file',
    void Function(int, int)? onProgress,
    bool retryOnUnauthorized = true,
  }) => throw StateError('Network must not be used by this test');
}
