import '../../../core/network/api_client.dart';

class IdNameItem {
  const IdNameItem({required this.id, required this.name, this.parentId});
  factory IdNameItem.fromJson(Map<String, dynamic> json) => IdNameItem(
    id: json['id']?.toString() ?? '',
    name: (json['name'] ?? json['title'] ?? json['value'] ?? '-').toString(),
    parentId: json['parentId']?.toString(),
  );
  final String id;
  final String name;
  final String? parentId;
}

class GroupManagementApi {
  GroupManagementApi(this._client);
  final ApiClient _client;

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
        for (final item in value) visit(item);
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

  Future<void> createRole({required String sessionId, required String name}) =>
      _client.post<Map<String, dynamic>>(
        '/api/chat/session-role/$sessionId',
        query: <String, Object?>{'name': name},
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

  List<IdNameItem> _items(Map<String, dynamic> json) {
    final raw = json['items'];
    return raw is List
        ? raw
            .whereType<Map>()
            .map((item) => IdNameItem.fromJson(item.cast<String, dynamic>()))
            .toList(growable: false)
        : const <IdNameItem>[];
  }
}
