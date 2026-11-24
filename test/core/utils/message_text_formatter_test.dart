import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/utils/message_text_formatter.dart';

void main() {
  group('message_text_formatter im:// protocol tests', () {
    test('parses im://session-unit?id= and im://announcement?id=', () {
      const input =
          '<a href="im://session-unit?id=unit-1">13：林惠娟</a> 发布了新公告：《<a href="im://announcement?id=ann-1">22</a>》';

      final nodes = parseMessageTagNodes(input);
      expect(nodes.length, 4);
      expect(nodes[0].type, MessageTagType.sessionUnit);
      expect(nodes[0].text, '13：林惠娟');
      expect(nodes[0].value, 'unit-1');
      expect(nodes[0].route, 'session-unit');

      expect(nodes[1].type, MessageTagType.text);
      expect(nodes[1].text, ' 发布了新公告：《');

      expect(nodes[2].type, MessageTagType.appLink);
      expect(nodes[2].text, '22');
      expect(nodes[2].value, 'ann-1');
      expect(nodes[2].route, 'announcement');
      expect(nodes[2].params, {'id': 'ann-1'});

      expect(nodes[3].type, MessageTagType.text);
      expect(nodes[3].text, '》');

      expect(stripMessageTags(input), '13：林惠娟 发布了新公告：《22》');
    });

    test('supports configurable custom schemes', () {
      configureAppLinkSchemes(['im', 'app', 'gotoim']);
      addTearDown(() => configureAppLinkSchemes(kDefaultAppLinkSchemes));

      const input = '查看 <a href="gotoim://chat-object?id=10086">客服中心</a>';
      final nodes = parseMessageTagNodes(input);
      expect(nodes.length, 2);
      expect(nodes[1].type, MessageTagType.chatObject);
      expect(nodes[1].value, '10086');
      expect(nodes[1].scheme, 'gotoim');
    });

    test('remains backwards-compatible with uid and oid attributes', () {
      const input = '<a uid="u1">张三</a> 邀请 <a oid="o1">产品群</a>';
      final nodes = parseMessageTagNodes(input);
      expect(nodes[0].type, MessageTagType.sessionUnit);
      expect(nodes[0].value, 'u1');
      expect(nodes[2].type, MessageTagType.chatObject);
      expect(nodes[2].value, 'o1');
    });

    test('parses bare im:// links and @mentions when enabled', () {
      const input = '请 @张三 查看 im://settings 和 https://example.com';
      final nodes = parseMessageTagNodes(input, parseMentions: true);
      expect(nodes.any((n) => n.type == MessageTagType.mention && n.value == '张三'), isTrue);
      expect(nodes.any((n) => n.type == MessageTagType.appLink && n.route == 'settings'), isTrue);
      expect(nodes.any((n) => n.type == MessageTagType.link && n.href == 'https://example.com'), isTrue);
    });

    test('preprocessAnnouncementMarkdownLinks skips code blocks and existing links', () {
      const md = '通知 @李四 看下 `[跳过 @王五]` 与 ```\n@赵六\n``` 以及 [@已有](im://session-unit?id=1)';
      final result = preprocessAnnouncementMarkdownLinks(md);
      expect(result, contains('[@李四](im://mention?name=%E6%9D%8E%E5%9B%9B)'));
      expect(result, contains('```\n@赵六\n```'));
      expect(result, contains('[@已有](im://session-unit?id=1)'));
    });
  });
}
