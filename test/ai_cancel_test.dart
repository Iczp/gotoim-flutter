import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/database/unified_database.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/features/session/data/datasources/ai_api.dart';
import 'package:gotoim_flutter/features/session/data/datasources/session_dao.dart';
import 'package:gotoim_flutter/features/session/data/datasources/session_unit_api.dart';
import 'package:gotoim_flutter/features/session/data/repositories/session_repository.dart';

void main() {
  test('AiApi.cancelAiRun sends post to /api/chat/ai/cancel with correct payload', () async {
    final client = _MockApiClient();
    final aiApi = AiApi(client);

    await aiApi.cancelAiRun(
      runId: 'run-123',
      sessionUnitId: 'session-456',
      sourceMessageId: 789,
    );

    expect(client.postCalls.length, 1);
    expect(client.postCalls[0].path, '/api/chat/ai/cancel');
    expect(client.postCalls[0].data, <String, dynamic>{
      'runId': 'run-123',
      'sessionUnitId': 'session-456',
      'sourceMessageId': 789,
    });
  });

  test('AiApi.cancelAiRun falls back to /api/chat/ai/cancel/{runId} on primary failure', () async {
    final client = _MockApiClient(failPrimary: true);
    final aiApi = AiApi(client);

    await aiApi.cancelAiRun(
      runId: 'run-999',
      sessionUnitId: 'session-888',
    );

    expect(client.postCalls.length, 2);
    expect(client.postCalls[0].path, '/api/chat/ai/cancel');
    expect(client.postCalls[1].path, '/api/chat/ai/cancel/run-999');
    expect(client.postCalls[1].data, <String, dynamic>{
      'runId': 'run-999',
      'sessionUnitId': 'session-888',
    });
  });

  test('SessionRepository.cancelAiRun forwards cancellation parameters to AiApi', () async {
    final client = _MockApiClient();
    final database = UnifiedDatabase(
      DatabaseConnection(NativeDatabase.memory()),
    );
    addTearDown(database.close);

    final repository = SessionRepository(
      api: SessionUnitApi(client),
      aiApi: AiApi(client),
      dao: SessionDao(database),
    );

    await repository.cancelAiRun(
      runId: 'run-abc',
      sessionUnitId: 'unit-xyz',
      sourceMessageId: 101,
    );

    expect(client.postCalls.length, 1);
    expect(client.postCalls[0].path, '/api/chat/ai/cancel');
    expect(client.postCalls[0].data, <String, dynamic>{
      'runId': 'run-abc',
      'sessionUnitId': 'unit-xyz',
      'sourceMessageId': 101,
    });
  });
}

class _PostCall {
  _PostCall(this.path, this.data);
  final String path;
  final Object? data;
}

class _MockApiClient implements ApiClient {
  _MockApiClient({this.failPrimary = false});
  final bool failPrimary;
  final List<_PostCall> postCalls = [];

  @override
  Future<T> post<T>(
    String path, {
    Map<String, Object?>? query,
    Object? data,
    Map<String, String>? headers,
    bool retryOnUnauthorized = true,
  }) async {
    postCalls.add(_PostCall(path, data));
    if (failPrimary && path == '/api/chat/ai/cancel') {
      throw StateError('Primary endpoint error');
    }
    return null as T;
  }

  @override
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    bool retryOnUnauthorized = true,
  }) async => throw UnimplementedError();

  @override
  Future<T> postMultipart<T>(
    String path, {
    Map<String, Object?>? query,
    Map<String, Object?>? extraFields,
    required MultipartUploadFile file,
    String fieldName = 'file',
    void Function(int sent, int total)? onProgress,
    bool retryOnUnauthorized = true,
  }) async => throw UnimplementedError();

  @override
  Future<void> cancelByTag(Object tag) async {}

  @override
  Future<List<int>> getBytes(
    String path, {
    Object? cancelTag,
    void Function(int received, int total)? onProgress,
  }) async => const <int>[];
}
