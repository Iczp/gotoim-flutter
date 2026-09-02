import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/widgets/floating_popover.dart';
import 'package:gotoim_flutter/features/chat/data/models/chat_message.dart';
import 'package:gotoim_flutter/features/chat/presentation/message_menu/chat_avatar_menu.dart';
import 'package:gotoim_flutter/features/chat/presentation/message_menu/chat_message_menu.dart';

ChatMessage _message({
  int type = 0,
  String state = 'sent',
  int? serverId = 1,
  bool mine = true,
  bool rollbacked = false,
}) =>
    ChatMessage(
      localId: 'local',
      serverId: serverId,
      clientMessageId: 'client',
      ownerId: 1,
      sessionUnitId: 'mine',
      senderSessionUnitId: mine ? 'mine' : 'other',
      messageType: type,
      state: state,
      score: 1,
      createdAt: DateTime(2026),
      raw: <String, dynamic>{
        if (rollbacked) 'isRollbacked': true,
        'content': {'text': 'hello'},
      },
    );

void main() {
  const builder = ChatMessageMenuBuilder();

  group('ChatMessageMenuBuilder Tests', () {
    test('sent self text offers reply, copy, forward, select, recall, and delete', () {
      final items = builder.build(
        ChatMessageMenuContext(message: _message(), canRecall: true),
      );
      expect(
        items.map((item) => item.id),
        containsAll(<String>[
          'reply',
          'copy',
          'forward',
          'select',
          'recall',
          'delete',
        ]),
      );
    });

    test('failed message only offers retry when the controller can retry it', () {
      final context = ChatMessageMenuContext(
        message: _message(state: 'failed', serverId: null),
        canRetry: true,
      );
      expect(builder.build(context).map((item) => item.id), <String>[
        'retry',
        'delete',
      ]);
      expect(
        builder
            .build(
              ChatMessageMenuContext(
                message: _message(state: 'failed', serverId: null),
              ),
            )
            .map((item) => item.id),
        <String>['delete'],
      );
    });

    test('recalled and system messages cannot expose invalid actions', () {
      expect(
        builder
            .build(ChatMessageMenuContext(message: _message(rollbacked: true)))
            .map((item) => item.id),
        <String>['delete'],
      );
      expect(
        builder.build(ChatMessageMenuContext(message: _message(type: 1))),
        isEmpty,
      );
    });
  });

  group('ChatMessageMenu Widget Tests', () {
    testWidgets('renders up to 8 items across 2 rows (4 per row) with icons and labels', (tester) async {
      final tapped = <String>[];
      final items = List.generate(
        6,
        (i) => ChatMessageMenuItem(
          id: 'item_$i',
          label: '选项$i',
          icon: Icons.star,
          onTap: () => tapped.add('item_$i'),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ChatMessageMenu(
                items: items,
                layoutMode: ChatMessageMenuLayoutMode.doubleRow,
              ),
            ),
          ),
        ),
      );

      expect(find.text('选项0'), findsOneWidget);
      expect(find.text('选项5'), findsOneWidget);
      expect(find.byType(Row), findsNWidgets(2)); // 4 items in row 1, 2 items in row 2

      await tester.tap(find.text('选项0'));
      expect(tapped, contains('item_0'));
    });

    testWidgets('shows "更多" button when items exceed max page limit and pages over on tap', (tester) async {
      final items = List.generate(
        10,
        (i) => ChatMessageMenuItem(
          id: 'item_$i',
          label: '功能$i',
          icon: Icons.circle,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ChatMessageMenu(
                items: items,
                layoutMode: ChatMessageMenuLayoutMode.doubleRow,
              ),
            ),
          ),
        ),
      );

      expect(find.text('功能0'), findsOneWidget);
      expect(find.text('功能6'), findsOneWidget);
      expect(find.text('更多'), findsOneWidget);
      expect(find.text('功能8'), findsNothing);

      // Tap "更多" to switch to next page
      await tester.tap(find.text('更多'));
      await tester.pumpAndSettle();

      expect(find.text('返回'), findsOneWidget);
      expect(find.text('功能7'), findsOneWidget);
      expect(find.text('功能8'), findsOneWidget);
      expect(find.text('功能9'), findsOneWidget);
    });
  });

  group('ChatAvatarMenu Widget Tests', () {
    testWidgets('renders vertically with icon, text, and dividers', (tester) async {
      var mentionTapped = false;
      var muteTapped = false;

      final items = [
        ChatAvatarMenuItem(
          id: 'mention',
          label: '@TA',
          icon: Icons.alternate_email,
          onTap: () => mentionTapped = true,
        ),
        ChatAvatarMenuItem(
          id: 'follow',
          label: '特别关注',
          icon: Icons.star_border,
        ),
        ChatAvatarMenuItem(
          id: 'mute',
          label: '禁言',
          icon: Icons.volume_off_outlined,
          onTap: () => muteTapped = true,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ChatAvatarMenu(items: items),
            ),
          ),
        ),
      );

      expect(find.text('@TA'), findsOneWidget);
      expect(find.text('特别关注'), findsOneWidget);
      expect(find.text('禁言'), findsOneWidget);
      expect(find.byType(Divider), findsNWidgets(2)); // Dividers between 3 items

      await tester.tap(find.text('@TA'));
      expect(mentionTapped, isTrue);

      await tester.tap(find.text('禁言'));
      expect(muteTapped, isTrue);
    });
  });

  group('FloatingPopover & Alignment Tests', () {
    testWidgets('second row in ChatMessageMenu is left aligned with first row', (tester) async {
      final items = List.generate(
        6,
        (i) => ChatMessageMenuItem(
          id: 'item_$i',
          label: 'Item$i',
          icon: Icons.star,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ChatMessageMenu(
                items: items,
                layoutMode: ChatMessageMenuLayoutMode.doubleRow,
              ),
            ),
          ),
        ),
      );

      final item0Pos = tester.getTopLeft(find.text('Item0'));
      final item4Pos = tester.getTopLeft(find.text('Item4')); // First item in row 2

      // Both should have the same horizontal X coordinate (left-aligned)
      expect(item0Pos.dx, equals(item4Pos.dx));
    });

    testWidgets('FloatingPopover clamps within screen bounds and does not overflow', (tester) async {
      final controller = FloatingPopoverController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  top: 10,
                  right: 10, // Near top-right corner
                  child: FloatingPopover(
                    controller: controller,
                    placement: FloatingPlacement.auto,
                    contentBuilder: (_) => const SizedBox(
                      width: 250,
                      height: 120,
                      child: Text('PopoverContent'),
                    ),
                    child: const SizedBox(width: 40, height: 40),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      controller.show();
      await tester.pumpAndSettle();

      expect(find.text('PopoverContent'), findsOneWidget);
      final popoverRect = tester.getRect(find.text('PopoverContent'));

      // Popover must be strictly within screen boundaries (>= 0 and <= screen.width)
      expect(popoverRect.left, greaterThanOrEqualTo(0.0));
      expect(popoverRect.right, lessThanOrEqualTo(800.0));
      expect(popoverRect.top, greaterThanOrEqualTo(0.0));
    });

    testWidgets('Avatar placement appears on the side without covering avatar and respects offset', (tester) async {
      final leftController = FloatingPopoverController();
      final rightController = FloatingPopoverController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                // Left avatar at x=16, y=400, size=36x36
                Positioned(
                  top: 400,
                  left: 16,
                  child: FloatingPopover(
                    controller: leftController,
                    placement: FloatingPlacement.avatar,
                    offset: const Offset(8, 0),
                    contentBuilder: (_) => const SizedBox(
                      width: 140,
                      height: 120,
                      child: Text('LeftAvatarMenu'),
                    ),
                    child: const SizedBox(width: 36, height: 36),
                  ),
                ),
                // Right avatar at right=16 (x=748 in 800-wide screen), y=400, size=36x36
                Positioned(
                  top: 400,
                  right: 16,
                  child: FloatingPopover(
                    controller: rightController,
                    placement: FloatingPlacement.avatar,
                    offset: const Offset(8, 0),
                    contentBuilder: (_) => const SizedBox(
                      width: 140,
                      height: 120,
                      child: Text('RightAvatarMenu'),
                    ),
                    child: const SizedBox(width: 36, height: 36),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // Test Left Avatar menu
      leftController.show();
      await tester.pumpAndSettle();

      expect(find.text('LeftAvatarMenu'), findsOneWidget);
      final leftMenuRect = tester.getRect(find.text('LeftAvatarMenu'));

      // Avatar is [16, 52]. Menu starts at targetRect.right + offset.dx = 52 + 8 = 60
      expect(leftMenuRect.left, equals(60.0));
      // Avatar is NOT covered (menu.left >= avatar.right)
      expect(leftMenuRect.left, greaterThanOrEqualTo(52.0));

      leftController.hide();
      await tester.pumpAndSettle();

      // Test Right Avatar menu
      rightController.show();
      await tester.pumpAndSettle();

      expect(find.text('RightAvatarMenu'), findsOneWidget);
      final rightMenuRect = tester.getRect(find.text('RightAvatarMenu'));

      // Right avatar is at [800 - 16 - 36, 800 - 16] = [748, 784]
      // Menu is on the left: rightMenuRect.right <= 748 (not covering avatar)
      expect(rightMenuRect.right, lessThanOrEqualTo(748.0));
      // Does not overflow screen left
      expect(rightMenuRect.left, greaterThanOrEqualTo(0.0));
    });
  });
}
