import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/native/native.dart';

/// 呼叫电话/复制号码的底部弹窗
void showPhoneActionSheet(BuildContext context, String phone) {
  showModalBottomSheet<void>(
    context: context,
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

/// 音视频通话选择的底部弹窗
void showMediaCallActionSheet(BuildContext context, String displayName) {
  showModalBottomSheet<void>(
    context: context,
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
