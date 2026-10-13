import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/features/chat/data/models/article_message_item.dart';
import 'package:gotoim_flutter/features/chat/data/models/chat_message.dart';
import 'package:gotoim_flutter/features/chat/presentation/message_content/article_message_content.dart';
import 'package:gotoim_flutter/features/chat/presentation/message_content/chat_message_presentation.dart';
import 'package:gotoim_flutter/features/session/data/models/session_summary_helpers.dart';

Map<String, dynamic> item(String title, String url) => {
  'title': title,
  'originalUrl': url,
};
ChatMessage message(Object? content) => ChatMessage.fromJson(
  {'id': 11, 'messageType': 11, 'content': content},
  ownerId: 1,
  sessionUnitId: 'unit',
);

void main() {
  test('ordered group and legacy content are readable', () {
    final content = {
      'items': [
        item('一', 'https://example.com/1'),
        item('二', 'https://example.com/2'),
      ],
    };
    expect(message(content).articleItems.map((e) => e.title), ['一', '二']);
    expect(
      ArticleMessageItem.fromContent(item('旧文章', 'https://example.com'))
          .single
          .title,
      '旧文章',
    );
    expect(ArticleMessageItem.fromContent(null), isEmpty);
    expect(
      messageContentText({'messageType': 11, 'content': content}),
      '一 等2篇',
    );
  });
  testWidgets('each row opens its own article and fits a narrow window', (
    tester,
  ) async {
    final opened = <String>[];
    final content = {
      'items': [
        item('一', 'https://example.com/1'),
        item('二', 'https://example.com/2'),
      ],
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 230,
            child: ArticleMessageContent(
              message: message(content),
              onArticleTap: (article) async {
                opened.add(article.originalUrl);
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('article-item-1')));
    await tester.tap(find.byKey(const ValueKey('article-item-0')));
    expect(opened, ['https://example.com/2', 'https://example.com/1']);
    expect(tester.takeException(), isNull);
  });
  testWidgets('quote is compact and unsafe links cannot open', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArticleMessageContent(
            message: message(item('危险链接', 'javascript:alert(1)')),
            onArticleTap: (_) async {
              opened = true;
            },
            presentation: ChatMessagePresentation.quote,
          ),
        ),
      ),
    );
    await tester.tap(find.text('危险链接'));
    expect(opened, isFalse);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('single article renders cover image and bottom title area', (
    tester,
  ) async {
    final content = {
      'items': [
        {
          'title': '这位快递小哥的“移动工位”，火了！',
          'description': '移动工位走红网络',
          'author': '央视新闻',
          'originalUrl': 'https://news.cctv.com/article/1',
        },
      ],
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArticleMessageContent(
            message: message(content),
          ),
        ),
      ),
    );
    expect(find.text('这位快递小哥的“移动工位”，火了！'), findsOneWidget);
    expect(find.text('移动工位走红网络'), findsOneWidget);
    expect(find.text('央视新闻'), findsOneWidget);
    expect(find.byType(Divider), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('multi article renders top lead item and sub items with dividers', (
    tester,
  ) async {
    final content = {
      'items': [
        {
          'title': '俄军反制不隔夜，火力全开击打日本工厂',
          'originalUrl': 'https://news.qq.com/1',
        },
        {
          'title': '《庆余年》神预测：京都掀起鏖战',
          'originalUrl': 'https://news.qq.com/2',
        },
        {
          'title': '山东小伙模仿“济公”爆火全网',
          'originalUrl': 'https://news.qq.com/3',
        },
      ],
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArticleMessageContent(
            message: message(content),
          ),
        ),
      ),
    );
    expect(find.text('俄军反制不隔夜，火力全开击打日本工厂'), findsOneWidget);
    expect(find.text('《庆余年》神预测：京都掀起鏖战'), findsOneWidget);
    expect(find.text('山东小伙模仿“济公”爆火全网'), findsOneWidget);
    // 3 items -> 2 dividers
    expect(find.byType(Divider), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}

