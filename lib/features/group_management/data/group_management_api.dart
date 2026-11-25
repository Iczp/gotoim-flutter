import '../../../core/network/api_client.dart';

class IdNameItem {
  const IdNameItem({
    required this.id,
    required this.name,
    this.parentId,
    this.boundRoles = const <IdNameItem>[],
    this.memberCount = 0,
  });
  factory IdNameItem.fromJson(Map<String, dynamic> json) {
    final rawBound = json['boundRoles'];
    final bound = rawBound is List
        ? rawBound
            .whereType<Map>()
            .map((e) => IdNameItem.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false)
        : const <IdNameItem>[];
    return IdNameItem(
      id: json['id']?.toString() ?? '',
      name: (json['name'] ?? json['title'] ?? json['value'] ?? '-').toString(),
      parentId: json['parentId']?.toString(),
      boundRoles: bound,
      memberCount: json['memberCount'] is num
          ? (json['memberCount'] as num).toInt()
          : 0,
    );
  }
  final String id;
  final String name;
  final String? parentId;
  final List<IdNameItem> boundRoles;
  final int memberCount;
}

class RoomManagementSettings {
  const RoomManagementSettings({
    required this.sessionId,
    required this.roomId,
    required this.name,
    this.portrait,
    this.description,
    this.verificationMethod = 0,
    this.isAllMuted = false,
    this.invitePolicy = 0,
    this.allowJoinChannels = 7,
    this.pendingJoinRequestCount = 0,
    this.pendingAnnouncementCount = 0,
    this.isCreator = false,
    this.isAdmin = false,
    this.hasCreator = false,
    this.hasAdmin = false,
    this.canClaimCreator = false,
    this.canEnterManagement = false,
    this.canManageSettings = false,
    this.canManageJoinRequests = false,
    this.canManageAnnouncements = false,
    this.canManageMembers = false,
    this.canManageOrgs = false,
    this.canManageRoles = false,
    this.canManagePermissions = false,
    this.canSetAdmin = false,
    this.canManageNameOrDescription = false,
    this.canToggleAllMuted = false,
    this.canManageJoinPolicies = false,
    this.canTransferOrDissolve = false,
  });

  factory RoomManagementSettings.fromJson(Map<String, dynamic> json) {
    int parseInt(Object? v, int fallback) =>
        v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? fallback;

    return RoomManagementSettings(
      sessionId: json['sessionId']?.toString() ?? '',
      roomId: parseInt(json['roomId'], 0),
      name: json['name']?.toString() ?? '',
      portrait: json['portrait']?.toString(),
      description: json['description']?.toString(),
      verificationMethod: parseInt(json['verificationMethod'], 0),
      isAllMuted: json['isAllMuted'] == true,
      invitePolicy: parseInt(json['invitePolicy'], 0),
      allowJoinChannels: parseInt(json['allowJoinChannels'], 7),
      pendingJoinRequestCount: parseInt(json['pendingJoinRequestCount'], 0),
      pendingAnnouncementCount: parseInt(json['pendingAnnouncementCount'], 0),
      isCreator: json['isCreator'] == true,
      isAdmin: json['isAdmin'] == true,
      hasCreator: json['hasCreator'] == true,
      hasAdmin: json['hasAdmin'] == true,
      canClaimCreator: json['canClaimCreator'] == true,
      canEnterManagement: json['canEnterManagement'] == true,
      canManageSettings: json['canManageSettings'] == true,
      canManageJoinRequests: json['canManageJoinRequests'] == true,
      canManageAnnouncements: json['canManageAnnouncements'] == true,
      canManageMembers: json['canManageMembers'] == true,
      canManageOrgs: json['canManageOrgs'] == true,
      canManageRoles: json['canManageRoles'] == true,
      canManagePermissions: json['canManagePermissions'] == true,
      canSetAdmin: json.containsKey('canSetAdmin')
          ? json['canSetAdmin'] == true
          : json['isCreator'] == true,
      canManageNameOrDescription: json.containsKey('canManageNameOrDescription')
          ? json['canManageNameOrDescription'] == true
          : json['canManageSettings'] == true,
      canToggleAllMuted: json.containsKey('canToggleAllMuted')
          ? json['canToggleAllMuted'] == true
          : json['canManageSettings'] == true,
      canManageJoinPolicies: json.containsKey('canManageJoinPolicies')
          ? json['canManageJoinPolicies'] == true
          : json['canManageSettings'] == true,
      canTransferOrDissolve: json['canTransferOrDissolve'] == true,
    );
  }

  final String sessionId;
  final int roomId;
  final String name;
  final String? portrait;
  final String? description;
  final int verificationMethod;
  final bool isAllMuted;
  final int invitePolicy;
  final int allowJoinChannels;
  final int pendingJoinRequestCount;
  final int pendingAnnouncementCount;
  final bool isCreator;
  final bool isAdmin;
  final bool hasCreator;
  final bool hasAdmin;
  final bool canClaimCreator;
  final bool canEnterManagement;
  final bool canManageSettings;
  final bool canManageJoinRequests;
  final bool canManageAnnouncements;
  final bool canManageMembers;
  final bool canManageOrgs;
  final bool canManageRoles;
  final bool canManagePermissions;
  final bool canSetAdmin;
  final bool canManageNameOrDescription;
  final bool canToggleAllMuted;
  final bool canManageJoinPolicies;
  final bool canTransferOrDissolve;

  int get totalPendingCount =>
      canEnterManagement
          ? (pendingJoinRequestCount + pendingAnnouncementCount)
          : 0;
}

class GroupManagementApi {
  GroupManagementApi(this._client);
  final ApiClient _client;

  Future<RoomManagementSettings> getManagementSettings(
    String sessionUnitId,
  ) async {
    final json = await _client.get<Map<String, dynamic>>(
      '/api/chat/room/management-settings/${Uri.encodeComponent(sessionUnitId)}',
    );
    return RoomManagementSettings.fromJson(json);
  }

  Future<RoomManagementSettings> updatePolicies({
    required String sessionUnitId,
    int? verificationMethod,
    bool? isAllMuted,
    int? invitePolicy,
    int? allowJoinChannels,
    String? description,
  }) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/api/chat/room/update-policies',
      data: <String, Object?>{
        'sessionUnitId': sessionUnitId,
        if (verificationMethod != null)
          'verificationMethod': verificationMethod,
        if (isAllMuted != null) 'isAllMuted': isAllMuted,
        if (invitePolicy != null) 'invitePolicy': invitePolicy,
        if (allowJoinChannels != null) 'allowJoinChannels': allowJoinChannels,
        if (description != null) 'description': description,
      },
    );
    return RoomManagementSettings.fromJson(json);
  }

  Future<void> updateRoomName({
    required String sessionUnitId,
    required String name,
  }) => _client.post<Map<String, dynamic>>(
    '/api/chat/room/update-name/${Uri.encodeComponent(sessionUnitId)}',
    query: <String, Object?>{'name': name},
  );

  Future<void> transferCreator({
    required String sessionUnitId,
    required String targetSessionUnitId,
  }) => _client.post<Map<String, dynamic>>(
    '/api/chat/room/transfer-creator',
    query: <String, Object?>{
      'sessionUnitId': sessionUnitId,
      'targetSessionUnitId': targetSessionUnitId,
    },
  );

  Future<void> dissolveRoom(String sessionUnitId) =>
      _client.post<Map<String, dynamic>>(
        '/api/chat/room/dissolve/${Uri.encodeComponent(sessionUnitId)}',
      );

  Future<RoomManagementSettings> claimCreator(String sessionUnitId) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/api/chat/room/claim-creator/${Uri.encodeComponent(sessionUnitId)}',
    );
    return RoomManagementSettings.fromJson(json);
  }

  Future<List<IdNameItem>> organizations(String sessionId) async {
    final json = await _client.get<Map<String, dynamic>>(
      '/api/chat/session-organization',
      query: <String, Object?>{'SessionId': sessionId, 'MaxResultCount': 1000},
    );
    return _items(json);
  }

  Future<List<IdNameItem>> roles(String sessionId) async {
    final json = await _client.get<Map<String, dynamic>>(
      '/api/chat/session-role',
      query: <String, Object?>{'SessionId': sessionId, 'MaxResultCount': 1000},
    );
    return _items(json);
  }

  Future<List<IdNameItem>> permissionDefinitions() async {
    final json = await _client.get<Map<String, dynamic>>(
      '/api/chat/session-permission/definitions',
    );
    final result = <IdNameItem>[];
    void visit(Object? value) {
      if (value is List) {
        for (final item in value) {
          visit(item);
        }
      } else if (value is Map) {
        final map = value.cast<String, dynamic>();
        if (map['id'] != null && map['isGroup'] != true) {
          result.add(IdNameItem.fromJson(map));
        }
        visit(map['children']);
        if (map['items'] is List) visit(map['items']);
      }
    }

    visit(json['items'] ?? json['result'] ?? json);
    return result.where((item) => item.id.isNotEmpty).toList(growable: false);
  }

  Future<void> createOrganization({
    required String sessionId,
    required String name,
    String? parentId,
  }) => _client.post<Map<String, dynamic>>(
    '/api/chat/session-organization',
    data: <String, Object?>{
      'sessionId': sessionId,
      'name': name,
      if (parentId != null) 'parentId': int.tryParse(parentId),
      'sorting': 0,
    },
  );

  Future<void> deleteOrganization(String organizationId) =>
      _client.post<Map<String, dynamic>>(
        '/api/chat/session-organization/${Uri.encodeComponent(organizationId)}/delete',
      );

  Future<void> createRole({
    required String sessionId,
    required String name,
    String? sessionUnitId,
  }) =>
      _client.post<Map<String, dynamic>>(
        '/api/chat/session-role',
        data: <String, Object?>{
          'sessionId': sessionId,
          'name': name,
          if (sessionUnitId != null && sessionUnitId.isNotEmpty)
            'sessionUnitId': sessionUnitId,
        },
      );

  Future<void> deleteRole(String roleId) =>
      _client.post<Map<String, dynamic>>(
        '/api/chat/session-role/${Uri.encodeComponent(roleId)}/delete',
      );

  Future<Map<String, dynamic>> rolePermissions(String roleId) => _client
      .get<Map<String, dynamic>>('/api/chat/session-role/$roleId/permissions');

  Future<void> grantRolePermission({
    required String roleId,
    required String definitionId,
    required bool enabled,
  }) => _client.post<Map<String, dynamic>>(
    '/api/chat/session-permission/grant-by-session-role',
    query: <String, Object?>{
      'definitionId': definitionId,
      'sessionRoleId': roleId,
    },
    // PermissionGrantValue is an enum in the server contract: 1=granted,
    // 0=undefined/revoked. The server remains authoritative.
    data: enabled ? 1 : 0,
  );

  Future<void> setAllRolePermissions({
    required String roleId,
    required bool enabled,
  }) => _client.post<Map<String, dynamic>>(
    '/api/chat/session-role/${Uri.encodeComponent(roleId)}/set-all-permissions',
    data: <String, Object?>{'isEnabled': enabled, 'value': enabled ? 1 : 0},
  );

  Future<void> setAdmin(String memberSessionUnitId, bool isAdmin) =>
      _client.post<Map<String, dynamic>>(
        '/api/chat/session-unit-setting/set-admin/${Uri.encodeComponent(memberSessionUnitId)}',
        query: <String, Object?>{'isAdmin': isAdmin},
      );

  Future<Map<String, dynamic>> batchSetMemberOrganizations({
    required String sessionUnitId,
    required List<String> memberSessionUnitIds,
    required List<String> organizationIds,
    required int mode, // 0=Add, 1=Remove, 2=Replace, 3=Clear
  }) => _client.post<Map<String, dynamic>>(
    '/api/chat/session-organiztion-by-session-unit/batch-set-members',
    data: <String, Object?>{
      'sessionUnitId': sessionUnitId,
      'memberSessionUnitIdList': memberSessionUnitIds,
      'organizationIdList': organizationIds
          .map((id) => int.tryParse(id) ?? id)
          .toList(growable: false),
      'mode': mode,
    },
  );

  Future<List<IdNameItem>> organizationRoles({
    required String sessionUnitId,
    required String organizationId,
  }) async {
    final json = await _client.get<Object?>(
      '/api/chat/session-organiztion-by-session-unit/organization-roles',
      query: <String, Object?>{
        'sessionUnitId': sessionUnitId,
        'organizationId': int.tryParse(organizationId) ?? organizationId,
      },
    );
    final list = json is List ? json : (json is Map ? json['items'] : null);
    return list is List
        ? list
            .whereType<Map>()
            .map((e) => IdNameItem.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false)
        : const <IdNameItem>[];
  }

  Future<void> setOrganizationRoles({
    required String sessionUnitId,
    required String organizationId,
    required List<String> roleIds,
  }) => _client.post<Object?>(
    '/api/chat/session-organiztion-by-session-unit/set-organization-roles',
    data: <String, Object?>{
      'sessionUnitId': sessionUnitId,
      'organizationId': int.tryParse(organizationId) ?? organizationId,
      'roleIdList': roleIds,
    },
  );

  Future<Map<String, dynamic>> memberPermissionSources({
    required String sessionUnitId,
    required String targetSessionUnitId,
  }) => _client.get<Map<String, dynamic>>(
    '/api/chat/session-organiztion-by-session-unit/member-permission-sources',
    query: <String, Object?>{
      'sessionUnitId': sessionUnitId,
      'targetSessionUnitId': targetSessionUnitId,
    },
  );

  List<IdNameItem> _items(Map<String, dynamic> json) {
    final raw = json['items'];
    return raw is List
        ? raw
            .whereType<Map>()
            .map((item) => IdNameItem.fromJson(item.cast<String, dynamic>()))
            .where((item) => item.id.isNotEmpty)
            .toList(growable: false)
        : const <IdNameItem>[];
  }
}
