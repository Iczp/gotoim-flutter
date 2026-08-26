import '../datasources/session_dao.dart';
import '../datasources/session_unit_api.dart';
import '../models/session_summary.dart';

class SessionRepository {
  SessionRepository({required SessionUnitApi api, required SessionDao dao})
      : _api = api,
        _dao = dao;

  final SessionUnitApi _api;
  final SessionDao _dao;

  Future<List<SessionSummary>> loadCached({int limit = 50}) =>
      _dao.readRecent(limit: limit);

  Future<List<SessionSummary>> sync({int? ownerId, int limit = 50}) async {
    final page = await _api.getFriends(
      ownerId: ownerId,
      maxResultCount: limit,
    );
    await _dao.upsertAll(page.items);
    return _dao.readRecent(limit: limit);
  }
}
