import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../app/application_providers.dart';
import '../../session/application/friend_presence_store.dart';
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
    // The controller listens to presence changes itself. Do not watch this
    // ChangeNotifier here, or it is recreated on every status event.
    friendPresenceStore: ref.read(friendPresenceStoreProvider),
  ),
);

class ContactsController extends ChangeNotifier {
  ContactsController({
    required ContactsRepository contactsRepository,
    required SessionRepository sessionRepository,
    required FriendPresenceStore friendPresenceStore,
  }) : _contactsRepository = contactsRepository,
       _sessionRepository = sessionRepository,
       _friendPresenceStore = friendPresenceStore {
    _friendPresenceStore.addListener(_onPresenceChanged);
  }

  final ContactsRepository _contactsRepository;
  final SessionRepository _sessionRepository;
  final FriendPresenceStore _friendPresenceStore;
  List<ContactGroup> _groups = const <ContactGroup>[];
  int? _ownerId;
  bool isLoading = false;
  bool isRefreshing = false;
  Object? error;
  bool _disposed = false;

  List<ContactGroup> get groups => List.unmodifiable(_groups);
  int get totalCount => _groups.fold(0, (total, group) => total + group.count);
  int? get ownerId => _ownerId;
  List<String> onlineDeviceTypes(String sessionUnitId) =>
      _friendPresenceStore.deviceTypesForSession(sessionUnitId);

  void _onPresenceChanged() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize(int? ownerId) async {
    if (_disposed ||
        ownerId == null ||
        (_ownerId == ownerId && (_groups.isNotEmpty || isLoading))) {
      return;
    }
    _ownerId = ownerId;
    _groups = const <ContactGroup>[];
    unawaited(_friendPresenceStore.activateOwner(ownerId));
    error = null;
    isLoading = true;
    notifyListeners();

    var local = const <ContactGroup>[];
    try {
      local = await _loadLocal(ownerId);
    } catch (exception) {
      if (!_disposed && _ownerId == ownerId) {
        error = exception;
        debugPrint(
          '[contacts][local-failed] ownerId=$ownerId error=$exception',
        );
      }
    }
    if (_disposed || _ownerId != ownerId) return;
    if (local.isNotEmpty) {
      _groups = local;
      _friendPresenceStore.bindContacts(local);
      debugPrint(
        '[contacts][local] ownerId=$ownerId groups=${local.length} total=$totalCount',
      );
      notifyListeners();
    }
    try {
      final remote = await _contactsRepository.loadIndexedFriends(
        ownerId: ownerId,
      );
      if (_disposed || _ownerId != ownerId) return;
      _groups = remote;
      _friendPresenceStore.bindContacts(remote);
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
    } catch (exception) {
      if (!_disposed && _ownerId == ownerId) {
        error = exception;
        debugPrint(
          '[contacts][remote-failed] ownerId=$ownerId keepLocal=${local.isNotEmpty} error=$exception',
        );
      }
    } finally {
      if (!_disposed && _ownerId == ownerId) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> refresh() async {
    final ownerId = _ownerId;
    if (_disposed || ownerId == null || isRefreshing) return;
    isRefreshing = true;
    error = null;
    notifyListeners();
    try {
      final remote = await _contactsRepository.loadIndexedFriends(
        ownerId: ownerId,
      );
      if (_disposed || _ownerId != ownerId) return;
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
    } catch (exception) {
      if (_disposed) return;
      error = exception;
      rethrow;
    } finally {
      if (!_disposed) {
        isRefreshing = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _friendPresenceStore.removeListener(_onPresenceChanged);
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
