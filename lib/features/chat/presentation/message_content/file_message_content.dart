import 'package:flutter/material.dart';

import '../../../../core/services/file/attachment_transfer_service.dart';
import '../../data/models/chat_message.dart';
import 'chat_message_presentation.dart';
import 'message_bubble.dart';

class _FileStyle {
  const _FileStyle({
    required this.icon,
    required this.backgroundColor,
    required this.iconColor,
    required this.tag,
  });

  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;
  final String tag;
}

_FileStyle _resolveFileStyle(String name, String suffix) {
  final ext = (suffix.isNotEmpty
          ? suffix
          : (name.contains('.') ? '.${name.split('.').last}' : ''))
      .toLowerCase();
  switch (ext) {
    case '.pdf':
      return const _FileStyle(
        icon: Icons.picture_as_pdf_rounded,
        backgroundColor: Color(0xFFFFEBEE),
        iconColor: Color(0xFFD32F2F),
        tag: 'PDF',
      );
    case '.doc':
    case '.docx':
      return const _FileStyle(
        icon: Icons.description_rounded,
        backgroundColor: Color(0xFFE3F2FD),
        iconColor: Color(0xFF1976D2),
        tag: 'DOC',
      );
    case '.xls':
    case '.xlsx':
    case '.csv':
      return const _FileStyle(
        icon: Icons.table_chart_rounded,
        backgroundColor: Color(0xFFE8F5E9),
        iconColor: Color(0xFF388E3C),
        tag: 'XLS',
      );
    case '.ppt':
    case '.pptx':
      return const _FileStyle(
        icon: Icons.slideshow_rounded,
        backgroundColor: Color(0xFFFBE9E7),
        iconColor: Color(0xFFE64A19),
        tag: 'PPT',
      );
    case '.zip':
    case '.rar':
    case '.7z':
    case '.tar':
    case '.gz':
      return const _FileStyle(
        icon: Icons.folder_zip_rounded,
        backgroundColor: Color(0xFFFFF8E1),
        iconColor: Color(0xFFFFA000),
        tag: 'ZIP',
      );
    case '.mp3':
    case '.wav':
    case '.aac':
    case '.m4a':
    case '.flac':
      return const _FileStyle(
        icon: Icons.audiotrack_rounded,
        backgroundColor: Color(0xFFF3E5F5),
        iconColor: Color(0xFF8E24AA),
        tag: 'AUDIO',
      );
    case '.mp4':
    case '.mov':
    case '.avi':
    case '.mkv':
      return const _FileStyle(
        icon: Icons.video_file_rounded,
        backgroundColor: Color(0xFFE0F7FA),
        iconColor: Color(0xFF0097A7),
        tag: 'VIDEO',
      );
    case '.txt':
    case '.md':
    case '.json':
    case '.dart':
    case '.ts':
    case '.js':
      return const _FileStyle(
        icon: Icons.code_rounded,
        backgroundColor: Color(0xFFECEFF1),
        iconColor: Color(0xFF546E7A),
        tag: 'TXT',
      );
    default:
      final rawTag = ext.startsWith('.') ? ext.substring(1).toUpperCase() : 'FILE';
      return _FileStyle(
        icon: Icons.insert_drive_file_rounded,
        backgroundColor: const Color(0xFFF0F4F8),
        iconColor: const Color(0xFF607D8B),
        tag: rawTag.length > 4 ? rawTag.substring(0, 4) : rawTag,
      );
  }
}

/// 现代化美化文件消息气泡组件：
/// 1. 按文件类型展示专业配色与类型角标
/// 2. 下载进度百分比浮动在文件图标层正上方
/// 3. 去除独立下载按钮，卡片整块点击智能处理下载、取消与打开
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
    final style = _resolveFileStyle(message.fileName, message.fileSuffix);
    final isDownloading = transfer.isDownloading;
    final isReady = transfer.isReady;

    final stateLabel = switch (transfer.status) {
      AttachmentTransferStatus.downloading => _downloadPercentage(),
      AttachmentTransferStatus.completed => '已下载',
      AttachmentTransferStatus.cancelled => '已取消，点击下载',
      AttachmentTransferStatus.failed => '下载失败，点击重试',
      AttachmentTransferStatus.idle =>
        message.state == 'sending'
            ? '发送中'
            : message.state == 'failed'
            ? '发送失败'
            : '点击下载',
    };

    final onTap = switch (transfer.status) {
      AttachmentTransferStatus.downloading => onCancel,
      AttachmentTransferStatus.completed => onOpen,
      _ => message.state == 'sending' ? null : onDownload,
    };

    if (presentation == ChatMessagePresentation.quote) {
      return InkWell(
        onTap: onTap,
        onLongPress: isReady ? onSaveAs : null,
        borderRadius: BorderRadius.circular(6),
        child: Row(
          children: <Widget>[
            _buildFileIcon(style, compact: true),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message.fileName.isEmpty ? '文件' : message.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
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
      child: InkWell(
        onTap: onTap,
        onLongPress: isReady ? onSaveAs : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 240,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              // 文件图标 + 浮动百分比层
              _buildFileIcon(style),
              const SizedBox(width: 12),
              // 文件名与大小、状态
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      message.fileName.isEmpty ? '文件' : message.fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          _formatFileSize(message.fileSize),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.75),
                              ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '·',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.75),
                              ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            stateLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: transfer.status ==
                                              AttachmentTransferStatus.failed ||
                                          message.state == 'failed'
                                      ? Colors.red
                                      : isReady
                                          ? Colors.green
                                          : isDownloading
                                              ? Theme.of(context).colorScheme.primary
                                              : null,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isReady)
                IconButton(
                  icon: const Icon(Icons.save_alt_rounded, size: 18),
                  tooltip: '另存为',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: onSaveAs,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileIcon(_FileStyle style, {bool compact = false}) {
    final width = compact ? 36.0 : 48.0;
    final height = compact ? 42.0 : 54.0;
    final iconSize = compact ? 20.0 : 26.0;
    final isDownloading = transfer.isDownloading;
    final progress = transfer.progress ?? 0.0;
    final percentageText = '${(progress * 100).clamp(0, 100).toInt()}%';

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 底层文件图标背景
          Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: style.backgroundColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: style.iconColor.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  style.icon,
                  size: iconSize,
                  color: style.iconColor,
                ),
                if (!compact && style.tag.isNotEmpty)
                  Text(
                    style.tag,
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.bold,
                      color: style.iconColor,
                      letterSpacing: 0.5,
                      height: 1.1,
                    ),
                  ),
              ],
            ),
          ),
          // 浮动在图标层上的下载进度百分比遮罩
          if (isDownloading)
            Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.square(
                    dimension: compact ? 26 : 34,
                    child: CircularProgressIndicator(
                      value: progress > 0 ? progress : null,
                      color: Colors.white,
                      backgroundColor: Colors.white24,
                      strokeWidth: 2.5,
                    ),
                  ),
                  Text(
                    percentageText,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 8 : 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _downloadPercentage() {
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
