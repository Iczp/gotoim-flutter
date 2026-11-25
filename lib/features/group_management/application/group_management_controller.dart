import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/application_providers.dart';
import '../data/group_management_api.dart';

final groupManagementApiProvider = Provider<GroupManagementApi>(
  (ref) => GroupManagementApi(ref.watch(apiClientProvider)),
);

class GroupManagementController extends ChangeNotifier {
  GroupManagementController(
    this._api,
    this.sessionId, {
    this.sessionUnitId,
  });

  final GroupManagementApi _api;
  final String sessionId;
  final String? sessionUnitId;

  RoomManagementSettings? settings;
  List<IdNameItem> organizations = const [];
  List<IdNameItem> roles = const [];
  List<IdNameItem> permissions = const [];
  Set<String> grantedPermissionIds = <String>{};
  String? selectedRoleId;
  bool loading = false;
  bool updating = false;
  Object? error;

  Future<void> initialize() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      RoomManagementSettings? loadedSettings;
      if (sessionUnitId != null && sessionUnitId!.isNotEmpty) {
        loadedSettings = await _api.getManagementSettings(sessionUnitId!);
      }
      settings = loadedSettings;

      final effectiveSessionUnitId =
          (sessionUnitId != null && sessionUnitId!.isNotEmpty)
              ? sessionUnitId!
              : (loadedSettings?.sessionId.isNotEmpty == true
                  ? loadedSettings!.sessionId
                  : sessionId);

      final canOrgs =
          loadedSettings == null ||
          loadedSettings.canManageOrgs ||
          loadedSettings.canManageMembers;
      final canRoles =
          loadedSettings == null ||
          loadedSettings.canManageRoles ||
          loadedSettings.canManagePermissions;
      final canDefs =
          loadedSettings == null ||
          loadedSettings.canManagePermissions ||
          loadedSettings.canManageRoles;

      final values = await Future.wait(<Future<List<IdNameItem>>>[
        canOrgs && effectiveSessionUnitId.isNotEmpty
            ? _api
                .organizations(effectiveSessionUnitId)
                .catchError((_) => const <IdNameItem>[])
            : Future<List<IdNameItem>>.value(const <IdNameItem>[]),
        canRoles && effectiveSessionUnitId.isNotEmpty
            ? _api
                .roles(effectiveSessionUnitId)
                .catchError((_) => const <IdNameItem>[])
            : Future<List<IdNameItem>>.value(const <IdNameItem>[]),
        canDefs
            ? _api
                .permissionDefinitions()
                .catchError((_) => const <IdNameItem>[])
            : Future<List<IdNameItem>>.value(const <IdNameItem>[]),
      ]);
      organizations = values[0];
      roles = values[1];
      permissions = values[2];
      if (roles.isNotEmpty) {
        final targetRole =
            selectedRoleId != null && roles.any((r) => r.id == selectedRoleId)
                ? selectedRoleId!
                : roles.first.id;
        await selectRole(targetRole, silent: true);
      }
    } catch (exception) {
      error = exception;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refreshSettingsOnly() async {
    if (sessionUnitId == null || sessionUnitId!.isEmpty) return;
    try {
      settings = await _api.getManagementSettings(sessionUnitId!);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> updateBasicInfo({
    String? roomName,
    String? description,
    bool? isAllMuted,
  }) async {
    final unitId = sessionUnitId;
    if (unitId == null || unitId.isEmpty) return;
    await _update(() async {
      if (roomName != null &&
          roomName.trim().isNotEmpty &&
          roomName.trim() != settings?.name) {
        await _api.updateRoomName(sessionUnitId: unitId, name: roomName.trim());
      }
      settings = await _api.updatePolicies(
        sessionUnitId: unitId,
        description: description,
        isAllMuted: isAllMuted,
      );
    });
  }

  Future<void> updateJoinPolicies({
    required int verificationMethod,
    required int invitePolicy,
    required int allowJoinChannels,
  }) async {
    final unitId = sessionUnitId;
    if (unitId == null || unitId.isEmpty) return;
    await _update(() async {
      settings = await _api.updatePolicies(
        sessionUnitId: unitId,
        verificationMethod: verificationMethod,
        invitePolicy: invitePolicy,
        allowJoinChannels: allowJoinChannels,
      );
    });
  }

  Future<void> transferCreator(String targetSessionUnitId) async {
    final unitId = sessionUnitId;
    if (unitId == null || unitId.isEmpty) return;
    await _update(
      () => _api.transferCreator(
        sessionUnitId: unitId,
        targetSessionUnitId: targetSessionUnitId,
      ),
    );
  }

  Future<void> dissolveRoom() async {
    final unitId = sessionUnitId;
    if (unitId == null || unitId.isEmpty) return;
    await _update(() => _api.dissolveRoom(unitId));
  }

  String get _effectiveUnitId =>
      (sessionUnitId != null && sessionUnitId!.isNotEmpty)
          ? sessionUnitId!
          : (settings?.sessionId.isNotEmpty == true
              ? settings!.sessionId
              : sessionId);

  Future<void> createOrganization(String name, {String? parentId}) async {
    final unitId = _effectiveUnitId;
    if (unitId.isEmpty) return;
    await _update(
      () => _api.createOrganization(
        sessionUnitId: unitId,
        name: name,
        parentId: parentId,
      ),
    );
    await initialize();
  }

  Future<void> deleteOrganization(String organizationId) async {
    final unitId = _effectiveUnitId;
    if (unitId.isEmpty) return;
    await _update(
      () => _api.deleteOrganization(organizationId, sessionUnitId: unitId),
    );
    await initialize();
  }

  Future<void> createRole(String name) async {
    final unitId = _effectiveUnitId;
    if (unitId.isEmpty) return;
    await _update(
      () => _api.createRole(sessionUnitId: unitId, name: name),
    );
    await initialize();
  }

  Future<void> deleteRole(String roleId) async {
    final unitId = _effectiveUnitId;
    if (unitId.isEmpty) return;
    await _update(() => _api.deleteRole(roleId, sessionUnitId: unitId));
    await initialize();
  }

  Future<void> selectRole(String roleId, {bool silent = false}) async {
    final unitId = _effectiveUnitId;
    if (unitId.isEmpty) return;
    selectedRoleId = roleId;
    if (!silent) notifyListeners();
    final json = await _api.rolePermissions(roleId, sessionUnitId: unitId);
    final grants = json['permissionGrant'];
    grantedPermissionIds =
        grants is Map
            ? grants.entries
                .where((entry) => _isGranted(entry.value))
                .map((entry) => entry.key.toString())
                .toSet()
            : <String>{};
    if (!silent) notifyListeners();
  }

  Future<void> togglePermission(IdNameItem permission, bool enabled) async {
    final roleId = selectedRoleId;
    final unitId = _effectiveUnitId;
    if (roleId == null || unitId.isEmpty) return;
    await _update(
      () => _api.grantRolePermission(
        roleId: roleId,
        definitionId: permission.id,
        enabled: enabled,
        operatorSessionUnitId: unitId,
      ),
    );
    if (enabled) {
      grantedPermissionIds.add(permission.id);
    } else {
      grantedPermissionIds.remove(permission.id);
    }
    notifyListeners();
  }

  Future<void> setAllPermissions(bool enabled) async {
    final roleId = selectedRoleId;
    final unitId = _effectiveUnitId;
    if (roleId == null || unitId.isEmpty) return;
    await _update(
      () => _api.setAllRolePermissions(
        roleId: roleId,
        sessionUnitId: unitId,
        enabled: enabled,
      ),
    );
    if (enabled) {
      grantedPermissionIds = permissions.map((p) => p.id).toSet();
    } else {
      grantedPermissionIds.clear();
    }
    notifyListeners();
  }

  bool _isGranted(Object? value) =>
      value is num
          ? value.toInt() == 1
          : value == true || value.toString() == '1';

  Future<void> _update(Future<void> Function() action) async {
    if (updating) return;
    updating = true;
    error = null;
    notifyListeners();
    try {
      await action();
    } catch (exception) {
      error = exception;
      rethrow;
    } finally {
      updating = false;
      notifyListeners();
    }
  }
}
