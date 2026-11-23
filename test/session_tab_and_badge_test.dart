import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/device/client_device_context.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/core/realtime/signalr_gateway.dart';
import 'package:gotoim_flutter/features/chat/application/ai_stream_change_bus.dart';
import 'package:gotoim_flutter/features/group/data/room_api.dart';
import 'package:gotoim_flutter/features/session/application/friend_presence_store.dart';
import 'package:gotoim_flutter/features/session/application/realtime_sync_coordinator.dart';
import 'package:gotoim_flutter/features/session/application/session_list_controller.dart';
import 'package:gotoim_flutter/features/session/data/datasources/session_dao.dart';
import 'package:gotoim_flutter/features/session/data/models/chat_object_type.dart';
import 'package:gotoim_flutter/features/session/data/models/chat_owner.dart';
import 'package:gotoim_flutter/features/session/data/models/logged_in_device.dart';
import 'package:gotoim_flutter/features/session/data/models/session_summary.dart';
import 'package:gotoim_flutter/features/session/data/repositories/session_repository.dart';
import 'package:gotoim_flutter/features/session/data/session_change_bus.dart';
import 'package:gotoim_flutter/features/session/presentation/session_category_tabs.dart';
import 'package:gotoim_flutter/features/session/presentation/session_list_skeleton.dart';

class _FakeSignalRGateway extends Fake implements SignalRGateway {
  final StreamController<SignalRAppEvent> controller =
      StreamController<SignalRAppEvent>.broadcast(sync: true);

  @override
  SignalRConnectionState get connectionState =>
      SignalRConnectionState.connected;

  @override
  Stream<SignalRAppEvent> get events => controller.stream;

  @override
  Future<void> dispose() => controller.close();
}

class _FakeFriendPresenceStore extends ChangeNotifier
    implements FriendPresenceStore {
  @override
  Future<void> activateOwner(int? ownerId) async {}

  @override
  Future<void> refresh({bool force = false}) async {}

  @override
  List<LoggedInDevice> get currentOnlineDevices => const [];

  @override
  List<LoggedInDevice> onlineDevicesForChatObjectId(int? chatObjectId) =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSessionRepository extends Fake implements SessionRepository {
  _FakeSessionRepository({
    required this.owners,
    required this.pages,
  });

  final List<ChatOwner> owners;
  final List<LoadFriendsResult> pages;
  int pageCalls = 0;

  @override
  Future<int?> readCurrentOwnerId() async => owners.first.id;

  @override
  Future<void> saveCurrentOwnerId(int ownerId) async {}

  @override
  Future<List<ChatOwner>> loadLocalOwners() async => owners;

  @override
  Future<List<ChatOwner>> loadOwners() async => owners;

  @override
  Future<List<SessionSummary>> loadLocalFriends({
    required int ownerId,
    SessionCursor? cursor,
    int limit = 50,
  }) async => const <SessionSummary>[];

  @override
  Future<LoadFriendsResult> loadFriends({
    required int ownerId,
    SessionCursor? cursor,
    int limit = 50,
  }) async {
    final idx = pageCalls++;
    if (idx < pages.length) return pages[idx];
    return const LoadFriendsResult(items: <SessionSummary>[], hasMore: false);
  }

  @override
  Future<List<LoggedInDevice>> loadDevices() async => const [];

  @override
  Future<Map<int, ({int unread, int immersed})>> loadOverviewBadges() async =>
      const {};

  @override
  Future<List<SessionSummary>> loadChanges({required int ownerId}) async =>
      const [];

  @override
  Future<void> syncDisposals({required int ownerId}) async {}

  @override
  Future<List<Map<String, dynamic>>> loadActiveAiRuns(
    Iterable<String> sessionUnitIds,
  ) async => const [];
}

class _FakeMultipartApiClient extends Fake implements ApiClient {
  String? lastPath;
  String? lastFieldName;
  MultipartUploadFile? lastFile;

  @override
  Future<T> postMultipart<T>(
    String path, {
    Map<String, Object?>? query,
    Map<String, Object?>? extraFields,
    required MultipartUploadFile file,
    String fieldName = 'file',
    void Function(int sent, int total)? onProgress,
    bool retryOnUnauthorized = true,
  }) async {
    lastPath = path;
    lastFieldName = fieldName;
    lastFile = file;
    return <String, dynamic>{'id': 6024, 'portrait': '/new-room.jpg'} as T;
  }
}

SessionSummary _makeSession(
  String id,
  int objectType, {
  int unread = 0,
  bool isImmersed = false,
  int score = 100,
}) {
  return SessionSummary.fromJson(<String, dynamic>{
    'id': id,
    'ownerId': 14,
    'score': score,
    'ticks': score,
    'publicBadge': unread,
    'destination': <String, dynamic>{
      'id': int.tryParse(id.replaceAll(RegExp('[^0-9]'), '')) ?? 1,
      'displayName': '会话 $id',
      'objectType': objectType,
    },
    'setting': <String, dynamic>{'isImmersed': isImmersed},
  });
}

ClientDeviceContext _testDeviceContext() => const ClientDeviceContext(
  appId: 'app',
  appName: 'GotoIM',
  appVersion: '1.0.0',
  deviceId: 'dev-1',
  deviceType: 'Desktop',
  platform: 'windows',
  brand: 'PC',
  model: 'PC',
  browser: '',
  pushClientId: '',
);

void main() {
  test('chatObjectTypeLabel 与 ChatOwner.displayTypeDescription 正确映射对象类型', () {
    expect(chatObjectTypeLabel(ChatObjectTypeValues.anonymous), '匿名');
    expect(chatObjectTypeLabel(ChatObjectTypeValues.personal), '个人');
    expect(chatObjectTypeLabel(ChatObjectTypeValues.room), '群聊');
    expect(chatObjectTypeLabel(ChatObjectTypeValues.official), '服务号');
    expect(chatObjectTypeLabel(ChatObjectTypeValues.subscription), '订阅号');
    expect(chatObjectTypeLabel(ChatObjectTypeValues.square), '广场');
    expect(chatObjectTypeLabel(ChatObjectTypeValues.robot), '机器人');
    expect(chatObjectTypeLabel(ChatObjectTypeValues.shopKeeper), '掌柜');
    expect(chatObjectTypeLabel(ChatObjectTypeValues.shopWaiter), '店小二');
    expect(chatObjectTypeLabel(ChatObjectTypeValues.customer), '客户');

    // 当 typeDescription 为空或纯数字 '1' 时，自动映射为“个人”，不能误显为“官方客服”
    const numericDescOwner = ChatOwner(
      id: 14,
      name: '林惠娟',
      imageUrl: null,
      typeDescription: '1',
      objectType: 1,
    );
    expect(numericDescOwner.displayTypeDescription, '个人');

    const emptyDescOwner = ChatOwner(
      id: 13,
      name: '测试掌柜',
      imageUrl: null,
      typeDescription: '',
      objectType: 7,
    );
    expect(emptyDescOwner.displayTypeDescription, '掌柜');

    const explicitDescOwner = ChatOwner(
      id: 15,
      name: '客服专员',
      imageUrl: null,
      typeDescription: '企业客服',
      objectType: 7,
    );
    expect(explicitDescOwner.displayTypeDescription, '企业客服');

    final fromDbRow = ChatOwner.fromDatabaseRow(<String, Object?>{
      'id': 14,
      'name': '林惠娟',
      'objectType': '1',
    });
    expect(fromDbRow.displayTypeDescription, '个人');
  });

  test('SessionSummary.isGroup 仅将群聊(2)判定为群聊而非单聊(1)', () {
    final direct = _makeSession('u1', ChatObjectTypeValues.personal);
    expect(direct.destinationObjectType, 1);
    expect(direct.isGroup, isFalse);

    final rootDirectOnly = SessionSummary.fromJson(<String, dynamic>{
      'id': 'u-root-1',
      'ownerId': 14,
      'objectType': 1,
    });
    expect(rootDirectOnly.isGroup, isFalse);

    final room = _makeSession('u2', ChatObjectTypeValues.room);
    expect(room.destinationObjectType, 2);
    expect(room.isGroup, isTrue);
  });

  test('splitSessionCategoryTabs 在窄宽下折叠为更多菜单并汇总隐藏 Tab 角标总和', () {
    final unreadCounts = <SessionTabKey, int>{
      SessionTabKey.all: 15,
      SessionTabKey.direct: 2,
      SessionTabKey.room: 3,
      SessionTabKey.square: 4,
      SessionTabKey.subscription: 1,
      SessionTabKey.official: 2,
      SessionTabKey.robot: 0,
      SessionTabKey.customer: 3,
    };

    // 1. 宽容器全部容纳，无更多按钮
    final wide = splitSessionCategoryTabs(
      availableWidth: 800,
      unreadCounts: unreadCounts,
      measureTabWidth: (item, unread) => 48.0 + (unread > 0 ? 20.0 : 0.0),
      measureMoreWidth: (_) => 60.0,
    );
    expect(wide.visible.length, kSessionCategoryTabs.length);
    expect(wide.overflow, isEmpty);
    expect(wide.overflowUnread, 0);

    // 2. 窄容器（260px）自动折叠后半部分 Tab，更多角标等于隐藏角标之和
    final narrow = splitSessionCategoryTabs(
      availableWidth: 260,
      unreadCounts: unreadCounts,
      measureTabWidth: (item, unread) => 48.0 + (unread > 0 ? 20.0 : 0.0),
      measureMoreWidth: (overflowUnread) => overflowUnread > 0 ? 78.0 : 58.0,
    );
    expect(narrow.visible, isNotEmpty);
    expect(narrow.overflow, isNotEmpty);
    final expectedHiddenSum = narrow.overflow.fold<int>(
      0,
      (sum, t) => sum + (unreadCounts[t.key] ?? 0),
    );
    expect(narrow.overflowUnread, expectedHiddenSum);
    expect(narrow.overflowUnread, greaterThan(0));
  });

  test('SessionListController 支持分类过滤、免打扰角标剔除及不足一页自动补齐', () async {
    final gateway = _FakeSignalRGateway();
    final repo = _FakeSessionRepository(
      owners: const [
        ChatOwner(
          id: 14,
          name: '林惠娟',
          imageUrl: null,
          typeDescription: '个人',
          objectType: 1,
        ),
      ],
      pages: [
        LoadFriendsResult(
          items: [
            _makeSession('d1', ChatObjectTypeValues.personal, unread: 2, score: 200),
            _makeSession('d2', ChatObjectTypeValues.personal, unread: 5, isImmersed: true, score: 199),
            _makeSession('r1', ChatObjectTypeValues.room, unread: 3, score: 198),
            _makeSession('s1', ChatObjectTypeValues.square, unread: 1, score: 197),
          ],
          hasMore: true,
        ),
        LoadFriendsResult(
          items: [
            for (var i = 2; i <= 14; i++)
              _makeSession('r$i', ChatObjectTypeValues.room, score: 150 - i),
          ],
          hasMore: true,
        ),
      ],
    );
    final controller = SessionListController(
      repo,
      gateway,
      _testDeviceContext(),
      SessionChangeBus(),
      AiStreamChangeBus(),
      _FakeFriendPresenceStore(),
    );
    addTearDown(() async {
      controller.dispose();
      await gateway.dispose();
    });

    await controller.initialize();
    expect(controller.sessions.length, 4);
    expect(controller.tabUnreadCounts[SessionTabKey.direct], 2); // 忽略免打扰 d2
    expect(controller.tabUnreadCounts[SessionTabKey.room], 3);
    expect(controller.tabUnreadCounts[SessionTabKey.square], 1);
    expect(controller.tabUnreadCounts[SessionTabKey.all], 6);

    // 切到“群聊”Tab 时仅有 1 条（<12），应自动触发第 2 页加载直至 >=12 条
    controller.setSessionTab(SessionTabKey.room);
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(controller.activeTab, SessionTabKey.room);
    expect(controller.tabFilteredSessions.length, 14);
    expect(repo.pageCalls, 2);
  });

  test('SignalR created@message 携带 scopes 时排除发送人自身并对其他身份角标乐观 +1', () async {
    final gateway = _FakeSignalRGateway();
    final repo = _FakeSessionRepository(
      owners: const [
        ChatOwner(
          id: 14,
          name: '林惠娟',
          imageUrl: null,
          typeDescription: '个人',
          objectType: 1,
          unreadCount: 0,
        ),
        ChatOwner(
          id: 13,
          name: '测试身份13',
          imageUrl: null,
          typeDescription: '个人',
          objectType: 1,
          unreadCount: 3,
        ),
      ],
      pages: const [
        LoadFriendsResult(items: <SessionSummary>[], hasMore: false),
      ],
    );
    final controller = SessionListController(
      repo,
      gateway,
      _testDeviceContext(),
      SessionChangeBus(),
      AiStreamChangeBus(),
      _FakeFriendPresenceStore(),
    );
    addTearDown(() async {
      controller.dispose();
      await gateway.dispose();
    });

    await controller.initialize();
    expect(controller.currentOwner?.id, 14);
    expect(controller.otherUnreadCount, 3);

    // 发送人 14 给 13 发消息：scopes 同时包含 14 和 13；应排除 senderSessionUnitId 自身与当前身份 14，仅 13 角标 +1 -> 4
    gateway.controller.add(
      SignalRCommandEvent(
        command: SignalRCommand.messageCreated,
        envelope: {
          'scopes': [
            {
              'sessionUnitId': '47088610-8ca4-2c24-75c8-3a0aab123a9d',
              'chatObjectId': '14',
            },
            {
              'sessionUnitId': '79cc7a06-05c6-04ea-7087-3a0aab123a9d',
              'chatObjectId': '13',
            },
          ],
          'payload': {
            'command': 'created@message',
            'message': {
              'id': 7318673,
              'senderSessionUnitId': '47088610-8ca4-2c24-75c8-3a0aab123a9d',
            },
          },
        },
        receivedAt: DateTime.now(),
      ),
    );

    expect(controller.otherUnreadCount, 4);
    expect(
      controller.owners.firstWhere((o) => o.id == 13).unreadCount,
      4,
    );
    expect(
      controller.owners.firstWhere((o) => o.id == 14).unreadCount,
      0,
    );
  });

  test('RoomApi.uploadPortrait 调用群头像专属端点且 RealtimeSyncCoordinator 识别 UpdatePortrait', () async {
    final client = _FakeMultipartApiClient();
    final roomApi = RoomApi(client);
    const sessionUnitId = 'unit-room-uuid-1';

    await roomApi.uploadPortrait(
      sessionUnitId: sessionUnitId,
      file: MultipartUploadFile(
        name: 'avatar.jpg',
        length: 3,
        openRead: () => Stream<List<int>>.value([1, 2, 3]),
      ),
    );

    expect(
      client.lastPath,
      '/api/chat/room/upload-portrait/unit-room-uuid-1',
    );
    expect(client.lastFieldName, 'file');

    expect(
      RealtimeSyncCoordinator.isUpdatePortraitPayload({
        'message': {
          'keyName': 'UpdatePortrait',
          'content': {'cmd': 'UpdatePortrait', 'text': "张三 更新群头像:'研发群'"},
        },
      }),
      isTrue,
    );
    expect(
      RealtimeSyncCoordinator.isUpdatePortraitPayload({
        'message': {
          'content': {'text': '普通文本消息'},
        },
      }),
      isFalse,
    );
  });

  testWidgets('SessionCategoryTabs 与 SessionListSkeleton 在窄屏下无溢出且角标总和正确', (
    tester,
  ) async {
    SessionTabKey active = SessionTabKey.all;
    final counts = <SessionTabKey, int>{
      SessionTabKey.all: 15,
      SessionTabKey.direct: 2,
      SessionTabKey.room: 3,
      SessionTabKey.square: 4,
      SessionTabKey.subscription: 1,
      SessionTabKey.official: 2,
      SessionTabKey.robot: 0,
      SessionTabKey.customer: 3,
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 260,
            child: StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  SessionCategoryTabs(
                    activeTab: active,
                    tabUnreadCounts: counts,
                    onSelectTab: (t) => setState(() => active = t),
                  ),
                  const SessionListSkeleton(itemCount: 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('全部'), findsOneWidget);
    expect(find.text('更多'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
