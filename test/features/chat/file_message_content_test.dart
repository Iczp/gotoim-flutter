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
  Widget build(AttachmentTransferState state) => MaterialApp(
    home: Scaffold(
      body: FileMessageContent(
        message: _message(),
        transfer: state,
        onDownload: () async {},
        onCancel: () async {},
        onOpen: () async {},
        onSaveAs: () async {},
      ),
    ),
  );

  testWidgets('file bubble renders percentage and cancel while downloading', (
    tester,
  ) async {
    await tester.pumpWidget(
      build(
        const AttachmentTransferState(
          status: AttachmentTransferStatus.downloading,
          receivedBytes: 45,
          totalBytes: 100,
        ),
      ),
    );

    expect(find.text('下载 45%'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('downloaded file offers open and save as', (tester) async {
    await tester.pumpWidget(
      build(
        const AttachmentTransferState(
          status: AttachmentTransferStatus.completed,
          localPath: 'C:/cache/report.pdf',
        ),
      ),
    );

    expect(find.text('打开'), findsOneWidget);
    expect(find.text('另存为'), findsOneWidget);
  });
}
