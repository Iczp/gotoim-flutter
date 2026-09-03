import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gotoim_flutter/core/services/file/attachment_transfer_service.dart';
import 'package:gotoim_flutter/features/chat/data/models/chat_message.dart';
import 'package:gotoim_flutter/features/chat/presentation/message_content/file_message_content.dart';

ChatMessage _message() => ChatMessage(
  localId: 'file-1',
  serverId: 1,
  clientMessageId: 'file-1',
  ownerId: 1,
  sessionUnitId: 'session-1',
  senderSessionUnitId: 'session-2',
  messageType: 5,
  state: 'received',
  score: 1,
  createdAt: DateTime(2026),
  raw: const <String, dynamic>{
    'content': <String, dynamic>{
      'fileName': 'report.pdf',
      'size': 1024,
      'url': '/files/report.pdf',
    },
  },
);

void main() {
  Widget build(
    AttachmentTransferState state, {
    VoidCallback? onCancel,
    VoidCallback? onOpen,
    VoidCallback? onSaveAs,
    VoidCallback? onDownload,
  }) => MaterialApp(
    home: Scaffold(
      body: FileMessageContent(
        message: _message(),
        transfer: state,
        onDownload: () async => onDownload?.call(),
        onCancel: () async => onCancel?.call(),
        onOpen: () async => onOpen?.call(),
        onSaveAs: () async => onSaveAs?.call(),
      ),
    ),
  );

  testWidgets('file bubble renders floating percentage and triggers cancel on tap', (
    tester,
  ) async {
    var cancelled = false;
    await tester.pumpWidget(
      build(
        const AttachmentTransferState(
          status: AttachmentTransferStatus.downloading,
          receivedBytes: 45,
          totalBytes: 100,
        ),
        onCancel: () => cancelled = true,
      ),
    );

    // Floating percentage on icon
    expect(find.text('45%'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // PDF tag
    expect(find.text('PDF'), findsOneWidget);

    // Tapping the card while downloading cancels it
    await tester.tap(find.byType(FileMessageContent));
    expect(cancelled, isTrue);
  });

  testWidgets('downloaded file renders completed state and triggers open on tap', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      build(
        const AttachmentTransferState(
          status: AttachmentTransferStatus.completed,
          localPath: 'C:/cache/report.pdf',
        ),
        onOpen: () => opened = true,
      ),
    );

    expect(find.text('已下载'), findsOneWidget);
    expect(find.byIcon(Icons.save_alt_rounded), findsOneWidget);

    // Tapping the card opens the file
    await tester.tap(find.text('report.pdf'));
    expect(opened, isTrue);
  });
}
