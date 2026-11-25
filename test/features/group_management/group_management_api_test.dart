import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/features/group_management/data/group_management_api.dart';

void main() {
  test('RoomManagementSettings.fromJson parses policies and capability flags', () {
    final dto = RoomManagementSettings.fromJson(<String, dynamic>{
      'sessionId': '11111111-1111-1111-1111-111111111111',
      'roomId': 2002,
      'name': '技术架构群',
      'description': '群简介',
      'verificationMethod': 1,
      'isAllMuted': true,
      'invitePolicy': 2,
      'allowJoinChannels': 3,
      'pendingJoinRequestCount': 4,
      'pendingAnnouncementCount': 2,
      'isCreator': false,
      'isAdmin': true,
      'hasCreator': true,
      'hasAdmin': true,
      'canClaimCreator': false,
      'canEnterManagement': true,
      'canManageSettings': true,
      'canManageJoinRequests': true,
      'canManageAnnouncements': true,
      'canManageMembers': true,
      'canManageOrgs': false,
      'canManageRoles': false,
      'canManagePermissions': false,
      'canTransferOrDissolve': false,
    });

    expect(dto.sessionId, '11111111-1111-1111-1111-111111111111');
    expect(dto.roomId, 2002);
    expect(dto.isAllMuted, isTrue);
    expect(dto.invitePolicy, 2);
    expect(dto.allowJoinChannels, 3);
    expect(dto.totalPendingCount, 6);
    expect(dto.hasCreator, isTrue);
    expect(dto.hasAdmin, isTrue);
    expect(dto.canClaimCreator, isFalse);
    expect(dto.canEnterManagement, isTrue);
    expect(dto.canTransferOrDissolve, isFalse);
  });

  test('GroupManagementApi calls management-settings, update-policies, transfer-creator, and dissolve', () async {
    final client = _FakeApiClient();
    final api = GroupManagementApi(client);

    final settings = await api.getManagementSettings('unit-1');
    expect(client.lastGetPath, '/api/chat/room/management-settings/unit-1');
    expect(settings.name, '测试群');

    await api.updatePolicies(
      sessionUnitId: 'unit-1',
      verificationMethod: 1,
      isAllMuted: true,
      invitePolicy: 1,
      allowJoinChannels: 5,
      description: '新简介',
    );
    expect(client.lastPostPath, '/api/chat/room/update-policies');
    expect(client.lastPostData, <String, Object?>{
      'sessionUnitId': 'unit-1',
      'verificationMethod': 1,
      'isAllMuted': true,
      'invitePolicy': 1,
      'allowJoinChannels': 5,
      'description': '新简介',
    });

    await api.transferCreator(
      sessionUnitId: 'unit-1',
      targetSessionUnitId: 'unit-2',
    );
    expect(client.lastPostPath, '/api/chat/room/transfer-creator');
    expect(client.lastPostQuery, <String, Object?>{
      'sessionUnitId': 'unit-1',
      'targetSessionUnitId': 'unit-2',
    });

    await api.dissolveRoom('unit-1');
    expect(client.lastPostPath, '/api/chat/room/dissolve/unit-1');

    final claimed = await api.claimCreator('unit-1');
    expect(client.lastPostPath, '/api/chat/room/claim-creator/unit-1');
    expect(claimed.name, '测试群');
  });
}

class _FakeApiClient extends ApiClient {
  String? lastGetPath;
  String? lastPostPath;
  Object? lastPostData;
  Map<String, Object?>? lastPostQuery;

  @override
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    bool retryOnUnauthorized = true,
  }) async {
    lastGetPath = path;
    return <String, dynamic>{
      'sessionId': 'sess-1',
      'roomId': 1001,
      'name': '测试群',
      'canEnterManagement': true,
    } as T;
  }

  @override
  Future<T> post<T>(
    String path, {
    Map<String, Object?>? query,
    Object? data,
    Map<String, String>? headers,
    bool retryOnUnauthorized = true,
  }) async {
    lastPostPath = path;
    lastPostData = data;
    lastPostQuery = query;
    return <String, dynamic>{
      'sessionId': 'sess-1',
      'roomId': 1001,
      'name': '测试群',
      'canEnterManagement': true,
    } as T;
  }

  @override
  Future<T> postMultipart<T>(
    String path, {
    Map<String, Object?>? query,
    Map<String, Object?>? extraFields,
    required MultipartUploadFile file,
    String fieldName = 'file',
    void Function(int sent, int total)? onProgress,
    bool retryOnUnauthorized = true,
  }) async => throw UnimplementedError();

  @override
  Future<void> cancelByTag(Object tag) async {}

  @override
  Future<List<int>> getBytes(
    String path, {
    Object? cancelTag,
    void Function(int received, int total)? onProgress,
  }) async => throw UnimplementedError();
}
