import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/widgets/measure_size.dart';
import 'package:gotoim_flutter/features/chat/data/models/chat_message.dart';
import 'package:gotoim_flutter/features/chat/presentation/widgets/chat_message_list.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ChatMessage createMessage(String localId, String text) {
    return ChatMessage(
      localId: localId,
      serverId: int.tryParse(localId),
      clientMessageId: localId,
      ownerId: 100,
      sessionUnitId: 'u-1',
      senderSessionUnitId: 'u-1',
      messageType: 0,
      state: 'sent',
      score: int.tryParse(localId) ?? 0,
      createdAt: DateTime.now(),
      raw: <String, dynamic>{
        'content': <String, dynamic>{'text': text},
      },
    );
  }

  group('MeasureSize Tests', () {
    testWidgets('MeasureSize notifies correct rendered size', (tester) async {
      Size? capturedSize;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MeasureSize(
              onSizeChanged: (size) => capturedSize = size,
              child: const SizedBox(width: 200, height: 80),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(capturedSize, isNotNull);
      expect(capturedSize!.width, equals(200.0));
      expect(capturedSize!.height, equals(80.0));
    });
  });

  group('ChatMessageList Entry Transition Tests', () {
    testWidgets('Initial history messages do not trigger entry animation and render directly', (tester) async {
      final initialMessages = [
        createMessage('1', '历史消息 1'),
        createMessage('2', '历史消息 2'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatMessageList(
              messages: initialMessages,
              scrollController: ScrollController(),
              isLoading: false,
              hasMore: false,
              error: null,
              onViewingLatestChanged: (_) {},
              onLoadMore: () async {},
              onTapOutside: () {},
              itemBuilder: (context, message, index) => Text(message.text),
            ),
          ),
        ),
      );

      // 历史消息首帧立即渲染，无需等待动画
      expect(find.text('历史消息 1'), findsOneWidget);
      expect(find.text('历史消息 2'), findsOneWidget);

      // 检查此时没有 SizeTransition 动画处于进行态（未被动画控制）
      final sizeTransitions = tester.widgetList<SizeTransition>(find.byType(SizeTransition));
      expect(sizeTransitions, isEmpty);
    });

    testWidgets('New message added at the head triggers entry transition animation', (tester) async {
      final initialMessages = [
        createMessage('1', '已存在的旧消息'),
      ];

      final scrollController = ScrollController();
      late StateSetter testSetState;
      var currentMessages = List<ChatMessage>.from(initialMessages);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                testSetState = setState;
                return ChatMessageList(
                  messages: currentMessages,
                  scrollController: scrollController,
                  isLoading: false,
                  hasMore: false,
                  error: null,
                  onViewingLatestChanged: (_) {},
                  onLoadMore: () async {},
                  onTapOutside: () {},
                  itemBuilder: (context, message, index) => Text(message.text),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('已存在的旧消息'), findsOneWidget);

      // 发送/接收一条新消息（添加到头部 index 0）
      testSetState(() {
        currentMessages = [
          createMessage('2', '刚刚新收到的消息'),
          ...currentMessages,
        ];
      });

      // 触发首帧重绘，新消息触发了入场动画组件
      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SlideTransition && widget.position.value.dy > 0.0,
          skipOffstage: false,
        ),
        findsOneWidget,
      );

      // 前进 100ms，动画平滑过渡中
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('刚刚新收到的消息', skipOffstage: false), findsOneWidget);

      // 推进直到动画完成 (260ms)
      await tester.pumpAndSettle();
      expect(find.text('刚刚新收到的消息'), findsOneWidget);
    });
  });
}
