part of 'message_repository.dart';

extension MessageRepositorySync on MessageRepository {
  /// One job per account/scope; UI and reconnect triggers share the same work.
  Future<void> loadChanges({required int ownerId, String? sessionUnitId}) {
    if (sessionUnitId != null && _changeSyncInFlight['$ownerId:*'] != null) {
      // The owner scan may already have passed this unit when the event arrives.
      // Recheck it after the scan instead of treating that scan as the event.
      return _changeSyncInFlight['$ownerId:*']!.then(
        (_) => loadChanges(ownerId: ownerId, sessionUnitId: sessionUnitId),
      );
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

  Map<String, String>? _parseV2Cursor(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['epoch'] != null && decoded['seq'] != null) {
        return {
          'epoch': '${decoded['epoch']}',
          'seq': '${decoded['seq']}',
        };
      }
    } catch (_) {}
    return null;
  }

  String _formatV2Cursor(String epoch, String seq) {
    return jsonEncode({'epoch': epoch, 'seq': seq});
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

        final heads = await _api.changeHeads(
          chatObjectId: owner,
          sessionUnitIds: units,
        );

        final headMap = <String, Map<String, dynamic>>{};
        for (final item in heads) {
          final id = item['sessionUnitId']?.toString();
          if (id != null) headMap[id] = item;
        }

        for (final unit in units) {
          final head = headMap[unit];
          if (head == null || head['errorCode'] != null) continue;
          await _syncChangeScope(owner, unit, initialHead: head);
        }
      }
      if (onlyUnit != null || units.length < 20) return;
      after = units.last;
    } while (true);
  }

  Future<void> _calibrateScope(
    int owner,
    String unit, {
    required String epoch,
    required String headSeq,
  }) async {
    var afterId = 0;
    while (true) {
      final ids = await _dao.syncIds(owner, unit, afterId, 200);
      if (ids.isEmpty) break;
      final states = await _api.messageStates(
        chatObjectId: owner,
        sessionUnitId: unit,
        messageIds: ids,
      );

      final mappedItems = <Map<String, dynamic>>[];
      for (final state in states) {
        final stateType = state['state']?.toString();
        final msgId = state['messageId'] ?? state['id'];
        final changeSeq = state['changeSeq']?.toString() ?? '0';
        final isDeleted = stateType == 'DeletedForMe' || stateType == 'NotFound';
        final isRollbacked = stateType == 'Recalled';
        final rollbackTime = state['rollbackTime'];

        mappedItems.add({
          'messageId': msgId,
          'syncVersion': changeSeq,
          'isDeleted': isDeleted,
          'isRollbacked': isRollbacked,
          if (rollbackTime != null) 'rollbackTime': rollbackTime,
        });
      }

      await _dao.applySyncPage(owner, unit, mappedItems);
      _sessionChangeBus?.publish(
        ownerId: owner,
        sessionUnitId: unit,
        messageIds:
            mappedItems
                .where((row) => row['isRollbacked'] == true || row['isDeleted'] == true)
                .map((row) => int.parse('${row['messageId']}'))
                .toList(),
        deletedMessageIds:
            mappedItems
                .where((row) => row['isDeleted'] == true)
                .map((row) => int.parse('${row['messageId']}'))
                .toList(),
      );
      afterId = ids.last;
      if (ids.length < 200) break;
    }

    final newCursor = _formatV2Cursor(epoch, headSeq);
    await _dao.applySyncPage(owner, unit, const [], cursor: newCursor);
  }

  Future<void> _syncChangeScope(
    int owner,
    String unit, {
    Map<String, dynamic>? initialHead,
  }) async {
    var head = initialHead;
    if (head == null) {
      final heads = await _api.changeHeads(
        chatObjectId: owner,
        sessionUnitIds: [unit],
      );
      if (heads.isEmpty || heads.first['errorCode'] != null) return;
      head = heads.first;
    }

    final epoch = head['epoch']?.toString();
    final headSeqStr = head['headSeq']?.toString();
    if (epoch == null || epoch.isEmpty || headSeqStr == null) return;

    final cursorRaw = await _dao.syncCursor(owner, unit);
    final cursor = _parseV2Cursor(cursorRaw);

    // If no cursor or epoch changed, calibrate and baseline to headSeq
    if (cursor == null || cursor['epoch'] != epoch) {
      await _calibrateScope(owner, unit, epoch: epoch, headSeq: headSeqStr);
      return;
    }

    var currentSeq = cursor['seq']!;
    final headSeq = BigInt.tryParse(headSeqStr) ?? BigInt.zero;
    final curSeqNum = BigInt.tryParse(currentSeq) ?? BigInt.zero;

    if (curSeqNum >= headSeq) {
      // Local is already up-to-date with head
      return;
    }

    var resets = 0;
    while (true) {
      final page = await _api.incrementalChanges(
        chatObjectId: owner,
        sessionUnitId: unit,
        epoch: epoch,
        changeSeq: currentSeq,
        maxResultCount: 100,
      );

      if (page['resetRequired'] == true) {
        if (++resets > 2) throw StateError('消息同步基线反复变化，请重试');
        final targetHead = page['headSeq']?.toString() ?? headSeqStr;
        final targetEpoch = page['epoch']?.toString() ?? epoch;
        await _calibrateScope(owner, unit, epoch: targetEpoch, headSeq: targetHead);
        return;
      }

      final nextSeq = page['nextSeq']?.toString() ?? page['headSeq']?.toString();
      if (nextSeq == null || nextSeq.isEmpty) {
        throw StateError('消息同步响应缺少游标');
      }

      final rawItems = page['items'] as List<dynamic>? ?? const [];
      final items = <Map<String, dynamic>>[];

      for (final raw in rawItems) {
        final row = Map<String, dynamic>.from(raw as Map);
        final changeType = row['changeType']?.toString();
        final messageId = row['messageId'];
        final changeSeq = row['changeSeq']?.toString() ?? '0';

        if (changeType == 'Clear') {
          items.add({
            'clearTime': row['clearTime'],
            'syncVersion': changeSeq,
          });
        } else if (changeType == 'DeletedForMe') {
          items.add({
            'messageId': messageId,
            'isDeleted': true,
            'syncVersion': changeSeq,
          });
        } else if (changeType == 'Recalled') {
          items.add({
            'messageId': messageId,
            'isRollbacked': true,
            'rollbackTime': row['rollbackTime'],
            'syncVersion': changeSeq,
          });
        } else if (changeType == 'Updated') {
          items.add({
            'messageId': messageId,
            'syncVersion': changeSeq,
          });
        }
      }

      final newCursor = _formatV2Cursor(epoch, nextSeq);
      await _dao.applySyncPage(owner, unit, items, cursor: newCursor);

      if (items.isNotEmpty) {
        _sessionChangeBus?.publish(
          ownerId: owner,
          sessionUnitId: unit,
          messageIds:
              items
                  .where((row) => row['messageId'] != null)
                  .map((row) => int.parse('${row['messageId']}'))
                  .toList(),
          deletedMessageIds:
              items
                  .where((row) => row['isDeleted'] == true && row['messageId'] != null)
                  .map((row) => int.parse('${row['messageId']}'))
                  .toList(),
        );
      }

      if (page['hasMore'] != true) return;
      if (nextSeq == currentSeq) throw StateError('消息同步游标未推进');
      currentSeq = nextSeq;
    }
  }
}
