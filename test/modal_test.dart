import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gotoim_flutter/core/widgets/app_modal.dart';

void main() {
  testWidgets('Test all modal diagnostics cases and transitions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return Center(
                child: ElevatedButton(
                  onPressed: () {},
                  child: const Text('Open'),
                ),
              );
            },
          ),
        ),
      ),
    );

    final context = tester.element(find.byType(ElevatedButton));

    for (final trans in ModalTransitionType.values) {
      final opts = AppModalOptions(
        transitionType: trans,
        backdropBlur: 5.0,
      );

      // ── 1. Success, Error, AutoClose ──
      showSuccessModal(
        context: context,
        title: '转账成功',
        message: '¥ 5,000.00 已成功转入对方钱包。',
        options: opts,
      );
      await tester.pumpAndSettle();
      expect(find.text('转账成功'), findsOneWidget);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();

      showErrorModal(
        context: context,
        title: '连接超时',
        message: '无法连接到远程 SignalR 网关',
        options: opts,
      );
      await tester.pumpAndSettle();
      expect(find.text('连接超时'), findsOneWidget);
      await tester.tap(find.text('我知道了'));
      await tester.pumpAndSettle();

      // ── 2. Confirm (Checkbox, Neutral, Destructive) ──
      showModalDialog<void>(
        context: context,
        title: '开启桌面消息通知？',
        content: '开启后将弹出气泡提醒。',
        confirmText: '立即开启',
        cancelText: '暂不开启',
        checkboxText: '记住我的选择，不再提示',
        showCloseButton: true,
        options: opts,
      );
      await tester.pumpAndSettle();
      expect(find.text('开启桌面消息通知？'), findsOneWidget);
      expect(find.text('记住我的选择，不再提示'), findsOneWidget);
      // Toggle checkbox
      await tester.tap(find.text('记住我的选择，不再提示'));
      await tester.pump();
      await tester.tap(find.text('立即开启'));
      await tester.pumpAndSettle();

      // Three buttons
      showModalDialog<void>(
        context: context,
        title: '发现客户端新版本 v2.0',
        content: '更新说明',
        confirmText: '立即升级',
        cancelText: '忽略此版本',
        neutralText: '稍后提醒我',
        showCloseButton: true,
        options: opts,
      );
      await tester.pumpAndSettle();
      expect(find.text('发现客户端新版本 v2.0'), findsOneWidget);
      expect(find.text('稍后提醒我'), findsOneWidget);
      await tester.tap(find.text('稍后提醒我'));
      await tester.pumpAndSettle();

      // Destructive confirm
      showConfirmModal(
        context: context,
        icon: const Icon(Icons.delete_forever_outlined, size: 48, color: Colors.red),
        title: '解散当前群聊？',
        message: '解散后群聊天记录将不可恢复',
        confirmText: '确认解散',
        confirmIcon: const Icon(Icons.delete, size: 18),
        cancelText: '再想想',
        isDestructive: true,
        options: opts,
      );
      await tester.pumpAndSettle();
      expect(find.text('解散当前群聊？'), findsOneWidget);
      await tester.tap(find.text('确认解散'));
      await tester.pumpAndSettle();

      // ── 3. Prompt (Digits only, Multi-line, Password) ──
      showPromptModal(
        context: context,
        title: '输入安全验证码',
        message: '已发送 6 位验证码',
        placeholderText: '6 位数字验证码',
        maxLength: 6,
        prefixIcon: const Icon(Icons.security, size: 20),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        options: opts,
      );
      await tester.pumpAndSettle();
      expect(find.text('输入安全验证码'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      // Multi-line Prompt
      showPromptModal(
        context: context,
        title: '发布群公告',
        message: '公告将展示给所有群成员：',
        placeholderText: '请输入群公告内容...',
        maxLength: 200,
        maxLines: 4,
        minLines: 2,
        options: opts,
      );
      await tester.pumpAndSettle();
      expect(find.text('发布群公告'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '这是测试公告内容');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      // Password Prompt
      showPromptModal(
        context: context,
        title: '请输入账号密码',
        obscureText: true,
        options: opts,
      );
      await tester.pumpAndSettle();
      expect(find.text('请输入账号密码'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      // ── 4. Radio List ──
      showRadioListModal<int>(
        context: context,
        title: '消息云端漫游保存时间',
        initialValue: 30,
        items: const [
          ModalActionItem(title: '7 天', value: 7),
          ModalActionItem(title: '30 天 (推荐)', value: 30),
          ModalActionItem(title: '90 天', value: 90),
        ],
        options: opts,
      );
      await tester.pumpAndSettle();
      expect(find.text('消息云端漫游保存时间'), findsOneWidget);
      await tester.tap(find.text('30 天 (推荐)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      // ── 5. ActionSheet ──
      showActionSheetModal<String>(
        context: context,
        title: '消息操作',
        message: '对选中的消息执行以下操作',
        items: const [
          ModalActionItem(title: '转发给好友', value: 'forward'),
          ModalActionItem(title: '复制内容', value: 'copy'),
          ModalActionItem(title: '撤回此消息', value: 'recall', isDestructive: true),
        ],
        options: opts,
      );
      await tester.pumpAndSettle();
      expect(find.text('消息操作'), findsOneWidget);
      await tester.tap(find.text('撤回此消息'));
      await tester.pumpAndSettle();

      // ── 6. Async onConfirm loading & error ──
      showModalDialog<void>(
        context: context,
        title: '同步云端消息',
        content: '是否从服务器增量同步？',
        confirmText: '开始同步',
        onConfirm: (_) async => true,
        options: opts,
      );
      await tester.pumpAndSettle();
      expect(find.text('同步云端消息'), findsOneWidget);
      await tester.tap(find.text('开始同步'));
      await tester.pumpAndSettle();

      showPromptModal(
        context: context,
        title: '输入邀请码',
        onConfirm: (code) async {
          if (code != '8888') throw Exception('邀请码无效');
          return true;
        },
        options: opts,
      );
      await tester.pumpAndSettle();
      expect(find.text('输入邀请码'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('确定'));
      await tester.pump();
      expect(find.text('Exception: 邀请码无效'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '8888');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
    }
  });
}
