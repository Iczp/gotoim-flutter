import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/group_management_controller.dart';
import '../data/group_management_api.dart';

class GroupManagementPage extends ConsumerStatefulWidget {
  const GroupManagementPage({required this.sessionId, super.key});
  final String sessionId;
  @override
  ConsumerState<GroupManagementPage> createState() =>
      _GroupManagementPageState();
}

class _GroupManagementPageState extends ConsumerState<GroupManagementPage> {
  late final GroupManagementController controller;
  @override
  void initState() {
    super.initState();
    controller = GroupManagementController(
      ref.read(groupManagementApiProvider),
      widget.sessionId,
    )..initialize();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder:
        (context, _) => DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('群管理'),
              bottom: const TabBar(
                tabs: <Widget>[
                  Tab(text: '组织部门'),
                  Tab(text: '角色'),
                  Tab(text: '权限'),
                ],
              ),
            ),
            floatingActionButton: _addButton(),
            body:
                controller.loading
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
                      children: <Widget>[
                        _organizations(),
                        _roles(),
                        _permissions(),
                      ],
                    ),
          ),
        ),
  );

  Widget? _addButton() => FloatingActionButton.small(
    tooltip: '新增',
    onPressed: () async {
      final tab = DefaultTabController.of(context).index;
      if (tab == 2) return;
      final name = await _nameDialog(tab == 0 ? '新建部门' : '新建角色');
      if (name == null) return;
      try {
        tab == 0
            ? await controller.createOrganization(name)
            : await controller.createRole(name);
      } catch (_) {}
    },
    child: const Icon(Icons.add),
  );

  Widget _organizations() => _list(
    controller.organizations,
    empty: '暂无部门',
    item:
        (item) => ListTile(
          leading: const Icon(Icons.account_tree_outlined),
          title: Text(item.name),
          subtitle: Text('ID: ${item.id}'),
          trailing: IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加子部门',
            onPressed: () async {
              final name = await _nameDialog('新建子部门');
              if (name != null) {
                try {
                  await controller.createOrganization(name, parentId: item.id);
                } catch (_) {}
              }
            },
          ),
        ),
  );

  Widget _roles() => _list(
    controller.roles,
    empty: '暂无角色',
    item:
        (item) => RadioListTile<String>(
          value: item.id,
          groupValue: controller.selectedRoleId,
          onChanged:
              controller.updating
                  ? null
                  : (value) {
                    if (value != null) controller.selectRole(value);
                  },
          title: Text(item.name),
          subtitle: Text('ID: ${item.id}'),
        ),
  );

  Widget _permissions() {
    if (controller.selectedRoleId == null)
      return const Center(child: Text('请先创建并选择角色'));
    return _list(
      controller.permissions,
      empty: '暂无权限定义',
      item:
          (item) => CheckboxListTile(
            value: controller.grantedPermissionIds.contains(item.id),
            onChanged:
                controller.updating
                    ? null
                    : (value) =>
                        controller.togglePermission(item, value ?? false),
            title: Text(item.name),
            subtitle: Text('ID: ${item.id}'),
          ),
    );
  }

  Widget _list(
    List<IdNameItem> items, {
    required String empty,
    required Widget Function(IdNameItem item) item,
  }) => RefreshIndicator(
    onRefresh: controller.initialize,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: <Widget>[
        if (controller.error != null)
          MaterialBanner(
            content: Text('操作失败：${controller.error}'),
            actions: <Widget>[
              TextButton(
                onPressed: controller.initialize,
                child: const Text('重试'),
              ),
            ],
          ),
        if (items.isEmpty)
          SizedBox(height: 240, child: Center(child: Text(empty)))
        else
          ...items.map(item),
      ],
    ),
  );

  Future<String?> _nameDialog(String title) async {
    final input = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(title),
            content: TextField(
              controller: input,
              autofocus: true,
              decoration: const InputDecoration(hintText: '名称'),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, input.text.trim()),
                child: const Text('保存'),
              ),
            ],
          ),
    );
    input.dispose();
    return result?.isEmpty == true ? null : result;
  }
}
