import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:gotoim_flutter/core/services/file/attachment_transfer_service.dart';
import 'package:gotoim_flutter/core/theme/app_theme.dart';
import 'package:gotoim_flutter/core/widgets/chat_bubble.dart';
import 'package:gotoim_flutter/features/chat/data/models/chat_message.dart';
import 'package:gotoim_flutter/features/chat/presentation/widgets/chat_message_row.dart';
import 'package:gotoim_flutter/features/session/presentation/chat_object_avatar.dart';

void main() {
  setUpAll(() => dotenv.loadFromString(envString: 'APP_NAME=Test'));

  ChatMessage makeMessage({
    required int id,
    required int messageType,
    String text = 'Hello',
    bool isMine = false,
    Map<String, dynamic>? content,
  }) =>
      ChatMessage(
        localId: 'local-$id',
        serverId: id,
        clientMessageId: 'client-$id',
        ownerId: 1,
        sessionUnitId: 'session-1',
        senderSessionUnitId: isMine ? 'mine' : 'peer',
        messageType: messageType,
        state: 'sent',
        score: id,
        createdAt: DateTime(2026, 8, 26, 12),
        raw: <String, dynamic>{
          'senderSessionUnit': {'displayName': 'TestUser'},
          if (content != null) 'content': content,
          if (content == null && messageType == 0) 'content': {'text': text},
        },
      );

  Widget buildRow(ChatMessage message) {
    return ProviderScope(
      overrides: [
        appEnvironmentProvider.overrideWithValue(
          AppEnvironment.fromDotEnv(AppFlavor.development),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme(),
        home: Scaffold(
          body: ChatMessageRow(
            message: message,
            showTime: false,
            onUserTap: () {},
            onVoiceOpened: () async {},
            onLinkTap: () async {},
            mediaItems: const [],
            mediaInitialIndex: 0,
            attachmentState: const AttachmentTransferState(
              status: AttachmentTransferStatus.idle,
            ),
            onAttachmentDownload: () async {},
            onAttachmentCancel: () async {},
            onAttachmentOpen: () async {},
            onAttachmentSaveAs: () async {},
            imageBytes: null,
            uploadProgress: null,
            apiBaseUrl: 'http://localhost',
            selected: false,
            selectionMode: false,
            onQuoteTap: () {},
            showUnreadDivider: false,
            showPeerRead: false,
          ),
        ),
      ),
    );
  }

  testWidgets('ChatMessageRow renders avatar with size 44', (tester) async {
    final msg = makeMessage(id: 1, messageType: 0, text: 'Hi');
    await tester.pumpWidget(buildRow(msg));
    await tester.pumpAndSettle();

    final avatarFinder = find.byType(ChatObjectAvatar);
    expect(avatarFinder, findsOneWidget);
    final avatar = tester.widget<ChatObjectAvatar>(avatarFinder);
    expect(avatar.size, 44.0);
    expect(avatar.radius, 22.0);

    final avatarSize = tester.getSize(avatarFinder);
    expect(avatarSize.width, 44.0);
    expect(avatarSize.height, 44.0);
  });

  testWidgets('TextMessage has ChatBubble and satisfies minWidth 22, minHeight 44', (
    tester,
  ) async {
    final msg = makeMessage(id: 2, messageType: 0, text: 'a');
    await tester.pumpWidget(buildRow(msg));
    await tester.pumpAndSettle();

    final bubbleFinder = find.byType(ChatBubble);
    expect(bubbleFinder, findsOneWidget);

    final bubbleSize = tester.getSize(bubbleFinder);
    expect(bubbleSize.width, greaterThanOrEqualTo(22.0));
    expect(bubbleSize.height, greaterThanOrEqualTo(44.0));
  });

  testWidgets('ImageMessage (Type 2) does NOT wrap ChatBubble', (
    tester,
  ) async {
    final msg = makeMessage(
      id: 3,
      messageType: 2,
      content: {
        'url': 'http://localhost/image.png',
        'width': 100,
        'height': 100,
      },
    );
    await tester.pumpWidget(buildRow(msg));
    await tester.pump();

    expect(find.byType(ChatBubble), findsNothing);
  });

  testWidgets('VideoMessage (Type 4) does NOT wrap ChatBubble', (
    tester,
  ) async {
    final msg = makeMessage(
      id: 4,
      messageType: 4,
      content: {
        'url': 'http://localhost/video.mp4',
        'width': 160,
        'height': 90,
      },
    );
    await tester.pumpWidget(buildRow(msg));
    await tester.pump();

    expect(find.byType(ChatBubble), findsNothing);
  });
}
