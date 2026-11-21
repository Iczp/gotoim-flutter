part of 'message_repository.dart';

const String _globalV2CursorUnit = '__message_change_v2__';

extension MessageRepositorySync on MessageRepository {
  /// One job per account/ChatObject; UI and reconnect triggers share the same work.
  Future<void> loadChanges({required int ownerId, String? sessionUnitId}) {
    final key = '$ownerId:*';
    final existing = _changeSyncInFlight[key];
    if (existing != null) return existing;
    if (_changeSyncRetryAt?.isAfter(DateTime.now()) == true) {
      return Future.value();
    }
    final task = _loadChanges(ownerId).catchError((Object error) async {
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

  Future<void> _calibrateOwner(
    int owner, {
    required String epoch,
    required String headChangeId,
  }) async {
    if (headChangeId != '0') {
      var afterScope = '';
      while (true) {
      final units = await _dao.syncScopes(owner, afterScope, 50);
      if (units.isEmpty) break;
      for (final unit in units) {
        if (unit == _globalV2CursorUnit) continue;
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
            final status =
                state['status']?.toString() ?? state['state']?.toString();
            final msgId = state['messageId'] ?? state['id'];
            final changeId =
                state['messageChangeId']?.toString() ??
                state['changeSeq']?.toString() ??
                '0';
            final isDeleted = status == 'DeletedForMe' || status == 'NotFound';
            final isRollbacked = status == 'Recalled';
            final rollbackTime = state['rollbackTime'];

            mappedItems.add({
              'messageId': msgId,
              'syncVersion': changeId,
              'isDeleted': isDeleted,
              'isRollbacked': isRollbacked,
              if (rollbackTime != null) 'rollbackTime': rollbackTime,
            });

            if (!isDeleted && !isRollbacked && state['message'] is Map) {
              final raw = Map<String, dynamic>.from(state['message'] as Map);
              final remoteMessage = ChatMessage.fromJson(
                raw,
                ownerId: owner,
                sessionUnitId: unit,
              );
              final sId = remoteMessage.serverId;
              if (sId != null && sId > 0) {
                final existing = await _dao.findByServerId(
                  ownerId: owner,
                  sessionUnitId: unit,
                  serverId: sId,
                );
                final merged = existing != null
                    ? existing.copyWith(
                        serverId: remoteMessage.serverId,
                        score: remoteMessage.score,
                        raw: <String, dynamic>{
                          ...existing.raw,
                          ...remoteMessage.raw,
                          'content': <String, dynamic>{
                            ...existing.content,
                            ...remoteMessage.content,
                          },
                        },
                      )
                    : remoteMessage;
                await _dao.upsertAll(<ChatMessage>[merged]);
                await _updateSessionSummary(merged);
              }
            }
          }

          await _dao.applySyncPage(owner, unit, mappedItems);
          _sessionChangeBus?.publish(
            ownerId: owner,
            sessionUnitId: unit,
            messageIds:
                mappedItems
                    .where(
                      (row) =>
                          row['isRollbacked'] == true ||
                          row['isDeleted'] == true,
                    )
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
      }
      afterScope = units.last;
      if (units.length < 50) break;
      }
    }

    final newCursor = _formatV2Cursor(epoch, headChangeId);
    await _dao.applySyncPage(
      owner,
      _globalV2CursorUnit,
      const [],
      cursor: newCursor,
    );
    await _api
        .ackChanges(
          chatObjectId: owner,
          epoch: epoch,
          lastAppliedMessageChangeId: headChangeId,
          reset: true,
        )
        .catchError((_) => <String, dynamic>{});
  }

  Future<void> _loadChanges(int owner) async {
    final cursorRaw = await _dao.syncCursor(owner, _globalV2CursorUnit);
    final cursor = _parseV2Cursor(cursorRaw);

    final currentEpoch = cursor?['epoch'] ?? '';
    var currentSeq = cursor?['seq'] ?? '0';
    var resets = 0;

    while (true) {
      final page = await _api.pullChanges(
        chatObjectId: owner,
        epoch: cursor == null ? '' : currentEpoch,
        afterMessageChangeId: cursor == null ? '0' : currentSeq,
        maxResultCount: 100,
      );

      final pageEpoch = page['epoch']?.toString() ?? currentEpoch;
      final pageHead = page['headChangeId']?.toString() ?? '0';

      if (cursor == null || page['resetRequired'] == true) {
        if (++resets > 2) throw StateError('消息同步基线反复变化，请重试');
        await _calibrateOwner(
          owner,
          epoch: pageEpoch,
          headChangeId: pageHead,
        );
        return;
      }

      final nextCursor =
          page['nextCursor']?.toString() ?? page['headChangeId']?.toString();
      if (nextCursor == null || nextCursor.isEmpty) {
        throw StateError('消息同步响应缺少游标');
      }

      final rawItems = page['items'] as List<dynamic>? ?? const [];
      if (nextCursor == currentSeq &&
          rawItems.isEmpty &&
          page['hasMore'] != true) {
        return;
      }
      final itemsByUnit = <String, List<Map<String, dynamic>>>{};
      final updatedIdsByUnit = <String, List<int>>{};

      for (final raw in rawItems) {
        final row = Map<String, dynamic>.from(raw as Map);
        final unit = row['sessionUnitId']?.toString();
        final changeType = row['changeType']?.toString();
        final messageId = row['messageId'];
        final changeId = row['messageChangeId']?.toString() ?? '0';
        if (unit == null || unit.isEmpty || messageId == null) continue;

        if (changeType == 'Recalled') {
          itemsByUnit.putIfAbsent(unit, () => []).add({
            'messageId': messageId,
            'isRollbacked': true,
            'syncVersion': changeId,
          });
        } else if (changeType == 'Updated') {
          final parsedId = int.tryParse('$messageId');
          if (parsedId != null) {
            updatedIdsByUnit.putIfAbsent(unit, () => []).add(parsedId);
          }
          itemsByUnit.putIfAbsent(unit, () => []).add({
            'messageId': messageId,
            'syncVersion': changeId,
          });
        }
      }

      for (final entry in updatedIdsByUnit.entries) {
        final states = await _api.messageStates(
          chatObjectId: owner,
          sessionUnitId: entry.key,
          messageIds: entry.value.toSet().toList(),
        );
        final stateItems = itemsByUnit[entry.key]!;
        for (final state in states) {
          final status = state['status']?.toString();
          final msgId = state['messageId'];
          final changeId =
              state['messageChangeId']?.toString() ??
              state['changeSeq']?.toString() ??
              '0';
          if (status == 'Recalled') {
            stateItems.add({
              'messageId': msgId,
              'isRollbacked': true,
              'rollbackTime': state['rollbackTime'],
              'syncVersion': changeId,
            });
          } else if (status == 'DeletedForMe' || status == 'NotFound') {
            stateItems.add({
              'messageId': msgId,
              'isDeleted': true,
              'syncVersion': changeId,
            });
          } else {
            if (state['message'] is Map) {
              final raw = Map<String, dynamic>.from(state['message'] as Map);
              final remoteMessage = ChatMessage.fromJson(
                raw,
                ownerId: owner,
                sessionUnitId: entry.key,
              );
              final sId = remoteMessage.serverId;
              if (sId != null && sId > 0) {
                final existing = await _dao.findByServerId(
                  ownerId: owner,
                  sessionUnitId: entry.key,
                  serverId: sId,
                );
                final merged = existing != null
                    ? existing.copyWith(
                        serverId: remoteMessage.serverId,
                        score: remoteMessage.score,
                        raw: <String, dynamic>{
                          ...existing.raw,
                          ...remoteMessage.raw,
                          'content': <String, dynamic>{
                            ...existing.content,
                            ...remoteMessage.content,
                          },
                        },
                      )
                    : remoteMessage;
                await _dao.upsertAll(<ChatMessage>[merged]);
                await _updateSessionSummary(merged);
              }
            } else {
              final parsedId = int.tryParse('$msgId');
              if (parsedId != null && parsedId > 0) {
                final applied = await fetchAndApplyUpdatedMessage(
                  ownerId: owner,
                  sessionUnitId: entry.key,
                  messageId: parsedId,
                );
                if (applied == null) {
                  // F5: 变更正文加载失败，不能确认游标或发送 ACK，中止当前同步批次以待下次重试
                  debugPrint(
                    '[MessageSync] 变更正文加载失败 messageId=$parsedId，中断本轮游标推进以待重试',
                  );
                  return;
                }
              }
            }
          }
        }
      }

      for (final entry in itemsByUnit.entries) {
        await _dao.applySyncPage(owner, entry.key, entry.value);
        if (entry.value.isNotEmpty) {
          _sessionChangeBus?.publish(
            ownerId: owner,
            sessionUnitId: entry.key,
            messageIds:
                entry.value
                    .where((row) => row['messageId'] != null)
                    .map((row) => int.parse('${row['messageId']}'))
                    .toList(),
            deletedMessageIds:
                entry.value
                    .where(
                      (row) =>
                          row['isDeleted'] == true && row['messageId'] != null,
                    )
                    .map((row) => int.parse('${row['messageId']}'))
                    .toList(),
          );
        }
      }

      final newCursor = _formatV2Cursor(pageEpoch, nextCursor);
      await _dao.applySyncPage(
        owner,
        _globalV2CursorUnit,
        const [],
        cursor: newCursor,
      );

      await _api
          .ackChanges(
            chatObjectId: owner,
            epoch: pageEpoch,
            lastAppliedMessageChangeId: nextCursor,
          )
          .catchError((_) => <String, dynamic>{});

      if (page['hasMore'] != true) return;
      if (nextCursor == currentSeq) throw StateError('消息同步游标未推进');
      currentSeq = nextCursor;
    }
  }
}
