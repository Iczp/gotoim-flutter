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
}
