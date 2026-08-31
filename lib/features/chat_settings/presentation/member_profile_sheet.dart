import 'package:flutter/material.dart';

import '../../user/presentation/profile_page.dart';
import '../data/models/chat_member.dart';

/// Backward-compatible entry point. Member details now use the unified,
/// AdaptivePage-based formal profile page instead of a dedicated sheet.
Future<void> showMemberProfileSheet(
  BuildContext context,
  ChatMember member, {
  VoidCallback? onSendMessage,
}) => openProfilePage(
  context,
  subject: ProfileSubject.member(member),
  onSendMessage: onSendMessage,
);
