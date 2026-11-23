import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gotoim_flutter/features/chat/data/models/chat_message.dart';
import 'package:gotoim_flutter/features/chat/presentation/message_content/template_message_content.dart';
import 'package:gotoim_flutter/features/chat/presentation/message_content/chat_message_presentation.dart';
import 'package:gotoim_flutter/core/security/url_security_service.dart';
import 'package:gotoim_flutter/core/security/url_security_repository.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/features/chat/data/models/template_message_content.dart';
import 'package:gotoim_flutter/features/session/data/models/session_summary_helpers.dart';

void main() {
  final fixturesDir = Directory('test/fixtures/template-message');

  String loadFixture(String filename) {
    return File('${fixturesDir.path}/$filename').readAsStringSync();
  }

  group('Custom Template Message (v1) Flutter Tests', () {
    test('01-minimal-card should be valid and parse correctly', () {
      final raw = loadFixture('01-minimal-card.json');
      final res = TemplateSnapshot.parse(raw);
      expect(res.valid, isTrue);
      expect(res.snapshot, isNotNull);
      expect(res.snapshot?.schemaVersion, 1);
      expect(res.snapshot?.templateId, '4a82b63d-e9cd-4bed-8d41-c7bd12fe5001');
      expect(res.snapshot?.layout.type, 'card');
      expect(res.fallbackText, '[通知]系统初始化完成');
    });

    test(
      '02-full-card should be valid and parse layout, data, actions, resources',
      () {
        final raw = loadFixture('02-full-card.json');
        final res = TemplateSnapshot.parse(raw);
        expect(res.valid, isTrue);
        expect(res.snapshot?.templateName, '维修工单');
        expect(res.snapshot?.data['orderNo'], 'WX20261123001');
        expect(res.snapshot?.actions.length, 1);
        expect(res.snapshot?.actions.first.type, 'openUrl');
        expect(
          res.snapshot?.data['detailUrl'],
          'https://workorder.example.com/tickets/WX20261123001',
        );
      },
    );

    test(
      '03-optional-field-missing should be valid with missing field data',
      () {
        final raw = loadFixture('03-optional-field-missing.json');
        final res = TemplateSnapshot.parse(raw);
        expect(res.valid, isTrue);
        expect(res.snapshot?.data['contactPhone'], isNull);
      },
    );

    test('04-unknown-component should fallback gracefully', () {
      final raw = loadFixture('04-unknown-component.json');
      final res = TemplateSnapshot.parse(raw);
      expect(res.valid, isFalse);
      expect(res.errorReason, contains('unknown_component'));
      expect(res.fallbackText, '[工单]WX20261123004：待处理');
    });

    test('05-future-schema-version should fallback gracefully', () {
      final raw = loadFixture('05-future-schema-version.json');
      final res = TemplateSnapshot.parse(raw);
      expect(res.valid, isFalse);
      expect(res.errorReason, 'unsupported_schema_version');
      expect(res.fallbackText, '[未来工单]WX20261123005');
    });

    test('06-illegal-url should identify illegal protocols', () {
      final raw = loadFixture('06-illegal-url.json');
      final res = TemplateSnapshot.parse(raw);
      expect(res.valid, isFalse);
      final dangerousUrl = 'javascript:alert(1)';
      expect(isSafeHttpUrl(dangerousUrl), isFalse);
      expect(isSafeHttpUrl('http://example.com'), isTrue);
      expect(isSafeHttpUrl('https://example.com/path'), isTrue);
      expect(isSafeHttpUrl('javascript:alert(1)'), isFalse);
      expect(isSafeHttpUrl('data:text/html;base64,...'), isFalse);
      expect(isSafeHttpUrl('file:///etc/passwd'), isFalse);
    });

    test('07-too-deep-layout should reject depth > 6 and fallback', () {
      final raw = loadFixture('07-too-deep-layout.json');
      final res = TemplateSnapshot.parse(raw);
      expect(res.valid, isFalse);
      expect(res.errorReason, 'exceeded_max_depth');
      expect(res.fallbackText, '[超深测试]层级超出限制');
    });

    test('08-too-long-text should reject static text > 1000 and fallback', () {
      final raw = loadFixture('08-too-long-text.json');
      final res = TemplateSnapshot.parse(raw);
      expect(res.valid, isFalse);
      expect(res.errorReason, 'static_text_too_long');
      expect(res.fallbackText, '[超长测试]文本超出上限');
    });

    test(
      '09-corrupted-payload should return fallback text on corrupted json or invalid root',
      () {
        final raw = loadFixture('09-corrupted-payload.json');
        final res = TemplateSnapshot.parse(raw);
        expect(res.valid, isFalse);
        expect(res.errorReason, 'invalid_template_version');
        expect(res.fallbackText, '[模板消息] 内容暂不可用');

        final broken = TemplateSnapshot.parse('{"invalidJson: true');
        expect(broken.valid, isFalse);
        expect(broken.errorReason, 'corrupted_json');
        expect(broken.fallbackText, '[模板消息] 内容暂不可用');
      },
    );

    test('session summary helpers should handle template message type 13', () {
      final typeLabel = messageContentType({'messageType': 13});
      expect(typeLabel, '[模板消息]');

      final preview = messageContentText({
        'messageType': 13,
        'content': {'fallbackText': '工单WX001派发通知'},
      });
      expect(preview, '工单WX001派发通知');
    });
    Map<String, dynamic> snapshot() => Map<String, dynamic>.from(
      (jsonDecode(loadFixture('01-minimal-card.json')) as Map)['snapshot']
          as Map,
    );

    test('all shared fixtures obey their declared client expectations', () {
      for (final file in fixturesDir.listSync().whereType<File>()) {
        if (!file.path.endsWith('.json')) continue;
        final fixture = jsonDecode(file.readAsStringSync()) as Map;
        final expected = fixture['clientExpectation'] as Map;
        final result = TemplateSnapshot.parse(fixture['snapshot']);
        expect(!result.valid, expected['fallback'], reason: file.path);
        expect(
          result.fallbackText,
          expected['expectedFallbackText'],
          reason: file.path,
        );
      }
    });

    test(
      'rejects malformed shapes and unknown attributes without throwing',
      () {
        for (final node in <Object?>[
          null,
          1,
          {'type': 'text', 'text': 'x', 'html': true},
          {'type': 'text', 'text': 'x', 'bind': 'title'},
          {'type': 'text', 'bind': '__proto__'},
          {'type': 'text', 'bind': 'title', 'style': 'javascript'},
          {'type': 'column', 'children': 'invalid'},
          {'type': 'button', 'label': '运行', 'actionId': 'unregistered'},
        ]) {
          final input = snapshot();
          input['layout'] = {
            'type': 'card',
            'children': [node],
          };
          expect(TemplateSnapshot.parse(input).valid, isFalse, reason: '$node');
        }
        expect(TemplateSnapshot.parse({'schemaVersion': '1'}).valid, isFalse);
      },
    );

    test('enforces byte, data, image and action limits', () {
      for (final data in <Map<String, dynamic>>[
        {
          'nested': {'secret': true},
        },
        {'text': List.filled(2001, '长').join()},
        {'number': 9007199254740992},
        {for (var i = 0; i < 31; i++) 'field$i': 'value'},
      ]) {
        final input = snapshot()..['data'] = data;
        expect(TemplateSnapshot.parse(input).valid, isFalse);
      }
      final images = snapshot();
      images['layout'] = {
        'type': 'card',
        'children': List.generate(
          4,
          (_) => {'type': 'image', 'bind': 'missing'},
        ),
      };
      expect(TemplateSnapshot.parse(images).valid, isFalse);
      final huge = snapshot()..['padding'] = List.filled(65537, 'x').join();
      expect(TemplateSnapshot.parse(huge).errorReason, 'payload_too_large');
      final unsafeActions =
          snapshot()
            ..['actions'] = [
              {'id': 'x', 'type': 'openUrl', 'bind': 'url'},
            ]
            ..['data'] = {'url': 'https://user:password@example.com'};
      expect(TemplateSnapshot.parse(unsafeActions).valid, isFalse);
      final blob =
          snapshot()
            ..['resources'] = [
              {'id': 'cover', 'blobId': 'id'},
            ];
      expect(TemplateSnapshot.parse(blob).valid, isFalse);
    });

    test(
      'text length checks use actual length rather than fixture wording',
      () {
        final input = snapshot();
        input['layout'] = {
          'type': 'card',
          'children': [
            {'type': 'text', 'text': '实际单段静态文本上限1000字符'},
          ],
        };
        expect(TemplateSnapshot.parse(input).valid, isTrue);
        (input['layout'] as Map)['children'] = [
          {'type': 'text', 'text': List.filled(1001, '长').join()},
        ];
        expect(TemplateSnapshot.parse(input).valid, isFalse);
      },
    );

    test('rejects hostless credential and control-character URLs', () {
      for (final value in [
        'http:example.com',
        'https:///path',
        'https://user:password@example.com',
        'https://example.com/\npath',
        r'https://example.com\@evil.example',
      ]) {
        expect(isSafeHttpUrl(value), isFalse, reason: value);
      }
    });

    testWidgets(
      'nested rows fit narrow large-font cards and quote hides actions',
      (tester) async {
        final content = snapshot();
        content['data'] = {'title': '长标签', 'flag': true};
        content['layout'] = {
          'type': 'card',
          'children': [
            {
              'type': 'row',
              'children': [
                {'type': 'field', 'label': '这是一段很长的字段标签', 'bind': 'title'},
                {
                  'type': 'column',
                  'children': [
                    {'type': 'text', 'bind': 'flag'},
                    {'type': 'image', 'bind': 'missing'},
                    {'type': 'button', 'label': '复制', 'actionId': 'copy'},
                  ],
                },
              ],
            },
          ],
        };
        content['actions'] = [
          {'id': 'copy', 'type': 'copyText', 'bind': 'title'},
        ];
        final message = ChatMessage.fromJson(
          {'id': 1, 'messageType': 13, 'content': content},
          ownerId: 1,
          sessionUnitId: 'unit',
        );
        Widget host(ChatMessagePresentation presentation) => MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 170,
                  child: TemplateMessageContent(
                    message: message,
                    maxWidth: 170,
                    presentation: presentation,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpWidget(host(ChatMessagePresentation.normal));
        expect(find.text('是'), findsOneWidget);
        expect(find.byType(OutlinedButton), findsOneWidget);
        expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(host(ChatMessagePresentation.quote));
        expect(find.byType(OutlinedButton), findsNothing);
        expect(find.byType(Image), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'openUrl dispatches through the existing URL security provider',
      (tester) async {
        final content =
            snapshot()
              ..['data'] = {'url': 'https://example.com/safe'}
              ..['actions'] = [
                {'id': 'detail', 'type': 'openUrl', 'bind': 'url'},
              ]
              ..['layout'] = {
                'type': 'card',
                'children': [
                  {'type': 'button', 'label': '查看详情', 'actionId': 'detail'},
                ],
              };
        final security = RecordingUrlSecurityService();
        final message = ChatMessage.fromJson(
          {'id': 2, 'messageType': 13, 'content': content},
          ownerId: 1,
          sessionUnitId: 'unit',
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [urlSecurityServiceProvider.overrideWithValue(security)],
            child: MaterialApp(
              home: Scaffold(body: TemplateMessageContent(message: message)),
            ),
          ),
        );
        await tester.tap(find.text('查看详情'));
        expect(security.opened, ['https://example.com/safe']);
        expect(tester.takeException(), isNull);
      },
    );
  });
}

class RecordingUrlSecurityService extends UrlSecurityService {
  RecordingUrlSecurityService()
    : super(repository: _UnusedUrlSecurityRepository());
  final opened = <String>[];
  @override
  Future<void> openUrl(
    BuildContext context, {
    required String url,
    String? title,
    String? fallbackContent,
    bool useInterstitialPage = true,
  }) async {
    opened.add(url);
  }
}

class _UnusedUrlSecurityRepository implements UrlSecurityRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
