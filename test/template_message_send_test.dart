import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/database/unified_database.dart';
import 'package:gotoim_flutter/core/network/api_client.dart';
import 'package:gotoim_flutter/features/chat/application/chat_controller.dart';
import 'package:gotoim_flutter/features/chat/data/datasources/message_api.dart';
import 'package:gotoim_flutter/features/chat/data/datasources/message_dao.dart';
import 'package:gotoim_flutter/features/chat/data/repositories/message_repository.dart';
import 'package:gotoim_flutter/features/chat/presentation/widgets/template_message_composer.dart';

Map<String, dynamic> _fixture() =>
    jsonDecode(
          File(
            'test/fixtures/template-message/01-minimal-card.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

void main() {
  test(
    'template is persisted before HTTP and retry freezes request after DB reread',
    () async {
      final database = UnifiedDatabase(
        DatabaseConnection(NativeDatabase.memory()),
      );
      addTearDown(database.close);
      final dao = MessageDao(database);
      final snapshot = Map<String, dynamic>.from(_fixture()['snapshot'] as Map);
      final request = <String, dynamic>{
        'templateId': snapshot['templateId'],
        'templateVersion': 1,
        'data': {'message': '原始数据'},
      };
      final client = _TemplateClient()..responseSnapshot = snapshot;
      final repository = MessageRepository(api: MessageApi(client), dao: dao);
      client.onPost = () async {
        final stored = await dao.readPage(ownerId: 7, sessionUnitId: 'session');
        expect(stored, hasLength(1));
        expect(stored.single.state, 'sending');
        expect(stored.single.raw['_templateRequest'], request);
      };
      final failed = await repository.sendTemplate(
        ownerId: 7,
        sessionUnitId: 'session',
        content: request,
        snapshot: snapshot,
      );
      expect(failed.state, 'failed');
      expect(failed.clientMessageId!.length, lessThanOrEqualTo(26));
      (request['data'] as Map)['message'] = '修改后的数据';
      final reloaded =
          (await dao.readPage(ownerId: 7, sessionUnitId: 'session')).single;
      client.onPost = null;
      client.fail = false;
      final sent = await repository.retryTemplate(reloaded);
      expect(sent.state, 'sent');
      expect(sent.localId, failed.localId);
      expect(
        client.requests[0]['clientMessageId'],
        client.requests[1]['clientMessageId'],
      );
      expect((client.requests[1]['content'] as Map)['data'], {
        'message': '原始数据',
      });
      expect(
        (client.requests[1]['content'] as Map).keys,
        unorderedEquals(['templateId', 'templateVersion', 'data']),
      );
      expect(
        client.paths.every(
          (path) =>
              path ==
              '/api/chat/message-sender/send-template-content-message/session',
        ),
        isTrue,
      );
      final stored = await dao.readPage(ownerId: 7, sessionUnitId: 'session');
      expect(stored, hasLength(1));
      expect(stored.single.content, snapshot);
      expect(stored.single.raw['_templateRequest'], isEmpty);
      expect(await dao.readPage(ownerId: 8, sessionUnitId: 'session'), isEmpty);
    },
  );

  test(
    'usable list and fixed revision use the actual management contract',
    () async {
      final client = _TemplateClient();
      final api = MessageApi(client);
      await api.usableTemplates(ownerId: 7, skipCount: 20);
      expect(client.lastGet, '/api/chat/message-template');
      expect(client.lastQuery, {
        'ownerId': '7',
        'scope': 'usable',
        'skipCount': 20,
        'maxResultCount': 20,
      });
      await api.templateRevision('template', 3);
      expect(client.lastGet, '/api/chat/message-template/template/revisions/3');
    },
  );

  testWidgets('sender fills a frozen published revision and sends only data', (
    tester,
  ) async {
    final controller = _ComposerController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TemplateMessageComposer(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('系统通知'));
    await tester.pumpAndSettle();
    expect(controller.readRevision, 1);
    await tester.enterText(find.byType(TextFormField), '填写的数据');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(controller.request!['templateVersion'], 1);
    expect(controller.request!['data'], {'message': '填写的数据'});
    expect(
      controller.request!.keys,
      unorderedEquals(['templateId', 'templateVersion', 'data']),
    );
  });
}

class _TemplateClient implements ApiClient {
  var fail = true;
  Map<String, dynamic> responseSnapshot = {};
  final requests = <Map<String, dynamic>>[];
  final paths = <String>[];
  Future<void> Function()? onPost;
  String? lastGet;
  Map<String, Object?>? lastQuery;

  @override
  Future<T> post<T>(
    String path, {
    Map<String, Object?>? query,
    Object? data,
    Map<String, String>? headers,
    bool retryOnUnauthorized = true,
  }) async {
    paths.add(path);
    requests.add(jsonDecode(jsonEncode(data)) as Map<String, dynamic>);
    await onPost?.call();
    if (fail) throw StateError('timeout');
    return {'id': '501', 'messageType': 13, 'content': responseSnapshot} as T;
  }

  @override
  Future<T> get<T>(
    String path, {
    Map<String, Object?>? query,
    bool retryOnUnauthorized = true,
  }) async {
    lastGet = path;
    lastQuery = query;
    return <String, dynamic>{'items': [], 'totalCount': 0} as T;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _ComposerController implements ChatController {
  Map<String, dynamic>? request;
  int? readRevision;
  @override
  int get ownerId => 7;
  @override
  String get sessionUnitId => 'session';
  @override
  Future<Map<String, dynamic>> loadUsableTemplates({int skipCount = 0}) async =>
      {
        'totalCount': 1,
        'items': [
          {
            'id': (_fixture()['snapshot'] as Map)['templateId'],
            'name': '系统通知',
            'publishedVersion': 1,
          },
        ],
      };
  @override
  Future<Map<String, dynamic>> loadTemplateRevision(
    String id,
    int version,
  ) async {
    readRevision = version;
    return {'definitionJson': jsonEncode(_fixture()['definition'])};
  }

  @override
  Future<void> sendTemplate(
    Map<String, dynamic> content,
    Map<String, dynamic> snapshot,
  ) async {
    request = content;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
