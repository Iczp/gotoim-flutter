import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../app/application_providers.dart';
import '../../session/application/session_list_controller.dart';
import '../../session/data/models/session_summary.dart';
import '../../session/data/repositories/session_repository.dart';
import '../data/datasources/contacts_api.dart';
import '../data/models/contact_group.dart';
import '../data/repositories/contacts_repository.dart';

final contactsRepositoryProvider = Provider<ContactsRepository>(
  (ref) => ContactsRepository(ContactsApi(ref.watch(apiClientProvider))),
);

final contactsControllerProvider = ChangeNotifierProvider<ContactsController>(
  (ref) => ContactsController(
    contactsRepository: ref.watch(contactsRepositoryProvider),
    sessionRepository: ref.watch(sessionRepositoryProvider),
  ),
);

class ContactsController extends ChangeNotifier {
  ContactsController({
    required ContactsRepository contactsRepository,
    required SessionRepository sessionRepository,
  }) : _contactsRepository = contactsRepository,
       _sessionRepository = sessionRepository;

  final ContactsRepository _contactsRepository;
  final SessionRepository _sessionRepository;
  List<ContactGroup> _groups = const <ContactGroup>[];
  int? _ownerId;
  bool isLoading = false;
  bool isRefreshing = false;
  Object? error;

  List<ContactGroup> get groups => List.unmodifiable(_groups);
  int get totalCount => _groups.fold(0, (total, group) => total + group.count);
  int? get ownerId => _ownerId;

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
      debugPrint(
        '[contacts][remote] ownerId=$ownerId groups=${remote.length} total=$totalCount',
      );
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
      _groups = await _contactsRepository.loadIndexedFriends(ownerId: ownerId);
      debugPrint(
        '[contacts][refresh] ownerId=$ownerId groups=${_groups.length} total=$totalCount',
      );
    } catch (exception) {
      error = exception;
      rethrow;
    } finally {
      isRefreshing = false;
      notifyListeners();
    }
  }

  Future<List<ContactGroup>> _loadLocal(int ownerId) async {
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
