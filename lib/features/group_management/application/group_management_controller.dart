import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/application_providers.dart';
import '../data/group_management_api.dart';

final groupManagementApiProvider = Provider<GroupManagementApi>(
  (ref) => GroupManagementApi(ref.watch(apiClientProvider)),
);

class GroupManagementController extends ChangeNotifier {
  GroupManagementController(this._api, this.sessionId);
  final GroupManagementApi _api;
  final String sessionId;
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
      final values = await Future.wait(<Future<List<IdNameItem>>>[
        _api.organizations(sessionId),
        _api.roles(sessionId),
        _api.permissionDefinitions(),
      ]);
      organizations = values[0];
      roles = values[1];
      permissions = values[2];
      if (roles.isNotEmpty) await selectRole(roles.first.id, silent: true);
    } catch (exception) {
      error = exception;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> createOrganization(String name, {String? parentId}) async {
    await _update(
      () => _api.createOrganization(
        sessionId: sessionId,
        name: name,
        parentId: parentId,
      ),
    );
    await initialize();
  }

  Future<void> createRole(String name) async {
    await _update(() => _api.createRole(sessionId: sessionId, name: name));
    await initialize();
  }

  Future<void> selectRole(String roleId, {bool silent = false}) async {
    selectedRoleId = roleId;
    if (!silent) notifyListeners();
    final json = await _api.rolePermissions(roleId);
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
    if (roleId == null) return;
    await _update(
      () => _api.grantRolePermission(
        roleId: roleId,
        definitionId: permission.id,
        enabled: enabled,
      ),
    );
    if (enabled) {
      grantedPermissionIds.add(permission.id);
    } else {
      grantedPermissionIds.remove(permission.id);
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
