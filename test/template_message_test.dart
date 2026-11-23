import 'dart:io';

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

    test('02-full-card should be valid and parse layout, data, actions, resources', () {
      final raw = loadFixture('02-full-card.json');
      final res = TemplateSnapshot.parse(raw);
      expect(res.valid, isTrue);
      expect(res.snapshot?.templateName, '维修工单');
      expect(res.snapshot?.data['orderNo'], 'WX20261123001');
      expect(res.snapshot?.actions.length, 1);
      expect(res.snapshot?.actions.first.type, 'openUrl');
      expect(res.snapshot?.data['detailUrl'], 'https://workorder.example.com/tickets/WX20261123001');
    });

    test('03-optional-field-missing should be valid with missing field data', () {
      final raw = loadFixture('03-optional-field-missing.json');
      final res = TemplateSnapshot.parse(raw);
      expect(res.valid, isTrue);
      expect(res.snapshot?.data['contactPhone'], isNull);
    });

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
      expect(res.valid, isTrue);
      final dangerousUrl = res.snapshot?.data['maliciousUrl']?.toString();
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

    test('09-corrupted-payload should return fallback text on corrupted json or invalid root', () {
      final raw = loadFixture('09-corrupted-payload.json');
      final res = TemplateSnapshot.parse(raw);
      expect(res.valid, isFalse);
      expect(res.errorReason, 'root_node_must_be_card');
      expect(res.fallbackText, '[模板消息] 内容暂不可用');

      final broken = TemplateSnapshot.parse('{"invalidJson: true');
      expect(broken.valid, isFalse);
      expect(broken.errorReason, 'corrupted_json');
      expect(broken.fallbackText, '[模板消息] 内容暂不可用');
    });

    test('session summary helpers should handle template message type 13', () {
      final typeLabel = messageContentType({'messageType': 13});
      expect(typeLabel, '[模板消息]');

      final preview = messageContentText({
        'messageType': 13,
        'content': {'fallbackText': '工单WX001派发通知'},
      });
      expect(preview, '工单WX001派发通知');
    });
  });
}
