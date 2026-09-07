import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:gotoim_flutter/core/theme/app_theme.dart';
import 'package:gotoim_flutter/core/utils/message_text_formatter.dart';
import 'package:gotoim_flutter/core/utils/message_time_formatter.dart';
import 'package:gotoim_flutter/features/session/data/models/session_summary.dart';
import 'package:gotoim_flutter/features/session/presentation/relative_time_text.dart';
import 'package:gotoim_flutter/features/session/presentation/session_last_message_preview.dart';
import 'package:gotoim_flutter/features/session/presentation/session_unit_item.dart';

void main() {
  setUpAll(() => dotenv.loadFromString(envString: 'APP_NAME=Test'));
  group('message_text_formatter tests', () {
    test('stripMessageTags handles <a>user</a> correctly', () {
      const input = '欢迎 <a>user</a> 加入群聊';
      expect(stripMessageTags(input), equals('欢迎 user 加入群聊'));
    });

    test('stripMessageTags handles <a uid="...">name</a> and <a oid="...">room</a>', () {
      const input =
          '<a uid="fdc164ec-39bf-87bb-70aa-3a0e9fa5397e">林惠娟</a> 加入 <a oid="5847">研发群</a>';
      expect(stripMessageTags(input), equals('林惠娟 加入 研发群'));
    });

    test('stripMessageTags replaces newlines with space', () {
      const input = '第一行\n第二行\r\n第三行';
      expect(stripMessageTags(input), equals('第一行 第二行 第三行'));
    });

    test('parseMessageTagNodes correctly identifies nodes', () {
      const input = '你好 <a uid="1234">张三</a> 请加入 <a oid="5678">交流群</a>！';
      final nodes = parseMessageTagNodes(input);

      expect(nodes.length, equals(5));
      expect(nodes[0].type, equals(MessageTagType.text));
      expect(nodes[0].text, equals('你好 '));

      expect(nodes[1].type, equals(MessageTagType.sessionUnit));
      expect(nodes[1].text, equals('张三'));
      expect(nodes[1].value, equals('1234'));

      expect(nodes[2].type, equals(MessageTagType.text));
      expect(nodes[2].text, equals(' 请加入 '));

      expect(nodes[3].type, equals(MessageTagType.chatObject));
      expect(nodes[3].text, equals('交流群'));
      expect(nodes[3].value, equals('5678'));

      expect(nodes[4].type, equals(MessageTagType.text));
      expect(nodes[4].text, equals('！'));
    });
  });

  group('message_time_formatter tests', () {
    final baseNow = DateTime(2026, 9, 7, 15, 30, 0);

    test('returns "刚刚" for under 1 minute', () {
      final target = baseNow.subtract(const Duration(seconds: 35));
      expect(formatMessageTime(target, now: baseNow), equals('刚刚'));
    });

    test('returns "X分钟前" for under 60 minutes', () {
      final target = baseNow.subtract(const Duration(minutes: 12));
      expect(formatMessageTime(target, now: baseNow), equals('12分钟前'));
    });

    test('returns time with period when today but over 60 minutes and relative is false', () {
      final target = DateTime(2026, 9, 7, 9, 15);
      expect(formatMessageTime(target, now: baseNow, isRelative: false), equals('上午 09:15'));
    });

    test('returns "昨天 HH:mm" for yesterday', () {
      final target = DateTime(2026, 9, 6, 14, 20);
      expect(formatMessageTime(target, now: baseNow), equals('昨天 14:20'));
    });

    test('returns weekday for within 7 days', () {
      // 2026-09-07 is Monday (星期一)
      // 2026-09-04 is Friday (星期五)
      final target = DateTime(2026, 9, 4, 10, 5);
      expect(formatMessageTime(target, now: baseNow), equals('星期五 10:05'));
    });

    test('returns "M月d日 HH:mm" for same year', () {
      final target = DateTime(2026, 5, 20, 8, 30);
      expect(formatMessageTime(target, now: baseNow), equals('5月20日 08:30'));
    });

    test('returns "yyyy年M月d日" for different year', () {
      final target = DateTime(2025, 12, 1, 12, 0);
      expect(formatMessageTime(target, now: baseNow), equals('2025年12月1日'));
    });

    test('formatChatMessageTime formats concise date and time', () {
      final target = DateTime(2026, 9, 7, 14, 5);
      expect(formatChatMessageTime(target), equals('9-7 14:05'));
    });
  });

  group('RelativeTimeText and SessionLastMessagePreview Widgets', () {
    testWidgets('RelativeTimeText displays formatted relative time', (tester) async {
      final time = DateTime.now().subtract(const Duration(seconds: 10));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RelativeTimeText(time: time),
          ),
        ),
      );

      expect(find.text('刚刚'), findsOneWidget);
    });

    testWidgets('SessionLastMessagePreview strips tags and renders message preview correctly', (tester) async {
      final item = SessionSummary(
        id: 'unit-1',
        ownerId: 1,
        score: 1,
        ticks: 1,
        title: '测试群',
        preview: '<a uid="111">李四</a> 发送了 <a>重要通告</a>',
        updatedAt: DateTime.now(),
        unreadCount: 0,
        isPinned: false,
        raw: {
          'id': 'unit-1',
          'lastMessage': {
            'messageType': 0,
            'senderSessionUnit': {
              'id': 'unit-2',
              'displayName': '李四',
            },
          },
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SessionLastMessagePreview(item: item),
          ),
        ),
      );

      // Cleaned text should be "李四 发送了 重要通告", with no raw <a> tags
      expect(find.textContaining('李四 发送了 重要通告'), findsOneWidget);
      expect(find.textContaining('<a'), findsNothing);
    });

    testWidgets('SessionUnitItem renders with RelativeTimeText and SessionLastMessagePreview', (tester) async {
      final item = SessionSummary(
        id: 'unit-1',
        ownerId: 1,
        score: 1,
        ticks: 1,
        title: '产品交流群',
        preview: '欢迎 <a uid="999">王五</a> 加入群聊',
        updatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
        unreadCount: 3,
        isPinned: true,
        raw: {
          'id': 'unit-1',
          'publicBadge': 3,
          'lastMessage': {
            'messageType': 1,
          },
          'destination': {
            'id': 100,
            'name': '产品交流群',
          },
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appEnvironmentProvider.overrideWithValue(
              AppEnvironment.fromDotEnv(AppFlavor.development),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme(),
            home: Scaffold(
              body: SessionUnitItem(
                item: item,
                showDivider: true,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(SessionUnitItem), findsOneWidget);
      expect(find.byType(RelativeTimeText), findsOneWidget);
      expect(find.byType(SessionLastMessagePreview), findsOneWidget);
      expect(find.text('5分钟前'), findsOneWidget);
      expect(find.textContaining('欢迎 王五 加入群聊'), findsOneWidget);
    });
  });
}
