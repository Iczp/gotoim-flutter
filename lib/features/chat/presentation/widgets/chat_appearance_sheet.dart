import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/theme/chat_appearance_controller.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../chat_settings/application/chat_settings_controller.dart';
import '../../../session/application/session_list_controller.dart';

/// 聊天功能区内的快捷外观浮窗。
///
/// 背景属于当前会话并保存到服务端；其余玻璃与尺寸参数属于本机外观偏好，
/// 与“外观与主题”设置页共用同一个持久化 Provider。
class ChatAppearanceSheet extends ConsumerStatefulWidget {
  const ChatAppearanceSheet({
    required this.ownerId,
    required this.sessionUnitId,
    required this.onBackgroundChanged,
    super.key,
  });

  final int ownerId;
  final String sessionUnitId;
  final Future<void> Function() onBackgroundChanged;

  @override
  ConsumerState<ChatAppearanceSheet> createState() =>
      _ChatAppearanceSheetState();
}

class _ChatAppearanceSheetState extends ConsumerState<ChatAppearanceSheet> {
  late final ChatSettingsController _settingsController;

  @override
  void initState() {
    super.initState();
    _settingsController = ChatSettingsController(
      ref.read(chatSettingsRepositoryProvider),
      ref.read(sessionRepositoryProvider),
      ownerId: widget.ownerId,
      sessionUnitId: widget.sessionUnitId,
    )..initialize();
  }

  @override
  void dispose() {
    _settingsController.dispose();
    super.dispose();
  }

  Future<void> _pickBackground() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) return;
    try {
      await _settingsController.setBackgroundImage(
        MultipartUploadFile(
          name: image.name,
          length: await image.length(),
          openRead: image.openRead,
        ),
      );
      await widget.onBackgroundChanged();
      if (mounted) showToast('聊天背景已设置', type: ToastType.success);
    } catch (error) {
      if (mounted) showToast('设置背景失败：$error', type: ToastType.error);
    }
  }

  Future<void> _clearBackground() async {
    try {
      await _settingsController.clearBackgroundImage();
      await widget.onBackgroundChanged();
      if (mounted) showToast('聊天背景已取消', type: ToastType.success);
    } catch (error) {
      if (mounted) showToast('取消背景失败：$error', type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final appearance = ref.watch(chatAppearanceProvider);
    final appearanceController = ref.read(chatAppearanceProvider.notifier);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: .5),
          width: .33,
        ),
      ),
      child: AnimatedBuilder(
        animation: _settingsController,
        builder:
            (_, _) => Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.wallpaper_rounded),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '聊天背景与外观',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: appearanceController.reset,
                        child: const Text('恢复默认'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                    children: <Widget>[
                      Text('当前会话背景', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 10),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed:
                                  _settingsController.updating
                                      ? null
                                      : _pickBackground,
                              icon: const Icon(Icons.photo_library_outlined),
                              label: const Text('从相册选择'),
                            ),
                          ),
                          if ((_settingsController.backgroundImage ?? '')
                              .isNotEmpty) ...<Widget>[
                            const SizedBox(width: 10),
                            OutlinedButton(
                              onPressed:
                                  _settingsController.updating
                                      ? null
                                      : _clearBackground,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: colorScheme.error,
                              ),
                              child: const Text('取消背景'),
                            ),
                          ],
                        ],
                      ),
                      if (_settingsController.updating)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: LinearProgressIndicator(),
                        ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Divider(),
                      ),
                      Text('毛玻璃与消息样式', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        '调整后立即应用，并保存在本机。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      _AppearanceSlider(
                        label: '模糊强度',
                        value: tokens.chatGlassBlurSigma,
                        min: 0,
                        max: 24,
                        divisions: 24,
                        onChanged:
                            (value) => appearanceController.update(
                              appearance.copyWith(glassBlurSigma: value),
                            ),
                      ),
                      _AppearanceSlider(
                        label: '标题栏透明度',
                        value: tokens.chatTitleGlassOpacity,
                        min: .05,
                        max: .9,
                        divisions: 17,
                        onChanged:
                            (value) => appearanceController.update(
                              appearance.copyWith(titleGlassOpacity: value),
                            ),
                      ),
                      _AppearanceSlider(
                        label: '输入栏与功能区透明度',
                        value: tokens.chatInputGlassOpacity,
                        min: 0,
                        max: .9,
                        divisions: 18,
                        onChanged:
                            (value) => appearanceController.update(
                              appearance.copyWith(inputGlassOpacity: value),
                            ),
                      ),
                      _AppearanceSlider(
                        label: '玻璃边框透明度',
                        value: tokens.chatGlassBorderOpacity,
                        min: .05,
                        max: .8,
                        divisions: 15,
                        onChanged:
                            (value) => appearanceController.update(
                              appearance.copyWith(glassBorderOpacity: value),
                            ),
                      ),
                      _AppearanceSlider(
                        label: '玻璃边框线宽',
                        value: tokens.chatGlassBorderWidth,
                        min: .1,
                        max: 1,
                        divisions: 9,
                        onChanged:
                            (value) => appearanceController.update(
                              appearance.copyWith(glassBorderWidth: value),
                            ),
                      ),
                      _AppearanceSlider(
                        label: '消息气泡透明度',
                        value: tokens.chatBubbleOpacity,
                        min: .3,
                        max: 1,
                        divisions: 14,
                        onChanged:
                            (value) => appearanceController.update(
                              appearance.copyWith(bubbleOpacity: value),
                            ),
                      ),
                      _AppearanceSlider(
                        label: '工具栏高度',
                        value: tokens.chatComposerHeight,
                        min: 48,
                        max: 72,
                        divisions: 12,
                        onChanged:
                            (value) => appearanceController.update(
                              appearance.copyWith(composerHeight: value),
                            ),
                      ),
                      _AppearanceSlider(
                        label: '消息与头像最小尺寸',
                        value: tokens.chatMessageMinHeight,
                        min: 36,
                        max: 56,
                        divisions: 10,
                        onChanged:
                            (value) => appearanceController.update(
                              appearance.copyWith(messageMinHeight: value),
                            ),
                      ),
                      _AppearanceSlider(
                        label: '消息区安全留白',
                        value: tokens.chatGlassContentPadding,
                        min: 0,
                        max: 32,
                        divisions: 16,
                        onChanged:
                            (value) => appearanceController.update(
                              appearance.copyWith(glassContentPadding: value),
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
      ),
    );
  }
}

class _AppearanceSlider extends StatelessWidget {
  const _AppearanceSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(label),
            Text(value.toStringAsFixed(value < 2 ? 2 : 0)),
          ],
        ),
        Slider(
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          divisions: divisions,
          label: value.toStringAsFixed(value < 2 ? 2 : 0),
          onChanged: onChanged,
        ),
      ],
    ),
  );
}
