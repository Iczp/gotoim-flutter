import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/native/native.dart';
import '../../../../core/security/widgets/report_dialog.dart';
import '../../../../core/widgets/desktop_dialog.dart';

/// 呼叫电话/复制号码的弹窗（桌面端居中模态对话框，移动端底部弹窗）
void showPhoneActionSheet(BuildContext context, String phone) {
  final isDesktop = (!kIsWeb &&
          (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) ||
      MediaQuery.sizeOf(context).width >= 720;

  if (isDesktop) {
    showDesktopModalDialog<void>(
      context: context,
      title: '联系方式',
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.phone_rounded, color: Color(0xFF07C160)),
            title: Text(
              '呼叫 $phone',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            onTap: () {
              Navigator.pop(context);
              Native.system.makePhoneCall(phone);
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.copy_rounded),
            title: const Text('复制号码'),
            onTap: () {
              Navigator.pop(context);
              Clipboard.setData(ClipboardData(text: phone));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('电话号码已复制到剪贴板'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
    );
    return;
  }

  showModalBottomSheet<void>(
    context: context,
    isDismissible: true,
    enableDrag: true,
    backgroundColor: Colors.transparent,
    builder:
        (sheetContext) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ListTile(
                  title: Center(
                    child: Text(
                      '呼叫 $phone',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Native.system.makePhoneCall(phone);
                  },
                ),
                const Divider(height: 0.5),
                ListTile(
                  title: const Center(
                    child: Text('复制号码', style: TextStyle(fontSize: 15)),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Clipboard.setData(ClipboardData(text: phone));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('电话号码已复制到剪贴板'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
                const Divider(height: 0.5),
                ListTile(
                  title: const Center(
                    child: Text(
                      '取消',
                      style: TextStyle(fontSize: 15, color: Colors.grey),
                    ),
                  ),
                  onTap: () => Navigator.pop(sheetContext),
                ),
              ],
            ),
          ),
        ),
  );
}

/// 音视频通话选择的弹窗（桌面端居中模态对话框，移动端底部弹窗）
void showMediaCallActionSheet(BuildContext context, String displayName) {
  final isDesktop = (!kIsWeb &&
          (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) ||
      MediaQuery.sizeOf(context).width >= 720;

  if (isDesktop) {
    showDesktopModalDialog<void>(
      context: context,
      title: '发起通话',
      subtitle: displayName,
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(
              Icons.phone_rounded,
              color: Color(0xFF07C160),
            ),
            title: const Text('语音通话'),
            subtitle: Text('与 $displayName 进行实时语音沟通'),
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('语音通话功能接入中')),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(
              Icons.videocam_rounded,
              color: Color(0xFF07C160),
            ),
            title: const Text('视频通话'),
            subtitle: Text('与 $displayName 进行面对面高清视频'),
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('视频通话功能接入中')),
              );
            },
          ),
        ],
      ),
    );
    return;
  }

  showModalBottomSheet<void>(
    context: context,
    isDismissible: true,
    enableDrag: true,
    backgroundColor: Colors.transparent,
    builder:
        (sheetContext) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ListTile(
                  leading: const Icon(
                    Icons.phone_rounded,
                    color: Color(0xFF07C160),
                  ),
                  title: const Text('语音通话'),
                  subtitle: Text('与 $displayName 进行实时语音沟通'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('语音通话功能接入中')),
                    );
                  },
                ),
                const Divider(height: 0.5),
                ListTile(
                  leading: const Icon(
                    Icons.videocam_rounded,
                    color: Color(0xFF07C160),
                  ),
                  title: const Text('视频通话'),
                  subtitle: Text('与 $displayName 进行面对面高清视频'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('视频通话功能接入中')),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
  );
}

/// 更多资料设置（举报、拉黑、设置备注）弹窗（桌面端居中模态对话框，移动端底部弹窗）
void showMoreProfileActionSheet(
  BuildContext context, {
  required String userId,
  required String userName,
}) {
  final isDesktop = (!kIsWeb &&
          (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) ||
      MediaQuery.sizeOf(context).width >= 720;

  if (isDesktop) {
    showDesktopModalDialog<void>(
      context: context,
      title: '更多设置',
      subtitle: userName,
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_note_rounded),
            title: const Text('设置备注和标签'),
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已进入备注与标签设置'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.block_rounded, color: Colors.orange),
            title: const Text('加入黑名单'),
            subtitle: const Text('加入黑名单后将不再接收对方发来的任何消息'),
            onTap: () {
              Navigator.pop(context);
              showDialog<void>(
                context: context,
                builder:
                    (ctx) => AlertDialog(
                      title: const Text('加入黑名单'),
                      content: Text(
                        '确定要将 $userName 加入黑名单吗？加入后将不再接收对方消息。',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('取消'),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('已将 $userName 加入黑名单')),
                            );
                          },
                          child: const Text(
                            '确定拉黑',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(
              Icons.report_problem_outlined,
              color: Colors.redAccent,
            ),
            title: const Text(
              '投诉 / 举报该用户',
              style: TextStyle(color: Colors.redAccent),
            ),
            subtitle: const Text('举报涉嫌违规、骚扰、涉黄、诈骗等不良行为'),
            onTap: () {
              Navigator.pop(context);
              ReportDialog.showForUser(
                context,
                userId: userId,
                userName: userName,
              );
            },
          ),
        ],
      ),
    );
    return;
  }

  showModalBottomSheet<void>(
    context: context,
    isDismissible: true,
    enableDrag: true,
    backgroundColor: Colors.transparent,
    builder:
        (sheetContext) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.edit_note_rounded),
                  title: const Text('设置备注和标签'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已进入备注与标签设置'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
                const Divider(height: 0.5),
                ListTile(
                  leading: const Icon(Icons.block_rounded, color: Colors.orange),
                  title: const Text('加入黑名单'),
                  subtitle: const Text('加入黑名单后将不再接收对方发来的任何消息'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    showDialog<void>(
                      context: context,
                      builder:
                          (ctx) => AlertDialog(
                            title: const Text('加入黑名单'),
                            content: Text('确定要将 $userName 加入黑名单吗？加入后将不再接收对方消息。'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('取消'),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('已将 $userName 加入黑名单')),
                                  );
                                },
                                child: const Text(
                                  '确定拉黑',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                    );
                  },
                ),
                const Divider(height: 0.5),
                ListTile(
                  leading: const Icon(
                    Icons.report_problem_outlined,
                    color: Colors.redAccent,
                  ),
                  title: const Text(
                    '投诉 / 举报该用户',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                  subtitle: const Text('举报涉嫌违规、骚扰、涉黄、诈骗等不良行为'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    ReportDialog.showForUser(
                      context,
                      userId: userId,
                      userName: userName,
                    );
                  },
                ),
                const Divider(height: 0.5),
                ListTile(
                  title: const Center(
                    child: Text(
                      '取消',
                      style: TextStyle(fontSize: 15, color: Colors.grey),
                    ),
                  ),
                  onTap: () => Navigator.pop(sheetContext),
                ),
              ],
            ),
          ),
        ),
  );
}

