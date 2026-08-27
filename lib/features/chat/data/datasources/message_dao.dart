import '../../../../core/database/unified_database.dart';
import '../models/chat_message.dart';

class MessageDao {
  MessageDao(this._database);
  final UnifiedDatabase _database;

  Future<List<ChatMessage>> readPage({
    required int ownerId,
    required String sessionUnitId,
    int? beforeScore,
    int limit = 30,
  }) async => (await _database.readMessageRows(
    ownerId: ownerId,
    sessionUnitId: sessionUnitId,
    beforeScore: beforeScore,
    limit: limit,
  )).map(ChatMessage.fromDatabaseRow).toList(growable: false);

  Future<void> upsertAll(List<ChatMessage> messages) =>
      _database.upsertMessageRows(
        messages
            .map((message) => message.toDatabaseValues())
            .toList(growable: false),
      );

  Future<int> maxScore(int ownerId, String sessionUnitId) =>
      _database.readMaxMessageScore(ownerId, sessionUnitId);
}
