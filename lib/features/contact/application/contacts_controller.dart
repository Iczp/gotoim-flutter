import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../app/application_providers.dart';
import '../../session/application/session_list_controller.dart';
import '../../session/data/models/session_summary.dart';
import '../../session/data/repositories/session_repository.dart';
import '../data/datasources/contacts_api.dart';
import '../data/models/contact_entry_item.dart';
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
  bool _disposed = false;

  List<ContactGroup> get groups => List.unmodifiable(_groups);
  int get totalCount => _groups.fold(0, (total, group) => total + group.count);
  int? get ownerId => _ownerId;
  Future<void> initialize(int? ownerId) async {
    if (_disposed ||
        ownerId == null ||
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
      debugPrint(
        '[contacts][local] ownerId=$ownerId groups=${local.length} total=$totalCount',
      );
      notifyListeners();

      // 增量检查：如果本地存在版本号且数据非空，先向服务端请求增量变更
      try {
        final lastSyncTicks = await _contactsRepository.readLastSyncTicks(ownerId);
        if (lastSyncTicks > 0) {
          final changes = await _contactsRepository.loadContactChanges(
            ownerId: ownerId,
            minTicks: lastSyncTicks,
          );
          final items = changes['items'];
          if (items is List && items.isEmpty) {
            // 无任何联系人变更，直接保持本地最新状态，免除网络全量传输与重新渲染
            debugPrint(
              '[contacts][incremental] up to date, ownerId=$ownerId minTicks=$lastSyncTicks',
            );
            return;
          }
        }
      } catch (exception) {
        debugPrint(
          '[contacts][incremental-fallback] ownerId=$ownerId error=$exception',
        );
      }
    }
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
      if (_groups.isNotEmpty) {
        try {
          final lastSyncTicks = await _contactsRepository.readLastSyncTicks(ownerId);
          if (lastSyncTicks > 0) {
            final changes = await _contactsRepository.loadContactChanges(
              ownerId: ownerId,
              minTicks: lastSyncTicks,
            );
            final items = changes['items'];
            if (items is List && items.isEmpty) {
              debugPrint(
                '[contacts][refresh-incremental] up to date, ownerId=$ownerId minTicks=$lastSyncTicks',
              );
              return;
            }
          }
        } catch (e) {
          debugPrint('[contacts][refresh-incremental-fallback] error=$e');
        }
      }
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

  /// 加载指定联系人/会话单元详情（包含系统条目与私有扩展条目）
  Future<ContactDetail?> loadContactDetail(String sessionUnitId) async {
    try {
      final res = await _contactsRepository.loadContactDetail(sessionUnitId);
      return ContactDetail.fromJson(res);
    } catch (e) {
      debugPrint('[contacts] loadContactDetail error: $e');
      return null;
    }
  }

  /// 加载系统字段定义
  Future<List<EntryNameDefinition>> loadEntryNames() async {
    try {
      final res = await _contactsRepository.loadEntryNames();
      final items = res['items'];
      if (items is List) {
        return items
            .whereType<Map>()
            .map((e) => EntryNameDefinition.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false);
      }
      return const <EntryNameDefinition>[];
    } catch (e) {
      debugPrint('[contacts] loadEntryNames error: $e');
      return const <EntryNameDefinition>[];
    }
  }

  /// 保存会话单元自定义条目
  Future<bool> saveContactEntries(
    String sessionUnitId,
    Map<String, List<String>> entries,
  ) async {
    try {
      await _contactsRepository.saveSessionUnitEntries(sessionUnitId, entries);
      // 成功后触发增量刷新
      if (_ownerId != null) {
        unawaited(refresh());
      }
      return true;
    } catch (e) {
      debugPrint('[contacts] saveContactEntries error: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    _disposed = true;
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
