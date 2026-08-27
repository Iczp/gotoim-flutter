import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/chat_settings_controller.dart';
import '../application/member_list_controller.dart';
import 'member_tile.dart';

class MemberListPage extends ConsumerStatefulWidget {
  const MemberListPage({
    required this.ownerId,
    required this.sessionUnitId,
    super.key,
  });
  final int ownerId;
  final String sessionUnitId;

  @override
  ConsumerState<MemberListPage> createState() => _MemberListPageState();
}

class _MemberListPageState extends ConsumerState<MemberListPage> {
  late final MemberListController controller;
  final search = TextEditingController();

  @override
  void initState() {
    super.initState();
    controller = MemberListController(
      ref.read(chatSettingsRepositoryProvider),
      ownerId: widget.ownerId,
      sessionUnitId: widget.sessionUnitId,
    )..initialize();
  }

  @override
  void dispose() {
    controller.dispose();
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder:
        (context, _) => Scaffold(
          appBar: AppBar(title: const Text('成员列表')),
          body: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: SearchBar(
                  controller: search,
                  hintText: '搜索成员',
                  leading: const Icon(Icons.search),
                  trailing:
                      search.text.isEmpty
                          ? const <Widget>[]
                          : <Widget>[
                            IconButton(
                              onPressed: () {
                                search.clear();
                                controller.search('');
                              },
                              icon: const Icon(Icons.close),
                            ),
                          ],
                  onSubmitted: controller.search,
                ),
              ),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification.metrics.extentAfter < 180) {
                      controller.loadMore();
                    }
                    return false;
                  },
                  child: ListView.builder(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: controller.members.length + 1,
                    itemBuilder: (context, index) {
                      if (index < controller.members.length) {
                        return MemberTile(member: controller.members[index]);
                      }
                      if (controller.loading) {
                        return const Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (controller.error != null) {
                        return TextButton(
                          onPressed: controller.loadMore,
                          child: Text('加载失败，点击重试：${controller.error}'),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.all(20),
                        child: Center(
                          child: Text('共有 ${controller.totalCount} 人'),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
  );
}
