import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/ui/adaptive_page/adaptive_page.dart';
import '../../../core/ui/adaptive_page/adaptive_page_config.dart';
import '../../../core/ui/adaptive_page/adaptive_page_presentation.dart';
import '../data/models/profile_subject.dart';
import 'desktop_profile_card_dialog.dart';
import 'profile_detail_page.dart';
import 'profile_sheet.dart';

export '../data/models/profile_subject.dart';
export 'desktop_profile_card_dialog.dart';
export 'profile_detail_page.dart';
export 'profile_sheet.dart';
export 'widgets/profile_action_sheets.dart';
export 'widgets/profile_gender_badge.dart';
export 'widgets/profile_media_thumbnails.dart';

/// 以半屏轻量资料卡方式自适应弹出（手机端半屏，宽屏/桌面端展示桌面规范资料卡弹窗）
Future<void> openProfilePage(
  BuildContext context, {
  required ProfileSubject subject,
  VoidCallback? onSendMessage,
}) async {
  final isDesktop = (!kIsWeb &&
          (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) ||
      MediaQuery.sizeOf(context).width >= 720;

  if (isDesktop) {
    return DesktopProfileCardDialog.show(
      context,
      subject: subject,
      onSendMessage: onSendMessage,
    );
  }

  await AdaptivePage.open<void>(
    context,
    config: AdaptivePageConfig(
      title: titleForProfileKind(subject.kind),
      sheetSizingMode: AdaptiveSheetSizingMode.draggable,
      initialChildSize: .58,
      minChildSize: .42,
      maxChildSize: .96,
      fullPageMinWidth: 720,
    ),
    builder: (context, controller) {
      if (controller.presentation == AdaptivePagePresentation.full) {
        return ProfileDetailPage(
          subject: subject,
          onSendMessage: onSendMessage,
        );
      }
      return ProfileSheet(
        subject: subject,
        adaptiveController: controller,
        onSendMessage: onSendMessage,
      );
    },
  );
}
