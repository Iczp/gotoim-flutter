import 'package:flutter/material.dart';

import '../../../core/ui/adaptive_page/adaptive_page.dart';
import '../../../core/ui/adaptive_page/adaptive_page_config.dart';
import '../../../core/ui/adaptive_page/adaptive_page_presentation.dart';
import '../data/models/profile_subject.dart';
import 'profile_detail_page.dart';
import 'profile_sheet.dart';

export '../data/models/profile_subject.dart';
export 'profile_detail_page.dart';
export 'profile_sheet.dart';
export 'widgets/profile_action_sheets.dart';
export 'widgets/profile_gender_badge.dart';
export 'widgets/profile_media_thumbnails.dart';

/// 以半屏轻量资料卡方式自适应弹出（手机端半屏，宽屏/桌面端展示全屏或侧栏）
Future<void> openProfilePage(
  BuildContext context, {
  required ProfileSubject subject,
  VoidCallback? onSendMessage,
}) async {
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
