part of 'message_repository.dart';

const String _globalV2CursorUnit = '__message_change_v2__';
const String _calibrationCheckpointUnit = '__message_change_v2_calibrating__';
const int _byIdsMaxPerScope = 200;
const int _byIdsMaxPerBatch = 500;

typedef _CalibrationSlice = ({String sessionUnitId, List<int> messageIds});

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
      if (decoded is Map &&
          decoded['epoch'] != null &&
          decoded['seq'] != null) {
        return {'epoch': '${decoded['epoch']}', 'seq': '${decoded['seq']}'};
      }
    } catch (_) {}
    return null;
  }

  String _formatV2Cursor(String epoch, String seq) {
    return jsonEncode({'epoch': epoch, 'seq': seq});
  }

  ({String epoch, String headChangeId, String afterScope, int afterId})?
  _parseCalibrationCheckpoint(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map &&
          decoded['epoch'] != null &&
          decoded['headChangeId'] != null &&
          decoded['afterScope'] != null) {
        final afterId = int.tryParse('${decoded['afterId'] ?? 0}') ?? 0;
        return (
          epoch: '${decoded['epoch']}',
          headChangeId: '${decoded['headChangeId']}',
          afterScope: '${decoded['afterScope']}',
          afterId: afterId,
        );
      }
    } catch (_) {}
    return null;
  }

  String _formatCalibrationCheckpoint({
    required String epoch,
    required String headChangeId,
    required String afterScope,
    required int afterId,
  }) {
    return jsonEncode({
      'epoch': epoch,
      'headChangeId': headChangeId,
      'afterScope': afterScope,
      'afterId': afterId,
    });
  }

  Future<List<_CalibrationSlice>> _collectUnitSlices(
    int owner,
    String unit, {
    required int startAfterId,
  }) async {
    final slices = <_CalibrationSlice>[];
    var afterId = startAfterId;
    while (true) {
      final ids = await _dao.syncIds(owner, unit, afterId, _byIdsMaxPerScope);
      if (ids.isEmpty) break;
      slices.add((sessionUnitId: unit, messageIds: ids));
      afterId = ids.last;
      if (ids.length < _byIdsMaxPerScope) break;
    }
    return slices;
  }

  List<List<_CalibrationSlice>> _packCalibrationBatches(
    List<_CalibrationSlice> slices,
  ) {
    final batches = <List<_CalibrationSlice>>[];
    var currentBatch = <_CalibrationSlice>[];
    var currentItemCount = 0;
    final currentUnits = <String>{};

    for (final slice in slices) {
      final sliceCount = slice.messageIds.length;
      if (sliceCount == 0) continue;
      final exceedsBatchLimit =
          currentItemCount + sliceCount > _byIdsMaxPerBatch;
      final duplicateUnitInBatch = currentUnits.contains(slice.sessionUnitId);
      if (currentBatch.isNotEmpty &&
          (exceedsBatchLimit || duplicateUnitInBatch)) {
        batches.add(currentBatch);
        currentBatch = <_CalibrationSlice>[];
        currentItemCount = 0;
        currentUnits.clear();
      }
      currentBatch.add(slice);
      currentItemCount += sliceCount;
      currentUnits.add(slice.sessionUnitId);
    }
    if (currentBatch.isNotEmpty) {
      batches.add(currentBatch);
    }
    return batches;
  }

  bool _shouldUpdateCalibratedMessage(
    ChatMessage existing,
    ChatMessage remote,
    String changeId,
  ) {
    if (existing.score != remote.score) return true;
    final oldSyncVersion = '${existing.raw['syncVersion'] ?? ''}';
    final newSyncVersion = '${remote.raw['syncVersion'] ?? ''}';
    if (newSyncVersion.isNotEmpty && oldSyncVersion != newSyncVersion) {
      return true;
    }
    if (changeId != '0' &&
        '${existing.raw['messageChangeId'] ?? ''}' != changeId) {
      return true;
    }
    if (jsonEncode(existing.content) != jsonEncode(remote.content)) {
      return true;
    }
    return false;
  }

  Future<void> _calibrateOwner(
    int owner, {
    required String epoch,
    required String headChangeId,
    required DateTime startedAt,
  }) async {
    if (headChangeId != '0') {
      final rawCheckpoint = await _dao.syncCursor(
        owner,
        _calibrationCheckpointUnit,
      );
      final checkpoint = _parseCalibrationCheckpoint(rawCheckpoint);
      final canResume =
          checkpoint != null &&
          checkpoint.epoch == epoch &&
          checkpoint.headChangeId == headChangeId &&
          checkpoint.afterScope.isNotEmpty;

      final allSlices = <_CalibrationSlice>[];
      var afterScope = '';
      if (canResume) {
        allSlices.addAll(
          await _collectUnitSlices(
            owner,
            checkpoint.afterScope,
            startAfterId: checkpoint.afterId,
          ),
        );
        afterScope = checkpoint.afterScope;
      }

      while (true) {
        final units = await _dao.syncScopes(owner, afterScope, 50);
        if (units.isEmpty) break;
        for (final unit in units) {
          if (unit == _globalV2CursorUnit ||
              unit == _calibrationCheckpointUnit) {
            continue;
          }
          allSlices.addAll(
            await _collectUnitSlices(owner, unit, startAfterId: 0),
          );
        }
        afterScope = units.last;
        if (units.length < 50) break;
      }

      final batches = _packCalibrationBatches(allSlices);
      final totalBatches = batches.length;
      final totalItems = allSlices.fold<int>(
        0,
        (sum, slice) => sum + slice.messageIds.length,
      );
      final lastBatchByUnit = <String, int>{};
      for (var batchIndex = 0; batchIndex < batches.length; batchIndex++) {
        for (final req in batches[batchIndex]) {
          lastBatchByUnit[req.sessionUnitId] = batchIndex;
        }
      }
      final totalSessions = lastBatchByUnit.length;

      if (batches.isNotEmpty) {
        _emitSyncProgress(
          MessageSyncProgress(
            ownerId: owner,
            stage: MessageSyncStage.calibrating,
            startedAt: startedAt,
            completedBatches: 0,
            totalBatches: totalBatches,
            processedItems: 0,
            totalItems: totalItems,
            processedSessions: 0,
            totalSessions: totalSessions,
          ),
        );
      }

      var processedItems = 0;
      for (var batchIndex = 0; batchIndex < batches.length; batchIndex++) {
        final batch = batches[batchIndex];
        _checkActive();
        final states = await _api.messageStatesBatch(
          chatObjectId: owner,
          requests: batch,
        );

        final statesByUnit = <String, List<Map<String, dynamic>>>{};
        for (final state in states) {
          final rawUnit = state['sessionUnitId']?.toString();
          final resolvedUnit =
              (rawUnit != null && rawUnit.isNotEmpty)
                  ? rawUnit
                  : (batch.length == 1 ? batch.single.sessionUnitId : '');
          if (resolvedUnit.isEmpty) continue;
          statesByUnit.putIfAbsent(resolvedUnit, () => []).add(state);
        }

        for (final req in batch) {
          final unit = req.sessionUnitId;
          final unitStates = statesByUnit[unit] ?? const <Map<String, dynamic>>[];
          final tombstoneItems = <Map<String, dynamic>>[];
          final visibleStates = <({Map<String, dynamic> state, String changeId})>[];

          for (final state in unitStates) {
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

            if (isDeleted || isRollbacked) {
              tombstoneItems.add({
                'messageId': msgId,
                'syncVersion': changeId,
                'isDeleted': isDeleted,
                'isRollbacked': isRollbacked,
                if (rollbackTime != null) 'rollbackTime': rollbackTime,
              });
            } else if (state['message'] is Map) {
              visibleStates.add((state: state, changeId: changeId));
            }
          }

          if (visibleStates.isNotEmpty) {
            final visibleIds = <int>[];
            for (final entry in visibleStates) {
              final id = int.tryParse(
                '${entry.state['messageId'] ?? entry.state['id']}',
              );
              if (id != null && id > 0) visibleIds.add(id);
            }
            if (visibleIds.isNotEmpty) {
              final existingRows = await _dao.readByIds(owner, unit, visibleIds);
              final existingByServerId = <int, ChatMessage>{
                for (final row in existingRows)
                  if (row.serverId != null) row.serverId!: row,
              };
              final toUpsert = <ChatMessage>[];
              for (final entry in visibleStates) {
                final raw = Map<String, dynamic>.from(
                  entry.state['message'] as Map,
                );
                final remoteMessage = ChatMessage.fromJson(
                  raw,
                  ownerId: owner,
                  sessionUnitId: unit,
                );
                final sId = remoteMessage.serverId;
                if (sId == null || sId <= 0) continue;
                final existing = existingByServerId[sId];
                if (existing == null) {
                  // 仅更新本地 Messages 表中已缓存的消息，避免把 Friends.lastMessage 注入 Messages 表。
                  continue;
                }
                if (!_shouldUpdateCalibratedMessage(
                  existing,
                  remoteMessage,
                  entry.changeId,
                )) {
                  continue;
                }
                toUpsert.add(
                  existing.copyWith(
                    serverId: remoteMessage.serverId,
                    score: remoteMessage.score,
                    raw: <String, dynamic>{
                      ...existing.raw,
                      ...remoteMessage.raw,
                      if (entry.changeId != '0')
                        'messageChangeId': entry.changeId,
                      'content': <String, dynamic>{
                        ...existing.content,
                        ...remoteMessage.content,
                      },
                    },
                  ),
                );
              }
              if (toUpsert.isNotEmpty) {
                _checkActive();
                await _dao.upsertAll(toUpsert);
                var newest = toUpsert.first;
                for (final item in toUpsert.skip(1)) {
                  if (item.score > newest.score) newest = item;
                }
                await _updateSessionSummary(newest);
              }
            }
          }

          if (tombstoneItems.isNotEmpty) {
            _checkActive();
            await _dao.applySyncPage(owner, unit, tombstoneItems);
            _sessionChangeBus?.publish(
              ownerId: owner,
              sessionUnitId: unit,
              messageIds:
                  tombstoneItems
                      .where((row) => row['messageId'] != null)
                      .map((row) => int.parse('${row['messageId']}'))
                      .toList(),
              deletedMessageIds:
                  tombstoneItems
                      .where(
                        (row) =>
                            row['isDeleted'] == true &&
                            row['messageId'] != null,
                      )
                      .map((row) => int.parse('${row['messageId']}'))
                      .toList(),
            );
          }

          processedItems += req.messageIds.length;
        }

        final lastReq = batch.last;
        _checkActive();
        await _dao.applySyncPage(
          owner,
          _calibrationCheckpointUnit,
          const [],
          cursor: _formatCalibrationCheckpoint(
            epoch: epoch,
            headChangeId: headChangeId,
            afterScope: lastReq.sessionUnitId,
            afterId: lastReq.messageIds.last,
          ),
        );

        final processedSessions =
            lastBatchByUnit.values.where((idx) => idx <= batchIndex).length;
        _emitSyncProgress(
          MessageSyncProgress(
            ownerId: owner,
            stage: MessageSyncStage.calibrating,
            startedAt: startedAt,
            completedBatches: batchIndex + 1,
            totalBatches: totalBatches,
            processedItems: processedItems,
            totalItems: totalItems,
            processedSessions: processedSessions,
            totalSessions: totalSessions,
          ),
        );
      }

      if (totalBatches > 0) {
        debugPrint(
          '[MessageSync] calibrate done owner=$owner '
          'sessions=$totalSessions items=$totalItems batches=$totalBatches '
          'elapsed=${DateTime.now().difference(startedAt).inMilliseconds}ms',
        );
      }
    }

    final newCursor = _formatV2Cursor(epoch, headChangeId);
    _checkActive();
    await _dao.applySyncPage(
      owner,
      _globalV2CursorUnit,
      const [],
      cursor: newCursor,
    );
    await _dao.applySyncPage(
      owner,
      _calibrationCheckpointUnit,
      const [],
      cursor: '',
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
    final startedAt = DateTime.now();
    _emitSyncProgress(
      MessageSyncProgress(
        ownerId: owner,
        stage: MessageSyncStage.pullingChanges,
        startedAt: startedAt,
      ),
    );
    try {
      final cursorRaw = await _dao.syncCursor(owner, _globalV2CursorUnit);
      final cursor = _parseV2Cursor(cursorRaw);

      final currentEpoch = cursor?['epoch'] ?? '';
      var currentSeq = cursor?['seq'] ?? '0';
      var resets = 0;
      var pagesFetched = 0;
      var totalItemsProcessed = 0;

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
            startedAt: startedAt,
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
        pagesFetched++;
        totalItemsProcessed += rawItems.length;
        if (rawItems.isNotEmpty || page['hasMore'] == true) {
          _emitSyncProgress(
            MessageSyncProgress(
              ownerId: owner,
              stage: MessageSyncStage.pullingChanges,
              startedAt: startedAt,
              completedBatches: pagesFetched,
              processedItems: totalItemsProcessed,
            ),
          );
        }

        final itemsByUnit = <String, List<Map<String, dynamic>>>{};
        final updatedIdsByUnit = <String, List<int>>{};

        for (final raw in rawItems) {
          final row = Map<String, dynamic>.from(raw as Map);
          final unit = row['sessionUnitId']?.toString();
          final changeType = row['changeType']?.toString();
          final messageId = row['messageId'];
          final changeId = row['messageChangeId']?.toString() ?? '0';
          if (unit == null || unit.isEmpty || messageId == null) {
            throw StateError('Incomplete message change scope');
          }
          if (changeType != 'Recalled' && changeType != 'Updated') {
            throw StateError('Unsupported message change type: $changeType');
          }

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
          _checkActive();
          final expectedIds = entry.value.toSet();
          for (final state in states) {
            final id = int.tryParse('${state['messageId']}');
            if (id == null || !expectedIds.remove(id)) {
              throw StateError('Unexpected message state');
            }
          }
          if (expectedIds.isNotEmpty) {
            throw StateError('Message state response is incomplete');
          }
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
                  final merged =
                      existing != null
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
                  _checkActive();
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
          _checkActive();
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
                            row['isDeleted'] == true &&
                            row['messageId'] != null,
                      )
                      .map((row) => int.parse('${row['messageId']}'))
                      .toList(),
            );
          }
        }

        final newCursor = _formatV2Cursor(pageEpoch, nextCursor);
        _checkActive();
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
    } finally {
      _emitSyncProgress(MessageSyncProgress.idle(owner));
    }
  }
}
