import 'package:flutter/foundation.dart';

import '../../../../core/services/file/file_picker_service.dart';
import '../../../chat_settings/data/models/chat_member.dart';
import '../../data/models/chat_message.dart';

/// 底部消息输入与操作区控制器统一接口契约（ChatComposerController）
///
/// 供主窗口全功能 [ChatController] 与桌面端轻量独立子窗口 [SubWindowChatController] 共同实现，
/// 使得独立与非独立窗口能够 100% 复用同一个完整的 [ChatComposer] 体验与组件树。
abstract class ChatComposerController with ChangeNotifier {
  bool get isOfficialAccount;
  List<Map<String, dynamic>> get officialAccountMenus;
  bool get isMuted;
  bool get isSending;
  ChatMessage? get quoting;

  bool get mentionVisible;
  String get mentionKeyword;
  List<ChatMember> get mentionMembers;
  bool get mentionLoading;
  bool get mentionHasMore;

  void send(String text);
  void cancelQuote();
  void quoteMessage(ChatMessage message);

  void updateMentionInput(String text);
  void dismissMention();
  void updateMentionKeyword(String keyword);
  Future<void> loadMoreMentions();
  String toggleMention(String text, ChatMember member);
  bool isMemberMentioned(ChatMember member, String text);

  Future<bool> hasVoiceRecordingPermission();
  Future<void> startVoiceRecording();
  Future<void> cancelVoiceRecording();
  Future<void> finishVoiceRecording(Duration duration);
  Stream<double> voiceRecordingLevels(Duration interval);

  Future<void> chooseAndSendImages();
  Future<void> takeAndSendPhoto();
  Future<void> chooseAndSendVideo();
  Future<void> chooseAndSendFile();

  Future<void> sendImageBytes(
    Uint8List bytes, {
    String? caption,
    String? fileName,
  });

  Future<void> sendDirectFiles(List<SelectedFile> files, {String? caption});
}
