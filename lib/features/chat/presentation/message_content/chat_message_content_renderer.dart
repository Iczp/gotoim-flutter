import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/media/media_preview.dart';
import '../../../../core/services/file/attachment_transfer_service.dart';
import '../../data/models/chat_message.dart';
import 'chat_message_presentation.dart';
import 'contact_card_message_content.dart';
import 'file_message_content.dart';
import 'html_message_content.dart';
import 'history_message_content.dart';
import 'image_message_content.dart';
import 'link_message_content.dart';
import 'location_message_content.dart';
import 'red_envelope_message_content.dart';
import 'text_message_content.dart';
import 'unsupported_message_content.dart';
import 'article_message_content.dart';
import 'video_message_content.dart';
import 'voice_message_content.dart';

/// Shared message-type dispatch used by timeline rows and quote containers.
class ChatMessageContentRenderer extends StatelessWidget {
  const ChatMessageContentRenderer({
    required this.message,
    required this.attachmentState,
    required this.onVoiceOpened,
    required this.onAttachmentDownload,
    required this.onAttachmentCancel,
    required this.onAttachmentOpen,
    required this.onAttachmentSaveAs,
    required this.imageBytes,
    required this.uploadProgress,
    required this.apiBaseUrl,
    required this.mediaItems,
    required this.mediaInitialIndex,
    this.onLinkTap,
    this.onRetry,
    this.maxWidth,
    this.presentation = ChatMessagePresentation.normal,
    super.key,
  });

  final ChatMessage message;
  final AttachmentTransferState attachmentState;
  final Future<void> Function() onVoiceOpened;
  final Future<void> Function() onAttachmentDownload;
  final Future<void> Function() onAttachmentCancel;
  final Future<void> Function() onAttachmentOpen;
  final Future<void> Function() onAttachmentSaveAs;
  final Uint8List? imageBytes;
  final double? uploadProgress;
  final String apiBaseUrl;
  final List<MediaPreviewItem> mediaItems;
  final int mediaInitialIndex;
  final Future<void> Function()? onLinkTap;
  final VoidCallback? onRetry;
  final double? maxWidth;
  final ChatMessagePresentation presentation;

  @override
  Widget build(BuildContext context) => switch (message.messageType) {
    5 => FileMessageContent(
      message: message,
      transfer: attachmentState,
      onDownload: onAttachmentDownload,
      onCancel: onAttachmentCancel,
      onOpen: onAttachmentOpen,
      onSaveAs: onAttachmentSaveAs,
      presentation: presentation,
    ),
    6 => LinkMessageContent(
      message: message,
      apiBaseUrl: apiBaseUrl,
      onTap: onLinkTap,
      presentation: presentation,
    ),
    7 => LocationMessageContent(message: message, presentation: presentation),
    8 => ContactCardMessageContent(
      message: message,
      presentation: presentation,
    ),
    9 => RedEnvelopeMessageContent(
      message: message,
      presentation: presentation,
    ),
    10 => HtmlMessageContent(message: message, presentation: presentation),
    11 => ArticleMessageContent(message: message, presentation: presentation),
    12 => HistoryMessageContent(message: message, presentation: presentation),
    3 => VoiceMessageContent(
      message: message,
      onOpened: onVoiceOpened,
      presentation: presentation,
      maxWidth: maxWidth,
      onRetry: onRetry,
    ),
    2 => ImageMessageContent(
      message: message,
      bytes: imageBytes,
      apiBaseUrl: apiBaseUrl,
      progress: uploadProgress,
      mediaItems: mediaItems,
      initialIndex: mediaInitialIndex,
      presentation: presentation,
    ),
    4 => VideoMessageContent(
      message: message,
      apiBaseUrl: apiBaseUrl,
      progress: uploadProgress,
      mediaItems: mediaItems,
      initialIndex: mediaInitialIndex,
      presentation: presentation,
    ),
    0 => TextMessageContent(
      message: message,
      presentation: presentation,
      maxWidth: maxWidth,
      onRetry: onRetry,
    ),
    _ => UnsupportedMessageContent(
      message: message,
      presentation: presentation,
    ),
  };
}
