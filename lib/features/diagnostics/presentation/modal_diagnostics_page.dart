import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/app_modal.dart';

class ModalDiagnosticsPage extends StatefulWidget {
  const ModalDiagnosticsPage({super.key});

  @override
  State<ModalDiagnosticsPage> createState() => _ModalDiagnosticsPageState();
}

class _ModalDiagnosticsPageState extends State<ModalDiagnosticsPage> {
  String _lastResult = '未执行任何弹窗';
  double _borderRadius = 20.0;
  double _backdropBlur = 0.0;
  ModalTransitionType _transitionType = ModalTransitionType.material3;
  bool _barrierDismissible = true;
  bool _vibrate = true;
  bool _playSound = false;

  AppModalOptions get _currentOptions => AppModalOptions(
        borderRadius: _borderRadius,
        backdropBlur: _backdropBlur,
        transitionType: _transitionType,
        barrierDismissible: _barrierDismissible,
        vibrate: _vibrate,
        playSound: _playSound,
      );

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(
        body: Center(child: Text('开发诊断仅在 Debug 模式可用。')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Modal 对话框全功能诊断')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '验证统一 showModal 对话框体系：丰富参数、动画与毛玻璃、三按钮结构、勾选框、单选列表、富文本、表单校验与异步拦截。',
          ),
          const SizedBox(height: 12),

          // ── 全局选项配置 ──
          _Section(
            title: '全局容器与动效配置 (AppModalOptions)',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    Text('圆角半径: ${_borderRadius.toStringAsFixed(0)}'),
                    Expanded(
                      child: Slider(
                        value: _borderRadius,
                        min: 4,
                        max: 32,
                        divisions: 14,
                        label: _borderRadius.toStringAsFixed(0),
                        onChanged: (v) => setState(() => _borderRadius = v),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Row(
                  children: [
                    Text('毛玻璃模糊度: ${_backdropBlur.toStringAsFixed(1)}'),
                    Expanded(
                      child: Slider(
                        value: _backdropBlur,
                        min: 0,
                        max: 12,
                        divisions: 12,
                        label: _backdropBlur.toStringAsFixed(1),
                        onChanged: (v) => setState(() => _backdropBlur = v),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Text('进场过渡动画：'),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButton<ModalTransitionType>(
                        value: _transitionType,
                        isExpanded: true,
                        isDense: true,
                        items: const [
                          DropdownMenuItem(
                            value: ModalTransitionType.material3,
                            child: Text('Material 3 (缩放渐显)'),
                          ),
                          DropdownMenuItem(
                            value: ModalTransitionType.scale,
                            child: Text('Center Scale (中心放大)'),
                          ),
                          DropdownMenuItem(
                            value: ModalTransitionType.fade,
                            child: Text('Fade (淡入淡出)'),
                          ),
                          DropdownMenuItem(
                            value: ModalTransitionType.slideFromBottom,
                            child: Text('Slide Bottom (底部滑入)'),
                          ),
                          DropdownMenuItem(
                            value: ModalTransitionType.slideFromTop,
                            child: Text('Slide Top (顶部滑入)'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _transitionType = v);
                        },
                      ),
                    ),
                  ],
                ),
              ),

              SwitchListTile(
                value: _barrierDismissible,
                onChanged: (v) => setState(() => _barrierDismissible = v),
                title: const Text('点击遮罩允许关闭 (barrierDismissible)'),
                dense: true,
              ),
              SwitchListTile(
                value: _vibrate,
                onChanged: (v) => setState(() => _vibrate = v),
                title: const Text('弹出时触觉振动 (vibrate)'),
                dense: true,
              ),
              SwitchListTile(
                value: _playSound,
                onChanged: (v) => setState(() => _playSound = v),
                title: const Text('弹出时播放声音 (playSound)'),
                dense: true,
              ),
            ],
          ),

          // ── 1. 语义化状态弹窗 ──
          _Section(
            title: '1. 语义化快捷弹窗 (Success / Error / Alert)',
            children: [
              ListTile(
                leading: const Icon(Icons.check_circle_outline, color: Colors.green),
                title: const Text('成功提示 (showSuccessModal)'),
                subtitle: const Text('绿色对勾图标，支持自动倒计时关闭'),
                trailing: SizedBox(
                  width: 72,
                  child: FilledButton.tonal(
                    onPressed: () async {
                      await showSuccessModal(
                        context: context,
                        title: '转账成功',
                        message: '¥ 5,000.00 已成功转入对方钱包。',
                        options: _currentOptions,
                      );
                      setState(() => _lastResult = '关闭了成功提示弹窗');
                    },
                    child: const Text('测试'),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.error_outline, color: Colors.red),
                title: const Text('错误提示 (showErrorModal)'),
                subtitle: const Text('红色警示图标与震动反馈'),
                trailing: SizedBox(
                  width: 72,
                  child: FilledButton.tonal(
                    onPressed: () async {
                      await showErrorModal(
                        context: context,
                        title: '连接超时',
                        message: '无法连接到远程 SignalR 网关 (Error 504)，请检查网络配置。',
                        options: _currentOptions,
                      );
                      setState(() => _lastResult = '关闭了错误提示弹窗');
                    },
                    child: const Text('测试'),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.timer_outlined, color: Colors.teal),
                title: const Text('自动定时关闭 (autoCloseDuration: 2.5s)'),
                subtitle: const Text('无需用户点击，2.5 秒后自动消失'),
                trailing: SizedBox(
                  width: 72,
                  child: FilledButton.tonal(
                    onPressed: () async {
                      await showSuccessModal(
                        context: context,
                        title: '文件已同步',
                        message: '本提示将在 2.5 秒后自动关闭...',
                        autoCloseDuration: const Duration(milliseconds: 2500),
                        options: _currentOptions,
                      );
                      setState(() => _lastResult = '自动定时关闭弹窗已结束');
                    },
                    child: const Text('测试'),
                  ),
                ),
              ),
            ],
          ),

          // ── 2. Confirm 确认框（含高级选项） ──
          _Section(
            title: '2. Confirm 确认框 (三按钮 / 勾选框 / 右上角关闭)',
            children: [
              ListTile(
                leading: const Icon(Icons.rule_outlined, color: Colors.indigo),
                title: const Text('带“不再提醒”勾选框与右上角关闭 (X)'),
                subtitle: const Text('返回确认结果与勾选框布尔值'),
                trailing: SizedBox(
                  width: 72,
                  child: FilledButton.tonal(
                    onPressed: () async {
                      final result = await showModalDialog<void>(
                        context: context,
                        title: '开启桌面消息通知？',
                        content: '开启后，当有新群聊或私聊消息时将在右下角弹出气泡提醒。',
                        confirmText: '立即开启',
                        cancelText: '暂不开启',
                        checkboxText: '记住我的选择，不再提示',
                        showCloseButton: true,
                        options: _currentOptions,
                      );
                      setState(() => _lastResult =
                          '结果: confirmed=${result.confirmed}, checkbox=${result.checkboxValue}');
                    },
                    child: const Text('测试'),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.more_horiz, color: Colors.blue),
                title: const Text('三按钮结构 (稍后提醒 / 取消 / 立即更新)'),
                subtitle: const Text('含中立态 neutralButton，触发 isNeutral 状态'),
                trailing: SizedBox(
                  width: 72,
                  child: FilledButton.tonal(
                    onPressed: () async {
                      final result = await showModalDialog<void>(
                        context: context,
                        title: '发现客户端新版本 v2.0',
                        content: '1. 重构 Drift 本地数据库\n2. 优化 SignalR 双向长连接\n3. 新增开发诊断中心',
                        confirmText: '立即升级',
                        cancelText: '忽略此版本',
                        neutralText: '稍后提醒我',
                        showCloseButton: true,
                        options: _currentOptions,
                      );
                      String action = '取消';
                      if (result.isConfirmed) action = '立即升级';
                      if (result.isNeutral) action = '稍后提醒我';
                      setState(() => _lastResult = '三按钮结果: $action');
                    },
                    child: const Text('测试'),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever_outlined, color: Colors.red),
                title: const Text('危险/破坏性确认 (isDestructive)'),
                subtitle: const Text('红色高亮警示 + 自定义图标'),
                trailing: SizedBox(
                  width: 72,
                  child: FilledButton.tonal(
                    onPressed: () async {
                      final confirmed = await showConfirmModal(
                        context: context,
                        icon: const Icon(Icons.delete_forever_outlined, size: 48, color: Colors.red),
                        title: '解散当前群聊？',
                        message: '解散后将清空所有群成员，群聊天记录将不可恢复，是否继续？',
                        confirmText: '确认解散',
                        confirmIcon: const Icon(Icons.delete, size: 18),
                        cancelText: '再想想',
                        isDestructive: true,
                        options: _currentOptions,
                      );
                      setState(() => _lastResult = '解散群聊结果: $confirmed');
                    },
                    child: const Text('测试'),
                  ),
                ),
              ),
            ],
          ),

          // ── 3. Prompt 输入框弹窗 ──
          _Section(
            title: '3. Prompt 输入框 (前缀/后缀图标 / 正则过滤 / 校验)',
            children: [
              ListTile(
                leading: const Icon(Icons.pin_outlined, color: Colors.teal),
                title: const Text('纯数字验证码输入 (inputFormatters)'),
                subtitle: const Text('仅允许输入 6 位数字，带安全前缀图标'),
                trailing: SizedBox(
                  width: 72,
                  child: FilledButton.tonal(
                    onPressed: () async {
                      final text = await showPromptModal(
                        context: context,
                        title: '输入安全验证码',
                        message: '已发送 6 位验证码至您的绑定手机 138****0000：',
                        placeholderText: '6 位数字验证码',
                        maxLength: 6,
                        prefixIcon: const Icon(Icons.security, size: 20),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        validator: (val) {
                          if (val == null || val.length != 6) return '请输入完整的 6 位数字验证码';
                          return null;
                        },
                        options: _currentOptions,
                      );
                      setState(() => _lastResult = '验证码输入结果: ${text != null ? "「$text」" : "已取消"}');
                    },
                    child: const Text('测试'),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.notes_outlined, color: Colors.teal),
                title: const Text('多行长文本输入（如群公告）'),
                subtitle: const Text('maxLines: 4, minLines: 2'),
                trailing: SizedBox(
                  width: 72,
                  child: FilledButton.tonal(
                    onPressed: () async {
                      final text = await showPromptModal(
                        context: context,
                        title: '发布群公告',
                        message: '公告将展示给所有群成员：',
                        placeholderText: '请输入群公告内容...',
                        maxLength: 200,
                        maxLines: 4,
                        minLines: 2,
                        options: _currentOptions,
                      );
                      setState(() => _lastResult = '多行输入结果: ${text != null ? "「$text」" : "已取消"}');
                    },
                    child: const Text('测试'),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.lock_outline, color: Colors.teal),
                title: const Text('密码输入框 (obscureText)'),
                subtitle: const Text('隐藏字符 + 密码锁图标'),
                trailing: SizedBox(
                  width: 72,
                  child: FilledButton.tonal(
                    onPressed: () async {
                      final text = await showPromptModal(
                        context: context,
                        title: '请输入账号密码',
                        placeholderText: '请输入密码进行敏感操作确认',
                        obscureText: true,
                        prefixIcon: const Icon(Icons.lock_outline, size: 20),
                        options: _currentOptions,
                      );
                      setState(() => _lastResult = '密码输入: ${text != null ? "已输入(${text.length}位)" : "已取消"}');
                    },
                    child: const Text('测试'),
                  ),
                ),
              ),
            ],
          ),

          // ── 4. Radio List 单选列表 ──
          _Section(
            title: '4. 单选列表弹窗 (showRadioListModal)',
            children: [
              ListTile(
                leading: const Icon(Icons.radio_button_checked, color: Colors.deepPurple),
                title: const Text('选择消息漫游时长'),
                subtitle: const Text('单选 RadioGroup，支持默认选中值与图标'),
                trailing: SizedBox(
                  width: 72,
                  child: FilledButton.tonal(
                    onPressed: () async {
                      final selected = await showRadioListModal<int>(
                        context: context,
                        title: '消息云端漫游保存时间',
                        message: '超时后的历史消息将从云端自动清除：',
                        initialValue: 30,
                        items: const [
                          ModalActionItem(title: '7 天', subtitle: '适合轻量使用', value: 7),
                          ModalActionItem(title: '30 天 (推荐)', subtitle: '标准团队协同', value: 30),
                          ModalActionItem(title: '90 天', subtitle: '较长历史留存', value: 90),
                          ModalActionItem(title: '永久保留', subtitle: '需要企业专业版', value: 3650),
                        ],
                        options: _currentOptions,
                      );
                      setState(() => _lastResult = '单选结果: ${selected != null ? "$selected 天" : "已取消"}');
                    },
                    child: const Text('测试'),
                  ),
                ),
              ),
            ],
          ),

          // ── 5. ActionSheet 选项列表 ──
          _Section(
            title: '5. ActionSheet 选项列表 (showActionSheetModal)',
            children: [
              ListTile(
                leading: const Icon(Icons.menu_open_outlined, color: Colors.deepPurple),
                title: const Text('多选项操作菜单'),
                subtitle: const Text('支持图标、副标题、破坏性项与禁用项'),
                trailing: SizedBox(
                  width: 72,
                  child: FilledButton.tonal(
                    onPressed: () async {
                      final selected = await showActionSheetModal<String>(
                        context: context,
                        title: '消息操作',
                        message: '对选中的消息执行以下操作',
                        items: const [
                          ModalActionItem(
                            title: '转发给好友',
                            subtitle: '发送给最近联系人或群聊',
                            icon: Icon(Icons.send_outlined),
                            value: 'forward',
                          ),
                          ModalActionItem(
                            title: '复制内容',
                            icon: Icon(Icons.copy_outlined),
                            value: 'copy',
                          ),
                          ModalActionItem(
                            title: '收藏到知识库',
                            icon: Icon(Icons.bookmark_outline),
                            value: 'bookmark',
                          ),
                          ModalActionItem(
                            title: '撤回此消息',
                            subtitle: '仅支持 2 分钟内发送的消息',
                            icon: Icon(Icons.undo_outlined, color: Colors.red),
                            value: 'recall',
                            isDestructive: true,
                          ),
                        ],
                        options: _currentOptions,
                      );
                      setState(() => _lastResult = 'ActionSheet 选中项: ${selected ?? "取消选择"}');
                    },
                    child: const Text('测试'),
                  ),
                ),
              ),
            ],
          ),

          // ── 6. 异步操作与 Loading 拦截 ──
          _Section(
            title: '6. 异步处理与拦截 (onConfirm)',
            children: [
              ListTile(
                leading: const Icon(Icons.hourglass_top_outlined, color: Colors.orange),
                title: const Text('带 Loading 的异步网络提交'),
                subtitle: const Text('点击确认后显示旋转指示器，耗时 1.5s 后自动关闭'),
                trailing: SizedBox(
                  width: 72,
                  child: FilledButton.tonal(
                    onPressed: () async {
                      final result = await showModalDialog<void>(
                        context: context,
                        title: '同步云端消息',
                        content: '是否从服务器增量同步最近 7 天的离线记录？',
                        confirmText: '开始同步',
                        onConfirm: (val) async {
                          await Future.delayed(const Duration(milliseconds: 1500));
                          return true; // 返回 true 允许关闭
                        },
                        options: _currentOptions,
                      );
                      setState(() => _lastResult = '异步同步结果: confirmed=${result.confirmed}');
                    },
                    child: const Text('测试'),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.cancel_presentation_outlined, color: Colors.orange),
                title: const Text('异步校验失败拦截关闭'),
                subtitle: const Text('模拟服务器校验失败并在弹窗内显示错误信息'),
                trailing: SizedBox(
                  width: 72,
                  child: FilledButton.tonal(
                    onPressed: () async {
                      final result = await showPromptModal(
                        context: context,
                        title: '输入邀请码',
                        placeholderText: '请输入 8888 才能通过',
                        onConfirm: (code) async {
                          await Future.delayed(const Duration(milliseconds: 800));
                          if (code != '8888') {
                            throw Exception('邀请码无效或已被使用，请重新输入');
                          }
                          return true;
                        },
                        options: _currentOptions,
                      );
                      setState(() => _lastResult = '邀请码结果: $result');
                    },
                    child: const Text('测试'),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('执行结果：\n$_lastResult'),
          ),
          const SizedBox(height: 16),
          const Text(
            '平台支持：Android ✓  iOS/iPad ✓  Windows ✓  macOS ✓  Linux ✓  Web ✓',
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: Theme.of(context).colorScheme.primary),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Column(children: children),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}
