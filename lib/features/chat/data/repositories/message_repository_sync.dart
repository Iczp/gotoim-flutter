part of 'message_repository.dart';

extension MessageRepositorySync on MessageRepository {
  /// One job per account/scope; UI and reconnect triggers share the same work.
  Future<void> loadChanges({required int ownerId, String? sessionUnitId}) {
    if (sessionUnitId != null && _changeSyncInFlight['$ownerId:*'] != null) {
      return _changeSyncInFlight['$ownerId:*']!;
    }
    final key = '$ownerId:${sessionUnitId ?? '*'}';
    final existing = _changeSyncInFlight[key];
    if (existing != null) return existing;
    if (_changeSyncRetryAt?.isAfter(DateTime.now()) == true) {
      return Future.value();
    }
    final task = _loadChanges(ownerId, sessionUnitId).catchError((
      Object error,
    ) async {
      if (error is ApiException &&
          (error.statusCode == 404 ||
              error.code == 'Chat:MessageChangeSyncDisabled')) {
        _changeSyncRetryAt = DateTime.now().add(const Duration(minutes: 5));
        await _dao.resetSyncCursors(ownerId);
        return;
      }
      throw error;
    });
    _changeSyncInFlight[key] = task;
    return task.whenComplete(() {
      if (identical(_changeSyncInFlight[key], task)) {
        _changeSyncInFlight.remove(key);
      }
    });
  }

  Future<void> _loadChanges(int owner, String? onlyUnit) async {
    var after = '';
    do {
      final units =
          onlyUnit != null
              ? [onlyUnit]
              : await _dao.syncScopes(owner, after, 20);
      if (units.isEmpty) return;
      if (onlyUnit != null) {
        await _syncChangeScope(owner, onlyUnit);
      } else {
        for (final unit in units) {
          final active = _changeSyncInFlight['$owner:$unit'];
          if (active != null) await active;
        }
        final scopes = <Map<String, Object?>>[];
        for (final unit in units) {
          scopes.add({
            'sessionUnitId': unit,
            'cursor': await _dao.syncCursor(owner, unit),
          });
        }
        final pages = await _api.changes(scopes);
        if (pages.length != units.length ||
            pages.map((row) => row['sessionUnitId']).toSet().length !=
                units.length) {
          throw StateError('批量消息同步响应不完整');
        }
        for (final page in pages) {
          final unit = page['sessionUnitId']?.toString();
          if (!units.contains(unit)) throw StateError('消息同步返回未请求的会话');
          if (page['errorCode'] != null) continue;
          await _syncChangeScope(owner, unit!, firstPage: page);
        }
      }
      if (onlyUnit != null || units.length < 20) return;
      after = units.last;
    } while (true);
  }

  Future<void> _syncChangeScope(
    int owner,
    String unit, {
    Map<String, dynamic>? firstPage,
  }) async {
    var cursor = await _dao.syncCursor(owner, unit);
    String? snapshot;
    var resets = 0;
    while (true) {
      final pages =
          firstPage != null
              ? [firstPage]
              : await _api.changes([
                {
                  'sessionUnitId': unit,
                  'cursor': cursor,
                  'snapshotCursor': snapshot,
                },
              ]);
      firstPage = null;
      if (pages.length != 1 || pages.single['sessionUnitId'] != unit) {
        throw StateError('消息同步响应的会话不匹配');
      }
      final page = pages.single;
      if (page['errorCode'] != null) throw StateError('当前会话不可同步');
      final next = page['nextCursor']?.toString();
      if (next == null || next.isEmpty) throw StateError('消息同步响应缺少游标');
      if (page['resetRequired'] == true) {
        if (++resets > 2) throw StateError('消息同步基线反复变化，请重试');
        // The checkpoint is acquired BEFORE calibration. Anything committed
        // while the local ids are checked is replayed from this checkpoint.
        var afterId = 0;
        while (true) {
          final ids = await _dao.syncIds(owner, unit, afterId, 200);
          if (ids.isEmpty) break;
          final states = await _api.syncItems(unit, ids);
          if (states.any(
            (row) => !ids.contains(int.tryParse('${row['messageId']}')),
          )) {
            throw StateError('消息校准响应包含未请求的消息');
          }
          await _dao.applySyncPage(owner, unit, states);
          _sessionChangeBus?.publish(
            ownerId: owner,
            sessionUnitId: unit,
            messageIds:
                states
                    .where(
                      (row) =>
                          row['isRollbacked'] == true ||
                          row['rollbackTime'] != null,
                    )
                    .map((row) => int.parse('${row['messageId']}'))
                    .toList(),
          );
          afterId = ids.last;
          if (ids.length < 200) break;
        }
        await _dao.applySyncPage(owner, unit, const [], cursor: next);
        cursor = next;
        snapshot = null;
        continue;
      }
      final items =
          (page['items'] as List? ?? const [])
              .map((row) => Map<String, dynamic>.from(row as Map))
              .toList();
      // This release applies rollback only. Never acknowledge unknown future
      // mutation types until the client can apply their semantics.
      if (items.any(
        (row) => row['changeType'] != 1 && row['changeType'] != 'Rollback',
      )) {
        throw UnsupportedError('当前客户端尚不支持该消息变更类型');
      }
      if (items.any(
        (row) =>
            (int.tryParse('${row['messageId']}') ?? 0) <= 0 ||
            (int.tryParse('${row['syncVersion']}') ?? -1) < 0 ||
            !(row['isRollbacked'] == true || row['rollbackTime'] != null),
      )) {
        throw const FormatException('消息撤回变更缺少有效的标识、版本或状态');
      }
      if (page['hasMore'] == true &&
          (page['snapshotCursor']?.toString().isNotEmpty != true ||
              next == cursor)) {
        throw StateError('消息同步分页边界无效');
      }
      await _dao.applySyncPage(owner, unit, items, cursor: next);
      if (items.isNotEmpty) {
        _sessionChangeBus?.publish(
          ownerId: owner,
          sessionUnitId: unit,
          messageIds:
              items.map((row) => int.parse('${row['messageId']}')).toList(),
        );
      }
      if (page['hasMore'] != true) return;
      if (next == cursor) throw StateError('消息同步游标未推进');
      snapshot = page['snapshotCursor']?.toString();
      cursor = next;
    }
  }
}
