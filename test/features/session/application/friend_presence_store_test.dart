import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/core/realtime/signalr_gateway.dart';
import 'package:gotoim_flutter/features/contact/data/datasources/contacts_api.dart';
import 'package:gotoim_flutter/features/contact/data/models/online_friend.dart';
import 'package:gotoim_flutter/features/session/application/friend_presence_store.dart';
import 'package:gotoim_flutter/features/session/data/models/chat_owner.dart';
import 'package:gotoim_flutter/features/session/data/models/logged_in_device.dart';
import 'package:gotoim_flutter/features/session/data/repositories/session_repository.dart';

void main() {
  late _FakeSignalRGateway gateway;
  late _FakeSessionRepository repository;
  late _FakeContactsApi contactsApi;
  late FriendPresenceStore store;

  setUp(() {
    gateway = _FakeSignalRGateway();
    repository = _FakeSessionRepository();
    contactsApi = _FakeContactsApi();
    store = FriendPresenceStore(
      gateway: gateway,
      sessionRepository: repository,
      contactsApi: contactsApi,
      minimumRefreshInterval: const Duration(seconds: 10),
    );
  });

  tearDown(() {
    store.dispose();
    gateway.dispose();
  });

  test('multi-device of same type does not mark friend offline when one exits', () async {
    store.start();
    gateway.emit(SignalRConnectionState.connected);
    await Future<void>.delayed(Duration.zero);

    // Initial snapshot: friend 100 has 'phone'
    contactsApi.onlineFriends = [
      const OnlineFriend(
        ownerId: 1,
        destinationId: 100,
        sessionId: 's1',
        sessionUnitId: 'u1',
        deviceTypes: ['phone'],
      ),
    ];
    await store.refresh(force: true);

    expect(store.deviceTypesForChatObjectId(100), ['phone']);

    // Another phone device comes online for friend 100
    gateway.emitCommand(SignalRCommand.onlineFriend, {
      'chatObjectIdList': [100],
      'deviceTypes': ['phone'],
    });
    await Future<void>.delayed(Duration.zero);
    expect(store.deviceTypesForChatObjectId(100), ['phone']);

    // One phone goes offline
    gateway.emitCommand(SignalRCommand.offlineFriend, {
      'chatObjectIdList': [100],
      'deviceTypes': ['phone'],
    });
    await Future<void>.delayed(Duration.zero);

    // Count was 2, now 1 -> friend must STILL be online with 'phone'
    expect(store.deviceTypesForChatObjectId(100), ['phone']);

    // Second phone goes offline
    gateway.emitCommand(SignalRCommand.offlineFriend, {
      'chatObjectIdList': [100],
      'deviceTypes': ['phone'],
    });
    await Future<void>.delayed(Duration.zero);

    // Count is now 0 -> friend is offline
    expect(store.deviceTypesForChatObjectId(100), isEmpty);
  });

  test('multi-device with different types retains remaining device when one exits', () async {
    store.start();
    gateway.emit(SignalRConnectionState.connected);
    await Future<void>.delayed(Duration.zero);

    // Initial snapshot: friend 200 has 'pc' and 'phone'
    contactsApi.onlineFriends = [
      const OnlineFriend(
        ownerId: 1,
        destinationId: 200,
        sessionId: 's2',
        sessionUnitId: 'u2',
        deviceTypes: ['pc', 'phone'],
      ),
    ];
    await store.refresh(force: true);

    expect(store.deviceTypesForChatObjectId(200), containsAll(['pc', 'phone']));

    // Phone exits
    gateway.emitCommand(SignalRCommand.offlineFriend, {
      'chatObjectIdList': [200],
      'deviceTypes': ['phone'],
    });
    await Future<void>.delayed(Duration.zero);

    // PC is still online
    expect(store.deviceTypesForChatObjectId(200), ['pc']);
  });

  test('offlineMe triggers forced refresh even within minimum interval', () async {
    store.start();
    gateway.emit(SignalRConnectionState.connected);
    await Future<void>.delayed(Duration.zero);

    repository.onlineDevices = [
      _createDevice('conn-1', 'dev-1', 'phone', [1]),
      _createDevice('conn-2', 'dev-2', 'pc', [1]),
    ];
    await store.refresh(force: true);

    expect(store.currentOnlineDevices.length, 2);

    // Simulate device 2 disconnected on server
    repository.onlineDevices = [
      _createDevice('conn-1', 'dev-1', 'phone', [1]),
    ];

    // Receive offlineMe event
    gateway.emitCommand(SignalRCommand.offlineMe, {});

    // Wait for debounce timer (150ms)
    await Future<void>.delayed(const Duration(milliseconds: 250));

    expect(store.currentOnlineDevices.length, 1);
    expect(store.currentOnlineDevices.first.deviceId, 'dev-1');
  });
}

LoggedInDevice _createDevice(
  String connId,
  String devId,
  String type,
  List<int> chatObjectIds,
) {
  return LoggedInDevice(
    connectionId: connId,
    deviceId: devId,
    deviceType: type,
    brand: 'TestBrand',
    model: 'TestModel',
    updatedAt: DateTime.now(),
    groups: const [],
    ipAddress: '127.0.0.1',
    host: 'localhost',
    browser: '',
    browserInfo: '',
    platform: 'Android',
    chatObjectIdList: chatObjectIds,
  );
}

class _FakeSignalRGateway implements SignalRGateway {
  final StreamController<SignalRAppEvent> _events =
      StreamController<SignalRAppEvent>.broadcast();
  SignalRConnectionState _state = SignalRConnectionState.disconnected;

  @override
  Stream<SignalRAppEvent> get events => _events.stream;

  @override
  SignalRConnectionState get connectionState => _state;

  @override
  SignalRConnectionInfo get connectionInfo => SignalRConnectionInfo(
    hubUrl: 'http://test/signalr-hubs/chat',
    state: _state,
    connectionId: 'test-connection',
    keepAliveInterval: const Duration(seconds: 15),
    serverTimeout: const Duration(seconds: 30),
  );

  void emit(SignalRConnectionState state) {
    _state = state;
    _events.add(
      SignalRConnectionEvent(state: state, receivedAt: DateTime.now()),
    );
  }

  void emitCommand(SignalRCommand command, Object? payload) {
    _events.add(
      SignalRCommandEvent(
        command: command,
        envelope: <String, dynamic>{'payload': payload},
        receivedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> connect() async => emit(SignalRConnectionState.connected);

  @override
  Future<void> disconnect() async => emit(SignalRConnectionState.disconnected);

  @override
  Future<T?> invoke<T>(String method, {List<Object>? arguments}) async => null;

  @override
  Future<void> dispose() => _events.close();
}

class _FakeContactsApi extends ContactsApi {
  _FakeContactsApi() : super(_FakeApiClient());

  List<OnlineFriend> onlineFriends = [];

  @override
  Future<List<OnlineFriend>> getOnlineFriends({required int ownerId}) async {
    return onlineFriends;
  }
}

class _FakeApiClient implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSessionRepository implements SessionRepository {
  List<LoggedInDevice> onlineDevices = [];

  @override
  Future<ChatOwner> resolveCurrentOwner() async => const ChatOwner(
    id: 1,
    name: 'Owner 1',
    imageUrl: null,
    typeDescription: 'User',
  );

  @override
  Future<List<LoggedInDevice>> loadOnlineDevices() async => onlineDevices;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
