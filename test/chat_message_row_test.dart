import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/config/app_environment.dart';
import 'package:gotoim_flutter/core/services/file/attachment_transfer_service.dart';
import 'package:gotoim_flutter/core/services/media/audio_playback_service.dart';
import 'package:gotoim_flutter/core/theme/app_theme.dart';
import 'package:gotoim_flutter/core/widgets/chat_bubble.dart';
import 'package:gotoim_flutter/features/chat/application/chat_controller.dart';
import 'package:gotoim_flutter/features/chat/data/models/chat_message.dart';
import 'package:gotoim_flutter/features/chat/presentation/widgets/chat_message_row.dart';
import 'package:gotoim_flutter/features/session/presentation/chat_object_avatar.dart';

class FakeAudioPlaybackService extends ChangeNotifier
    implements AudioPlaybackService {
  @override
  bool isMessagePlaying(String messageId) => false;
  @override
  String? get downloadingMessageId => null;
  @override
  String? get activeMessageId => null;
  @override
  Duration get duration => Duration.zero;
  @override
  Duration get position => Duration.zero;
  @override
  bool get isEarpiece => false;
  @override
  double get downloadProgress => 0.0;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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
        senderSessionUnitId: isMine ? 'session-1' : 'peer',
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

  Widget buildRow(
    ChatMessage message, {
    bool showAvatar = true,
    bool selectionMode = false,
    bool selected = false,
    VoidCallback? onRetry,
  }) {
    return ProviderScope(
      overrides: [
        appEnvironmentProvider.overrideWithValue(
          AppEnvironment.fromDotEnv(AppFlavor.development),
        ),
        audioPlaybackServiceProvider.overrideWith(
          (ref) => FakeAudioPlaybackService(),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme(),
        home: Scaffold(
          body: ChatMessageRow(
            message: message,
            showTime: false,
            showAvatar: showAvatar,
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
            onRetry: onRetry,
            imageBytes: null,
            uploadProgress: null,
            apiBaseUrl: 'http://localhost',
            selected: selected,
            selectionMode: selectionMode,
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

  testWidgets('ChatMessageRow respects showAvatar: false', (tester) async {
    final msg = makeMessage(id: 10, messageType: 0, text: 'No Avatar');
    await tester.pumpWidget(buildRow(msg, showAvatar: false));
    await tester.pumpAndSettle();

    expect(find.byType(ChatObjectAvatar), findsNothing);
  });

  testWidgets('ChatMessageRow renders Checkbox when selectionMode is true', (
    tester,
  ) async {
    final msg = makeMessage(id: 11, messageType: 0, text: 'Selectable');
    await tester.pumpWidget(
      buildRow(msg, selectionMode: true, selected: true),
    );
    await tester.pumpAndSettle();

    final checkboxFinder = find.byType(Checkbox);
    expect(checkboxFinder, findsOneWidget);
    final checkbox = tester.widget<Checkbox>(checkboxFinder);
    expect(checkbox.value, true);
  });

  testWidgets('TextMessage renders sending indicator when isMine and state is sending', (
    tester,
  ) async {
    final msg = makeMessage(
      id: 12,
      messageType: 0,
      text: 'Sending msg',
      isMine: true,
    );
    // Overwrite state to sending
    final sendingMsg = ChatMessage(
      localId: msg.localId,
      serverId: msg.serverId,
      clientMessageId: msg.clientMessageId,
      ownerId: msg.ownerId,
      sessionUnitId: msg.sessionUnitId,
      senderSessionUnitId: msg.senderSessionUnitId,
      messageType: msg.messageType,
      state: 'sending',
      score: msg.score,
      createdAt: msg.createdAt,
      raw: msg.raw,
    );
    await tester.pumpWidget(buildRow(sendingMsg));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(ChatBubble), findsOneWidget);
  });

  testWidgets('TextMessage renders retry button when isMine and state is failed', (
    tester,
  ) async {
    var retried = false;
    final failedMsg = ChatMessage(
      localId: 'local-13',
      serverId: null,
      clientMessageId: 'client-13',
      ownerId: 1,
      sessionUnitId: 'session-1',
      senderSessionUnitId: 'session-1', // isMine = true
      messageType: 0,
      state: 'failed',
      score: 13,
      createdAt: DateTime(2026, 8, 26, 12),
      raw: const <String, dynamic>{},
    );
    await tester.pumpWidget(
      buildRow(failedMsg, onRetry: () => retried = true),
    );
    await tester.pumpAndSettle();

    final retryIconFinder = find.byIcon(Icons.error);
    expect(retryIconFinder, findsOneWidget);
    await tester.tap(retryIconFinder);
    expect(retried, true);
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

  testWidgets('VoiceMessage (Type 3) renders red dot when unread peer message', (
    tester,
  ) async {
    final msg = makeMessage(
      id: 5,
      messageType: 3,
      isMine: false,
      content: {'time': 5000},
    );
    await tester.pumpWidget(buildRow(msg));
    await tester.pumpAndSettle();

    expect(find.byType(ChatBubble), findsOneWidget);
    final redDotFinder = find.byWidgetPredicate((widget) {
      if (widget is Container && widget.decoration is BoxDecoration) {
        final deco = widget.decoration as BoxDecoration;
        return deco.color == Colors.red && deco.shape == BoxShape.circle;
      }
      return false;
    });
    expect(redDotFinder, findsOneWidget);
  });
}
