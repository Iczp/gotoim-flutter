import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../app/application_providers.dart';
import '../../../core/realtime/signalr_gateway.dart';
import '../../auth/application/auth_controller.dart';
import '../../session/application/session_list_controller.dart';
import '../../session/data/models/session_summary.dart';
import '../../session/data/repositories/session_repository.dart';
import '../data/datasources/contacts_api.dart';
import '../data/models/contact_group.dart';
import '../data/repositories/contacts_repository.dart';

final contactsRepositoryProvider = Provider<ContactsRepository>(
  (ref) => ContactsRepository(
    ContactsApi(ref.watch(apiClientProvider)),
    ref.watch(unifiedDatabaseProvider),
  ),
);

final contactsControllerProvider = ChangeNotifierProvider<ContactsController>(
  (ref) => ContactsController(
    contactsRepository: ref.watch(contactsRepositoryProvider),
    sessionRepository: ref.watch(sessionRepositoryProvider),
    signalRGateway: ref.watch(signalRGatewayProvider),
  ),
);

class ContactsController extends ChangeNotifier {
  ContactsController({
    required ContactsRepository contactsRepository,
    required SessionRepository sessionRepository,
    required SignalRGateway signalRGateway,
  }) : _contactsRepository = contactsRepository,
       _sessionRepository = sessionRepository {
    _signalSubscription = signalRGateway.events.listen((event) {
      if (event is! SignalRCommandEvent) return;
      switch (event.command) {
        case SignalRCommand.offlineMe:
          _clearOnlineFriends();
          _scheduleOnlineFriendsRefresh();
          break;
        case SignalRCommand.onlineMe:
        case SignalRCommand.onlineFriend:
        case SignalRCommand.offlineFriend:
          // Events can arrive out of order. The delayed endpoint refresh is
          // authoritative and settles the final state after a burst.
          _scheduleOnlineFriendsRefresh();
          break;
        default:
          break;
      }
    });
  }

  final ContactsRepository _contactsRepository;
  final SessionRepository _sessionRepository;
  late final StreamSubscription<SignalRAppEvent> _signalSubscription;
  Timer? _onlineRefreshTimer;
  List<ContactGroup> _groups = const <ContactGroup>[];
  int? _ownerId;
  bool isLoading = false;
  bool isRefreshing = false;
  Object? error;
  Map<String, List<String>> _onlineDeviceTypes = const <String, List<String>>{};

  List<ContactGroup> get groups => List.unmodifiable(_groups);
  int get totalCount => _groups.fold(0, (total, group) => total + group.count);
  int? get ownerId => _ownerId;
  List<String> onlineDeviceTypes(String sessionUnitId) =>
      _onlineDeviceTypes[sessionUnitId] ?? const <String>[];

  Future<void> initialize(int? ownerId) async {
    if (ownerId == null ||
        (_ownerId == ownerId && (_groups.isNotEmpty || isLoading))) {
      return;
    }
    _ownerId = ownerId;
    _groups = const <ContactGroup>[];
    error = null;
    isLoading = true;
    notifyListeners();

    var local = const <ContactGroup>[];
    try {
      local = await _loadLocal(ownerId);
    } catch (exception) {
      if (_ownerId == ownerId) {
        error = exception;
        debugPrint(
          '[contacts][local-failed] ownerId=$ownerId error=$exception',
        );
      }
    }
    if (_ownerId != ownerId) return;
    if (local.isNotEmpty) {
      _groups = local;
      debugPrint(
        '[contacts][local] ownerId=$ownerId groups=${local.length} total=$totalCount',
      );
      notifyListeners();
    }
    try {
      final remote = await _contactsRepository.loadIndexedFriends(
        ownerId: ownerId,
      );
      if (_ownerId != ownerId) return;
      _groups = remote;
      await _contactsRepository.saveIndexedFriends(
        ownerId: ownerId,
        groups: remote,
      );
      await _sessionRepository.mergeContactIdentitySnapshots(
        ownerId: ownerId,
        snapshots: remote.expand(
          (group) => group.contacts.map((contact) => contact.raw),
        ),
      );
      debugPrint(
        '[contacts][remote] ownerId=$ownerId groups=${remote.length} total=$totalCount',
      );
      unawaited(refreshOnlineFriends());
    } catch (exception) {
      if (_ownerId == ownerId) {
        error = exception;
        debugPrint(
          '[contacts][remote-failed] ownerId=$ownerId keepLocal=${local.isNotEmpty} error=$exception',
        );
      }
    } finally {
      if (_ownerId == ownerId) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> refresh() async {
    final ownerId = _ownerId;
    if (ownerId == null || isRefreshing) return;
    isRefreshing = true;
    error = null;
    notifyListeners();
    try {
      final remote = await _contactsRepository.loadIndexedFriends(
        ownerId: ownerId,
      );
      _groups = remote;
      await _contactsRepository.saveIndexedFriends(
        ownerId: ownerId,
        groups: remote,
      );
      await _sessionRepository.mergeContactIdentitySnapshots(
        ownerId: ownerId,
        snapshots: remote.expand(
          (group) => group.contacts.map((contact) => contact.raw),
        ),
      );
      debugPrint(
        '[contacts][refresh] ownerId=$ownerId groups=${_groups.length} total=$totalCount',
      );
      unawaited(refreshOnlineFriends());
    } catch (exception) {
      error = exception;
      rethrow;
    } finally {
      isRefreshing = false;
      notifyListeners();
    }
  }

  Future<void> refreshOnlineFriends() async {
    final ownerId = _ownerId;
    if (ownerId == null) return;
    try {
      final items = await _contactsRepository.loadOnlineFriends(
        ownerId: ownerId,
      );
      if (_ownerId != ownerId) return;
      _onlineDeviceTypes = <String, List<String>>{
        for (final item in items)
          if (item.sessionUnitId.isNotEmpty)
            item.sessionUnitId: item.deviceTypes,
      };
      notifyListeners();
    } catch (exception) {
      debugPrint(
        '[contacts][online-friends-failed] ownerId=$ownerId error=$exception',
      );
    }
  }

  void _scheduleOnlineFriendsRefresh() {
    _onlineRefreshTimer?.cancel();
    _onlineRefreshTimer = Timer(
      const Duration(milliseconds: 200),
      () => unawaited(refreshOnlineFriends()),
    );
  }

  void _clearOnlineFriends() {
    if (_onlineDeviceTypes.isEmpty) return;
    _onlineDeviceTypes = const <String, List<String>>{};
    notifyListeners();
  }

  @override
  void dispose() {
    _onlineRefreshTimer?.cancel();
    _signalSubscription.cancel();
    super.dispose();
  }

  Future<List<ContactGroup>> _loadLocal(int ownerId) async {
    final indexed = await _contactsRepository.loadLocalIndexedFriends(
      ownerId: ownerId,
    );
    if (indexed.isNotEmpty) return indexed;
    final friends = await _sessionRepository.loadLocalFriends(
      ownerId: ownerId,
      limit: 2000,
    );
    return localContactGroups(friends.map(_friendTuple));
  }

  ({String id, int? ownerId, String title, Map<String, dynamic> raw})
  _friendTuple(SessionSummary friend) => (
    id: friend.id,
    ownerId: friend.ownerId,
    title: friend.title,
    raw: friend.raw,
  );
}
