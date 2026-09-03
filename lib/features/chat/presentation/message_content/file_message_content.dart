import 'package:flutter/material.dart';

import '../../../../core/services/file/attachment_transfer_service.dart';
import '../../data/models/chat_message.dart';
import 'chat_message_presentation.dart';
import 'message_bubble.dart';

/// Dedicated attachment bubble with a real, cancellable transfer lifecycle.
class FileMessageContent extends StatelessWidget {
  const FileMessageContent({
    required this.message,
    required this.transfer,
    required this.onDownload,
    required this.onCancel,
    required this.onOpen,
    required this.onSaveAs,
    this.presentation = ChatMessagePresentation.normal,
    super.key,
  });

  final ChatMessage message;
  final AttachmentTransferState transfer;
  final Future<void> Function() onDownload;
  final Future<void> Function() onCancel;
  final Future<void> Function() onOpen;
  final Future<void> Function() onSaveAs;
  final ChatMessagePresentation presentation;

  @override
  Widget build(BuildContext context) {
    final stateLabel = switch (transfer.status) {
      AttachmentTransferStatus.downloading => _downloadLabel(),
      AttachmentTransferStatus.completed => '已下载',
      AttachmentTransferStatus.cancelled => '下载已取消',
      AttachmentTransferStatus.failed => '下载失败',
      AttachmentTransferStatus.idle =>
        message.state == 'sending'
            ? '发送中'
            : message.state == 'failed'
            ? '发送失败'
            : message.fileSuffix,
    };
    if (presentation == ChatMessagePresentation.quote) {
      final action =
          transfer.isDownloading
              ? onCancel
              : transfer.isReady
              ? onOpen
              : onDownload;
      final icon =
          transfer.isDownloading
              ? Icons.close
              : transfer.isReady
              ? Icons.open_in_new
              : Icons.download_outlined;
      return InkWell(
        onTap: message.state == 'sending' ? null : action,
        onLongPress: transfer.isReady ? onSaveAs : null,
        borderRadius: BorderRadius.circular(6),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 18),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                message.fileName.isEmpty ? '文件' : message.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              _formatFileSize(message.fileSize),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      );
    }
    return MessageBubble(
      message: message,
      child: SizedBox(
        width: 240,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.insert_drive_file_outlined, size: 26),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message.fileName.isEmpty ? '文件' : message.fileName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (transfer.isDownloading) ...<Widget>[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: transfer.progress),
          ],
          const Divider(height: 18),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _formatFileSize(message.fileSize),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              Text(
                stateLabel,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color:
                      transfer.status == AttachmentTransferStatus.failed ||
                              message.state == 'failed'
                          ? Colors.red
                          : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 4,
            children: <Widget>[
              if (transfer.isDownloading)
                TextButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('取消'),
                )
              else if (transfer.isReady) ...<Widget>[
                TextButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('打开'),
                ),
                TextButton.icon(
                  onPressed: onSaveAs,
                  icon: const Icon(Icons.save_alt_outlined, size: 16),
                  label: const Text('另存为'),
                ),
              ] else
                TextButton.icon(
                  onPressed: message.state == 'sending' ? null : onDownload,
                  icon: const Icon(Icons.download_outlined, size: 16),
                  label: Text(
                    transfer.status == AttachmentTransferStatus.cancelled ||
                            transfer.status == AttachmentTransferStatus.failed
                        ? '重新下载'
                        : '下载',
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
  }

  String _downloadLabel() {
    final progress = transfer.progress;
    if (progress == null) return '下载中';
    return '下载 ${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }
}
