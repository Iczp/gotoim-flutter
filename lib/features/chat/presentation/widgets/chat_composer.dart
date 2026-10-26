import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/clipboard_service.dart';
import '../../../../core/services/screen_capture_service.dart';
import '../../../../core/theme/app_theme_tokens.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/half_page_sheet.dart';
import '../../data/models/chat_message.dart';
import 'chat_composer_controller.dart';
import 'chat_function_panel.dart';
import 'chat_mention_panel.dart';
import 'chat_public_account_menu.dart';
import 'chat_quote_preview.dart';
import 'chat_recording_panel.dart';
import 'clipboard_files_confirm_dialog.dart';
import 'clipboard_image_confirm_dialog.dart';

/// 底部消息输入与操作区组件（ChatComposer）
///
/// 核心职责：
/// 1. 文本输入：多行自适应输入框，支持 Enter 换行与禁言状态禁用；
/// 2. 语音输入切换：长按录音、声波振幅实时采样、上滑取消与超时自动发送；
/// 3. 表情与附件功能面板切换：软键盘与功能托盘平滑高度无缝衔接；
/// 4. 引用回复：顶部浮层展示被引用消息，支持一键移除引用；
/// 5. 群聊 `@` 艾特触发：输入 `@` 字符自动唤起成员选择浮层。
class ChatComposer extends ConsumerStatefulWidget {
  const ChatComposer({
    required this.controller,
    required this.input,
    required this.quoteContentBuilder,
    this.onOpenAppearancePanel,
    this.useGlass = false,
    this.hasBackground = false,
    this.isDesktop = false,
    super.key,
  });

  /// 聊天状态控制器
  final ChatComposerController controller;

  /// 输入框文本控制器
  final TextEditingController input;

  /// 引用消息内容构建器
  final Widget Function(ChatMessage quote) quoteContentBuilder;
  final Future<void> Function()? onOpenAppearancePanel;
  final bool useGlass;
  final bool hasBackground;
  final bool isDesktop;

  @override
  ConsumerState<ChatComposer> createState() => ChatComposerState();
}

class ChatComposerState extends ConsumerState<ChatComposer>
    with WidgetsBindingObserver {
  final FocusNode _focusNode = FocusNode();
  final PageController _pageController = PageController();
  bool _showFunctions = false;
  bool _desktopCapturePending = false;
  bool _isSwitchingToKeyboard = false;
  bool _voiceMode = false;
  bool _startingRecording = false;
  bool _recording = false;
  bool _cancelRecording = false;
  bool _pointerReleased = false;
  bool _finishingRecording = false;
  StreamSubscription<double>? _levelSubscription;
  Timer? _durationTimer;
  OverlayEntry? _recordingOverlay;
  final Stopwatch _recordingWatch = Stopwatch();
  Duration _recordingDuration = Duration.zero;
  final List<double> _levelPercentages = List<double>.filled(
    24,
    0,
    growable: true,
  );
  int _amplitudeSampleCount = 0;
  int _page = 0;
  bool _mentionSheetOpen = false;
  bool _menuMode = false;
  String? _lastDockMetrics;
  bool _hideWindowOnScreenshot = true;

  // 微信同款桌面端高度调节与快捷键偏好
  double _desktopComposerHeight = 175.0; // 微信桌面同款初始高度
  static const double _minDesktopComposerHeight = 115.0;
  static const double _maxDesktopComposerHeight = 420.0;
  bool _isDraggingSplitter = false;
  bool _sendOnEnter = true; // 微信默认: Enter 发送，Ctrl+Enter 换行
  final ScrollController _desktopScrollController = ScrollController();

  static const _functions = <ChatFunctionItem>[
    ChatFunctionItem('相册', Icons.photo_outlined),
    ChatFunctionItem('拍摄', Icons.camera_alt_outlined),
    ChatFunctionItem('视频', Icons.videocam_outlined),
    ChatFunctionItem('文件', Icons.insert_drive_file_outlined, enabled: true),
    ChatFunctionItem('设置背景', Icons.wallpaper_rounded, enabled: true),
    ChatFunctionItem('位置', Icons.location_on_outlined),
    ChatFunctionItem('名片', Icons.contact_page_outlined),
    ChatFunctionItem('语音通话', Icons.call_outlined),
    ChatFunctionItem('视频通话', Icons.video_call_outlined),
    ChatFunctionItem('红包', Icons.wallet_giftcard_outlined),
    ChatFunctionItem('收藏', Icons.bookmark_border_rounded),
  ];

  static const _voiceWaveVisualConfig = VoiceWaveVisualConfig(
    inputFloorPercent: 30,
    inputPeakPercent: 80,
  );
  static const _fallbackFunctionTrayHeight = 300.0;
  static const _minValidKeyboardHeight = 180.0;
  double _keyboardTrayHeight = _fallbackFunctionTrayHeight;

  @override
  void initState() {
    super.initState();
    _menuMode = widget.controller.isOfficialAccount;
    WidgetsBinding.instance.addObserver(this);
    _focusNode.addListener(() => _logDockMetrics('focus'));
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _captureKeyboardHeight(),
    );
  }

  void _onMenuItemSelected(PublicAccountMenuItem item) {
    if (item.url != null && item.url!.isNotEmpty) {
      showToast('访问服务：${item.name}', type: ToastType.info);
    } else {
      widget.controller.send(item.key ?? item.name);
    }
  }

  @override
  void didChangeMetrics() {
    _captureKeyboardHeight();
  }

  void _captureKeyboardHeight() {
    if (!mounted) return;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final bottomSafeArea = MediaQuery.viewPaddingOf(context).bottom;
    final keyboardSlotHeight =
        (bottomInset - bottomSafeArea).clamp(0.0, double.infinity).toDouble();
    if (_isSwitchingToKeyboard) {
      // 功能区切回键盘时，先维持切换瞬间冻结的真实 Dock 高度。只有
      // 系统键盘回到同一锚点后才交还给实时 Insets，避免任意设备在
      // 键盘动画期间因导航栏/手势区 Insets 变化而让输入栏短暂下沉。
      if (keyboardSlotHeight >= _keyboardTrayHeight - 1) {
        setState(() => _isSwitchingToKeyboard = false);
      }
      _logDockMetrics('metrics');
      return;
    }
    if (!_showFunctions && keyboardSlotHeight > _minValidKeyboardHeight) {
      if ((keyboardSlotHeight - _keyboardTrayHeight).abs() >= 1) {
        setState(() => _keyboardTrayHeight = keyboardSlotHeight);
      }
    }
    _logDockMetrics('metrics');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_levelSubscription?.cancel());
    _durationTimer?.cancel();
    _hideRecordingOverlay();
    if (_recording || _startingRecording) {
      unawaited(widget.controller.cancelVoiceRecording());
    }
    _focusNode.dispose();
    _pageController.dispose();
    _desktopScrollController.dispose();
    super.dispose();
  }

  void _toggleFunctions() {
    if (_showFunctions) {
      _switchToKeyboard();
    } else {
      final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
      final bottomSafeArea = MediaQuery.viewPaddingOf(context).bottom;
      final keyboardSlotHeight =
          (keyboardInset - bottomSafeArea)
              .clamp(0.0, double.infinity)
              .toDouble();
      if (keyboardSlotHeight > _minValidKeyboardHeight) {
        _keyboardTrayHeight = keyboardSlotHeight;
      }
      _focusNode.unfocus();
      setState(() {
        _showFunctions = true;
        _isSwitchingToKeyboard = false;
      });
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _logDockMetrics('open-functions'),
      );
    }
  }

  void _switchToKeyboard() {
    if (!_showFunctions) return;
    setState(() {
      _showFunctions = false;
      _isSwitchingToKeyboard = true;
    });
    _focusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _logDockMetrics('switch-to-keyboard'),
    );
  }

  void _closeFunctions() {
    if (!_showFunctions && !_isSwitchingToKeyboard) return;
    setState(() {
      _showFunctions = false;
      _isSwitchingToKeyboard = false;
    });
  }

  void _logDockMetrics(String reason) {
    if (!kDebugMode || !mounted) return;
    final mediaQuery = MediaQuery.of(context);
    final viewInsets = mediaQuery.viewInsets.bottom;
    final viewPadding = mediaQuery.viewPadding.bottom;
    final padding = mediaQuery.padding.bottom;
    final keyboardSlot =
        (viewInsets - viewPadding).clamp(0.0, double.infinity).toDouble();
    final signature =
        '$reason/$viewInsets/$viewPadding/$padding/$keyboardSlot/'
        '$_keyboardTrayHeight/$_showFunctions/$_isSwitchingToKeyboard';
    if (signature == _lastDockMetrics) return;
    _lastDockMetrics = signature;
    debugPrint(
      '[chatDock] reason=$reason '
      'viewInsets=$viewInsets viewPadding=$viewPadding padding=$padding '
      'keyboardSlot=$keyboardSlot tray=$_keyboardTrayHeight '
      'functions=$_showFunctions switching=$_isSwitchingToKeyboard',
    );
  }

  void _onInputChanged(String value) {
    widget.controller.updateMentionInput(value);
    if (widget.controller.mentionVisible && !_mentionSheetOpen) {
      unawaited(_showMentionSheet());
    }
  }

  Future<void> _showMentionSheet() async {
    _mentionSheetOpen = true;
    final selected = await showHalfPageSheet<bool>(
      context: context,
      options: const HalfPageSheetOptions(heightFactor: .55),
      builder:
          (_) => ChatMentionBottomSheet(
            controller: widget.controller,
            input: widget.input,
          ),
    );
    _mentionSheetOpen = false;
    if (selected != true) widget.controller.dismissMention();
    if (mounted) _focusNode.requestFocus();
  }

  void closeInputArea() {
    _focusNode.unfocus();
    _closeFunctions();
  }

  void focusText() {
    if (_voiceMode || _showFunctions) {
      if (_showFunctions) {
        _switchToKeyboard();
      }
      setState(() {
        _voiceMode = false;
      });
    }
    _focusNode.requestFocus();
  }

  void insertMention(String name) {
    focusText();
    final currentText = widget.input.text;
    final selection = widget.input.selection;
    final mentionText = '@$name ';
    if (selection.isValid && selection.start >= 0) {
      final newText = currentText.replaceRange(
        selection.start,
        selection.end,
        mentionText,
      );
      widget.input.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: selection.start + mentionText.length,
        ),
      );
    } else {
      final newText = '$currentText$mentionText';
      widget.input.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
    }
  }

  void cancelActiveRecording() {
    if (!_recording && !_startingRecording) return;
    _pointerReleased = true;
    unawaited(_completeRecording(forceCancel: true));
  }

  void _toggleVoiceMode() {
    _focusNode.unfocus();
    _closeFunctions();
    setState(() {
      _voiceMode = !_voiceMode;
    });
  }

  Future<void> _startRecording(LongPressStartDetails _) async {
    if (_startingRecording || _recording) return;
    _pointerReleased = false;
    _startingRecording = true;
    _recordingWatch.reset();
    setState(() {
      _cancelRecording = false;
      _recordingDuration = Duration.zero;
      _amplitudeSampleCount = 0;
      _finishingRecording = false;
      _levelPercentages.fillRange(0, _levelPercentages.length, 0);
    });
    try {
      final permitted = await widget.controller.hasVoiceRecordingPermission();
      debugPrint('[voicePermission] microphone=$permitted');
      if (!permitted) {
        _startingRecording = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未获得麦克风权限，请在系统设置中允许录音。')),
          );
        }
        return;
      }
      await widget.controller.startVoiceRecording();
      _startingRecording = false;
      if (_pointerReleased) {
        await widget.controller.cancelVoiceRecording();
        return;
      }
      if (!mounted) return;
      _recordingWatch.start();
      setState(() => _recording = true);
      _showRecordingOverlay();
      _levelSubscription = widget.controller
          .voiceRecordingLevels(const Duration(milliseconds: 70))
          .listen(
            _sampleRecordingLevel,
            onError: (Object error) {
              debugPrint('[voiceAmplitude][failed] error=$error');
            },
          );
      _durationTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!mounted || !_recording) return;
        setState(() => _recordingDuration = _recordingWatch.elapsed);
        _recordingOverlay?.markNeedsBuild();
        if (_recordingDuration >= const Duration(seconds: 60)) {
          unawaited(_completeRecording());
        }
      });
    } catch (error) {
      _startingRecording = false;
      _recordingWatch.stop();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法开始录音：$error')));
    }
  }

  void _sampleRecordingLevel(double levelPercent) {
    if (!_recording || !mounted) return;
    _amplitudeSampleCount++;
    final inputPercent = levelPercent.clamp(0.0, 100.0);
    final percentage = _voiceWaveVisualConfig.mapInput(inputPercent);
    final response = percentage > _levelPercentages.last ? 0.94 : 0.30;
    final smoothed =
        _levelPercentages.last * (1 - response) + percentage * response;
    if (_amplitudeSampleCount == 1 || _amplitudeSampleCount % 8 == 0) {
      final height = 5 + smoothed / 100 * 75;
      debugPrint(
        '[voiceWave] sample=$_amplitudeSampleCount '
        'inputPercent=${inputPercent.toStringAsFixed(1)} '
        'displayPercent=${percentage.toStringAsFixed(1)} '
        'smoothedPercent=${smoothed.toStringAsFixed(1)} '
        'height=${height.toStringAsFixed(1)}px',
      );
    }
    setState(() {
      _levelPercentages
        ..removeAt(0)
        ..add(smoothed.clamp(0.0, 100.0));
    });
    _recordingOverlay?.markNeedsBuild();
  }

  void _moveRecording(LongPressMoveUpdateDetails details) {
    final cancel = details.localPosition.dy < -44;
    if (cancel != _cancelRecording) {
      setState(() => _cancelRecording = cancel);
      _recordingOverlay?.markNeedsBuild();
    }
  }

  Future<void> _endRecording(LongPressEndDetails _) async {
    _pointerReleased = true;
    await _completeRecording();
  }

  Future<void> _completeRecording({bool forceCancel = false}) async {
    if (_startingRecording || !_recording || _finishingRecording) return;
    _finishingRecording = true;
    await _levelSubscription?.cancel();
    _levelSubscription = null;
    _durationTimer?.cancel();
    _durationTimer = null;
    _recordingWatch.stop();
    final duration = _recordingWatch.elapsed;
    final cancel =
        forceCancel ||
        _cancelRecording ||
        duration < const Duration(milliseconds: 800);
    setState(() {
      _recording = false;
      _recordingDuration = duration;
    });
    _hideRecordingOverlay();
    if (cancel) {
      await widget.controller.cancelVoiceRecording();
      if (mounted && !_cancelRecording) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('说话时间太短')));
      }
      return;
    }
    await widget.controller.finishVoiceRecording(duration);
  }

  void _showRecordingOverlay() {
    _hideRecordingOverlay();
    _recordingOverlay = OverlayEntry(
      builder:
          (context) => Positioned(
            top: MediaQuery.paddingOf(context).top + 48 + 18,
            left: 42,
            right: 42,
            child: IgnorePointer(
              child: Material(
                color: Colors.transparent,
                child: ChatRecordingPanel(
                  levelPercentages: _levelPercentages,
                  visualConfig: _voiceWaveVisualConfig,
                  duration: _recordingDuration,
                  cancelling: _cancelRecording,
                ),
              ),
            ),
          ),
    );
    Overlay.of(context).insert(_recordingOverlay!);
  }

  void _hideRecordingOverlay() {
    _recordingOverlay?.remove();
    _recordingOverlay = null;
  }

  Future<void> _selectFunction(ChatFunctionItem item) async {
    if (item.label == '设置背景') {
      _closeFunctions();
      await widget.onOpenAppearancePanel?.call();
      return;
    }
    if (item.label == '相册') {
      await widget.controller.chooseAndSendImages();
      return;
    }
    if (item.label == '拍摄') {
      await widget.controller.takeAndSendPhoto();
      return;
    }
    if (item.label == '视频') {
      await widget.controller.chooseAndSendVideo();
      return;
    }
    if (item.label == '文件') {
      await widget.controller.chooseAndSendFile();
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${item.label}功能暂未接入')));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isDesktop) {
      return _buildDesktopComposer(context);
    }
    final tokens = context.appTokens;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasBg = widget.hasBackground;

    final inputControlHeight = tokens.chatMessageMinHeight;
    final verticalPadding =
        ((tokens.chatComposerHeight - inputControlHeight) / 2)
            .clamp(0.0, double.infinity)
            .toDouble();

    // 胶囊药丸式输入框底色与边框：适配 Light / Dark 与 未设置背景 / 已设置背景
    final Color inputFillColor;
    final Color inputBorderColor;
    if (hasBg) {
      inputFillColor =
          isDark
              ? const Color(0xFF1E293B).withValues(alpha: 0.85)
              : Colors.white.withValues(alpha: 0.88);
      inputBorderColor =
          isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.08);
    } else {
      inputFillColor =
          isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
      inputBorderColor =
          isDark
              ? const Color(0xFF334155).withValues(alpha: 0.6)
              : const Color(0xFFE2E8F0);
    }

    final inputPillBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: BorderSide(color: inputBorderColor, width: 0.8),
    );
    final inputFocusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: BorderSide(
        color: colorScheme.primary.withValues(alpha: 0.7),
        width: 1.2,
      ),
    );

    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final bottomSafeArea = MediaQuery.viewPaddingOf(context).bottom;
    final keyboardSlotHeight =
        (bottomInset - bottomSafeArea).clamp(0.0, double.infinity).toDouble();
    final dockSlotHeight =
        _showFunctions || _isSwitchingToKeyboard
            ? (_keyboardTrayHeight > keyboardSlotHeight
                ? _keyboardTrayHeight
                : keyboardSlotHeight)
            : keyboardSlotHeight;
    final isKeyboardActive = keyboardSlotHeight > 0;

    final composer = Material(
      color: widget.useGlass ? Colors.transparent : null,
      elevation: widget.useGlass ? 0 : 8,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (_menuMode && widget.controller.officialAccountMenus.isNotEmpty)
            ChatPublicAccountMenu(
              menus:
                  widget.controller.officialAccountMenus
                      .map(PublicAccountMenuItem.fromJson)
                      .toList(),
              onToggleKeyboard: () => setState(() => _menuMode = false),
              onMenuItemSelected: _onMenuItemSelected,
            )
          else ...[
            Padding(
              padding: EdgeInsets.fromLTRB(
                10,
                verticalPadding,
                10,
                verticalPadding,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  SizedBox(
                    width: inputControlHeight,
                    height: inputControlHeight,
                    child: IconButton(
                      tooltip:
                          widget.controller.isOfficialAccount
                              ? '切换公众号菜单'
                              : (_voiceMode ? '切换键盘' : '语音输入'),
                      onPressed:
                          widget.controller.isOfficialAccount
                              ? () => setState(() => _menuMode = true)
                              : _toggleVoiceMode,
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        widget.controller.isOfficialAccount
                            ? Icons.menu_rounded
                            : (_voiceMode
                                ? Icons.keyboard_alt_outlined
                                : Icons.mic_none),
                      ),
                    ),
                  ),
                  Expanded(
                    child:
                        _voiceMode
                            ? GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onLongPressStart: _startRecording,
                              onLongPressMoveUpdate: _moveRecording,
                              onLongPressEnd: _endRecording,
                              child: Container(
                                height: inputControlHeight,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color:
                                      _recording
                                          ? colorScheme.primaryContainer
                                          : inputFillColor,
                                  border: Border.all(
                                    color: inputBorderColor,
                                    width: 0.8,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _recording
                                      ? (_cancelRecording ? '松开取消' : '松开发送')
                                      : '按住说话',
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w500,
                                    color:
                                        _recording
                                            ? colorScheme.onPrimaryContainer
                                            : (isDark
                                                ? const Color(0xFFE2E8F0)
                                                : const Color(0xFF334155)),
                                  ),
                                ),
                              ),
                            )
                            : ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: inputControlHeight,
                                maxHeight: 132,
                              ),
                              child: TextField(
                                controller: widget.input,
                                focusNode: _focusNode,
                                onTap: () {
                                  if (_showFunctions) {
                                    _switchToKeyboard();
                                  }
                                },
                                onChanged: _onInputChanged,
                                enabled: !widget.controller.isMuted,
                                minLines: 1,
                                maxLines: 5,
                                textInputAction: TextInputAction.newline,
                                style: TextStyle(
                                  fontSize: 15,
                                  color:
                                      isDark
                                          ? const Color(0xFFF8FAFC)
                                          : const Color(0xFF0F172A),
                                ),
                                decoration: InputDecoration(
                                  hintText:
                                      widget.controller.isMuted
                                          ? '你已被禁言，暂不能发言'
                                          : '输入消息',
                                  hintStyle: TextStyle(
                                    fontSize: 14.5,
                                    color:
                                        isDark
                                            ? const Color(0xFF64748B)
                                            : const Color(0xFF94A3B8),
                                  ),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 9.5,
                                  ),
                                  filled: true,
                                  fillColor: inputFillColor,
                                  border: inputPillBorder,
                                  enabledBorder: inputPillBorder,
                                  focusedBorder: inputFocusedBorder,
                                ),
                              ),
                            ),
                  ),
                  if (!_voiceMode)
                    SizedBox(
                      width: inputControlHeight,
                      height: inputControlHeight,
                      child: IconButton(
                        tooltip: '表情',
                        onPressed: () {
                          if (kIsWeb || widget.isDesktop) {
                            _openDesktopEmojiPicker(context);
                          } else {
                            _toggleFunctions();
                          }
                        },
                        padding: EdgeInsets.zero,
                        icon: const Icon(
                          Icons.sentiment_satisfied_alt_outlined,
                          size: 26,
                        ),
                      ),
                    ),
                  if (!_voiceMode)
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: widget.input,
                      builder: (context, val, _) {
                        final hasText = val.text.trim().isNotEmpty;
                        if (!hasText) {
                          return SizedBox(
                            width: inputControlHeight,
                            height: inputControlHeight,
                            child: IconButton(
                              tooltip: _showFunctions ? '打开键盘' : '更多功能',
                              onPressed: _toggleFunctions,
                              padding: EdgeInsets.zero,
                              icon: AnimatedRotation(
                                turns: _showFunctions ? 0.125 : 0,
                                duration: const Duration(milliseconds: 180),
                                child: const Icon(
                                  Icons.add_circle_outline_rounded,
                                  size: 26,
                                ),
                              ),
                            ),
                          );
                        } else {
                          return Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                minimumSize: Size(58, inputControlHeight),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                backgroundColor: const Color(0xFF07C160),
                                foregroundColor: Colors.white,
                                elevation: 0,
                              ),
                              onPressed:
                                  widget.controller.isSending ||
                                          widget.controller.isMuted
                                      ? null
                                      : () {
                                        final value = widget.input.text;
                                        widget.input.clear();
                                        widget.controller.send(value);
                                      },
                              child: const Text(
                                '发送',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          );
                        }
                      },
                    ),
                ],
              ),
            ),
            if (widget.controller.quoting case final quote?)
              Padding(
                padding: const EdgeInsets.fromLTRB(54, 0, 12, 8),
                child: ChatQuotePreview(
                  senderName: quote.senderName,
                  content: widget.quoteContentBuilder(quote),
                  onClear: widget.controller.cancelQuote,
                ),
              ),
            AnimatedContainer(
              duration:
                  isKeyboardActive || _isSwitchingToKeyboard
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              height: dockSlotHeight,
              child:
                  _showFunctions
                      ? ChatFunctionPanel(
                        items: _functions,
                        pageController: _pageController,
                        page: _page,
                        useGlass: widget.useGlass,
                        onPageChanged: (value) => setState(() => _page = value),
                        onSelected: _selectFunction,
                      )
                      : const SizedBox.shrink(),
            ),
          ],
        ],
      ),
    );

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        composer,
        if (bottomSafeArea > 0) SizedBox(height: bottomSafeArea),
      ],
    );

    if (widget.useGlass) {
      final Color glassBackground;
      final Color glassBorder;
      final double blurSigma = hasBg ? 18.0 : 20.0;

      if (hasBg) {
        glassBackground =
            isDark
                ? const Color(0xFF0B1120).withValues(alpha: 0.74)
                : Colors.white.withValues(alpha: 0.72);
        glassBorder =
            isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06);
      } else {
        glassBackground =
            isDark
                ? const Color(0xFF0B1120).withValues(alpha: 0.90)
                : Colors.white.withValues(alpha: 0.90);
        glassBorder =
            isDark
                ? const Color(0xFF1E293B).withValues(alpha: 0.8)
                : const Color(0xFFE2E8F0).withValues(alpha: 0.8);
      }

      return GlassContainer(
        borderRadius: BorderRadius.zero,
        borderWidth: 0.8,
        blurSigma: blurSigma,
        backgroundColor: glassBackground,
        borderColor: glassBorder,
        child: content,
      );
    }

    return content;
  }

  void insertText(String text) {
    focusText();
    final currentText = widget.input.text;
    final selection = widget.input.selection;
    if (selection.isValid && selection.start >= 0) {
      final newText = currentText.replaceRange(
        selection.start,
        selection.end,
        text,
      );
      widget.input.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: selection.start + text.length,
        ),
      );
    } else {
      final newText = '$currentText$text';
      widget.input.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
    }
  }

  void _openDesktopEmojiPicker(BuildContext context) {
    const emojis = <String>[
      '😀',
      '😁',
      '😂',
      '🤣',
      '😃',
      '😄',
      '😅',
      '😆',
      '😉',
      '😊',
      '😋',
      '😎',
      '😍',
      '😘',
      '🥰',
      '😗',
      '😙',
      '😚',
      '🙂',
      '🤗',
      '🤩',
      '🤔',
      '🤨',
      '😐',
      '😑',
      '😶',
      '🙄',
      '😏',
      '😣',
      '😥',
      '😮',
      '🤐',
      '😯',
      '😪',
      '😫',
      '🥱',
      '😴',
      '😌',
      '😛',
      '😜',
      '😝',
      '🤤',
      '😒',
      '😓',
      '😔',
      '😕',
      '🙃',
      '🤑',
      '😲',
      '🙁',
      '😖',
      '😞',
      '😟',
      '😤',
      '😢',
      '😭',
      '👍',
      '👎',
      '👏',
      '🙏',
      '🤝',
      '🎉',
      '🔥',
      '❤️',
      '💯',
      '🚀',
      '💡',
      '🎂',
      '🎁',
      '✨',
      '⭐',
      '☕',
    ];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (dialogContext) {
        return Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => Navigator.of(dialogContext).pop(),
            ),
            Positioned(
              left: 360,
              bottom: 180,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(10),
                color: isDark ? const Color(0xFF282828) : Colors.white,
                child: Container(
                  width: 290,
                  height: 220,
                  padding: const EdgeInsets.all(8),
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 8,
                          mainAxisSpacing: 4,
                          crossAxisSpacing: 4,
                        ),
                    itemCount: emojis.length,
                    itemBuilder: (context, index) {
                      final emoji = emojis[index];
                      return InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () {
                          insertText(emoji);
                          Navigator.of(dialogContext).pop();
                        },
                        child: Center(
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 触发桌面端屏幕截图 (截图按钮或 Alt+A 快捷键触发)
  Future<void> _handleDesktopScreenshot() async {
    if (_desktopCapturePending) return;
    _desktopCapturePending = true;
    final target = widget.controller;
    try {
      final screenCapture = ref.read(screenCaptureServiceProvider);
      final imageBytes = await screenCapture.capture(
        hideMainWindow: _hideWindowOnScreenshot,
      );
      if (imageBytes != null &&
          imageBytes.isNotEmpty &&
          mounted &&
          identical(target, widget.controller)) {
        await _confirmImageSend(
          imageBytes,
          fileName: 'screenshot_${DateTime.now().millisecondsSinceEpoch}.png',
        );
      }
    } catch (e) {
      debugPrint('[ChatComposer] 屏幕截图异常: $e');
    } finally {
      _desktopCapturePending = false;
    }
  }

  Future<void> _confirmImageSend(Uint8List bytes, {String? fileName}) async {
    if (!mounted) return;
    final target = widget.controller;
    final result = await ClipboardImageConfirmDialog.show(
      context,
      imageBytes: bytes,
      onAnnotatedSend: (annotatedBytes, caption) async {
        if (!mounted || !identical(target, widget.controller)) return;
        await target.sendImageBytes(
          annotatedBytes,
          caption: caption,
          fileName: fileName,
        );
      },
    );
    if (!mounted || !identical(target, widget.controller)) return;
    if (result != null && result.confirmed) {
      await target.sendImageBytes(
        bytes,
        caption: result.caption,
        fileName: fileName,
      );
    }
  }

  /// 智能识别剪贴板内容（Ctrl+V 触发）
  /// - 优先检测是否包含系统复制的文件（支持批量单文件或多文件）-> 弹出文件确认对话框；
  /// - 其次检测是否包含剪贴板图像（截图或复制的图片）-> 弹出图片确认对话框；
  /// - 若仅为纯文本，则返回 false，放行系统默认输入框粘贴行为。
  Future<bool> _handleClipboardPaste() async {
    try {
      final clipboard = SystemClipboardService();

      // 1. 优先检查是否存在系统文件列表 (例如在资源管理器中 Ctrl+C 复制的 1 个或多个文件)
      final files = await clipboard.readFiles();
      if (files.isNotEmpty) {
        if (!mounted) return true;
        final result = await ClipboardFilesConfirmDialog.show(
          context,
          filePaths: files,
        );
        if (result != null && result.confirmed && result.files.isNotEmpty) {
          await widget.controller.sendDirectFiles(
            result.files,
            caption: result.caption,
          );
        }
        return true; // 拦截默认文本粘贴
      }

      // 2. 检查是否存在图像数据 (例如截图工具写入剪贴板或浏览器复制图片)
      final imageBytes = await clipboard.readImage();
      if (imageBytes != null && imageBytes.isNotEmpty) {
        if (!mounted) return true;
        await _confirmImageSend(imageBytes);
        return true; // 拦截默认文本粘贴
      }
    } catch (e) {
      debugPrint('[ChatComposer] 剪贴板识别处理异常: $e');
    }
    return false; // 无文件或图像，放行常规纯文本粘贴
  }

  void _sendDesktopText() {
    final text = widget.input.text.trim();
    if (text.isNotEmpty &&
        !widget.controller.isSending &&
        !widget.controller.isMuted) {
      widget.input.clear();
      widget.controller.send(text);
    }
  }

  void _insertNewlineAtCursor() {
    final text = widget.input.text;
    final selection = widget.input.selection;
    final start = selection.start;
    final end = selection.end;

    if (start >= 0 && end >= 0) {
      final newText = text.replaceRange(start, end, '\n');
      widget.input.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: start + 1),
      );
    } else {
      widget.input.text = '$text\n';
      widget.input.selection = TextSelection.collapsed(
        offset: widget.input.text.length,
      );
    }
  }

  KeyEventResult _handleDesktopKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      // 1. 发送消息逻辑 (支持用户快捷键偏好切换)
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        final isCtrl =
            HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed;
        final isShift = HardwareKeyboard.instance.isShiftPressed;

        if (_sendOnEnter) {
          // 模式 1: 按 Enter 发送，Shift+Enter 或 Ctrl+Enter 换行
          if (isCtrl) {
            _insertNewlineAtCursor();
            return KeyEventResult.handled;
          } else if (isShift) {
            return KeyEventResult.ignored; // 放行系统默认换行
          } else {
            _sendDesktopText();
            return KeyEventResult.handled;
          }
        } else {
          // 模式 2: 按 Ctrl+Enter 发送，Enter 换行
          if (isCtrl) {
            _sendDesktopText();
            return KeyEventResult.handled;
          } else {
            return KeyEventResult.ignored; // 放行系统默认换行
          }
        }
      }

      // 2. Alt + A 快捷截屏
      if (event.logicalKey == LogicalKeyboardKey.keyA &&
          HardwareKeyboard.instance.isAltPressed) {
        _handleDesktopScreenshot();
        return KeyEventResult.handled;
      }

      // 3. Ctrl + V 智能剪贴板粘贴
      if (event.logicalKey == LogicalKeyboardKey.keyV &&
          (HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed)) {
        final prevText = widget.input.text;
        _handleClipboardPaste().then((intercepted) {
          if (intercepted && mounted) {
            if (widget.input.text != prevText) {
              widget.input.text = prevText;
            }
          }
        });
      }
    }
    return KeyEventResult.ignored;
  }

  Widget _buildDesktopToolbar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _DesktopToolIcon(
              icon: Icons.sentiment_satisfied_alt_outlined,
              tooltip: '表情',
              onPressed: () => _openDesktopEmojiPicker(context),
            ),
            const SizedBox(width: 4),
            _DesktopToolIcon(
              icon: Icons.folder_open_outlined,
              tooltip: '发送文件',
              onPressed: widget.controller.chooseAndSendFile,
            ),
            const SizedBox(width: 4),
            // 屏幕截图按钮 (Alt+A) 配合选项菜单 (立即截屏 / 截屏时隐藏当前窗口)
            _buildDesktopScreenshotTool(context),
            const SizedBox(width: 4),
            _DesktopToolIcon(
              icon: Icons.history_rounded,
              tooltip: '聊天记录',
              onPressed: () {
                showToast('已加载全部漫游聊天记录，向上滚动可查阅', type: ToastType.info);
              },
            ),
            const SizedBox(width: 4),
            _DesktopToolIcon(
              icon: Icons.image_outlined,
              tooltip: '发送图片',
              onPressed: widget.controller.chooseAndSendImages,
            ),
            const SizedBox(width: 4),
            if (widget.onOpenAppearancePanel != null)
              _DesktopToolIcon(
                icon: Icons.wallpaper_rounded,
                tooltip: '设置聊天背景',
                onPressed: widget.onOpenAppearancePanel!,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopTextInput(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Focus(
        onKeyEvent: _handleDesktopKeyEvent,
        child: Scrollbar(
          controller: _desktopScrollController,
          thumbVisibility: false,
          child: TextField(
            controller: widget.input,
            focusNode: _focusNode,
            scrollController: _desktopScrollController,
            expands: true,
            maxLines: null,
            minLines: null,
            textAlignVertical: TextAlignVertical.top,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: isDark ? const Color(0xFFF0F0F0) : const Color(0xFF1E293B),
            ),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.only(top: 2, bottom: 4),
              hintText:
                  widget.controller.isMuted
                      ? '全员禁言中'
                      : '输入消息，支持拖拽或 Ctrl+V 粘贴图片/文件...',
              hintStyle: TextStyle(
                fontSize: 13.5,
                color:
                    isDark ? const Color(0xFF757575) : const Color(0xFF9E9E9E),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopBottomBar(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 320;
          final hintText =
              _sendOnEnter
                  ? (isNarrow ? 'Enter 发送' : '按 Enter 发送，按 Ctrl+Enter 换行')
                  : (isNarrow ? 'Ctrl+Enter 发送' : '按 Ctrl+Enter 发送，按 Enter 换行');

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  hintText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color:
                        isDark
                            ? const Color(0xFF666666)
                            : const Color(0xFFAAAAAA),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // 微信同款“发送(S)”组合按钮 (带快捷键下拉切换)
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: widget.input,
                builder: (context, value, _) {
                  final canSend =
                      value.text.trim().isNotEmpty &&
                      !widget.controller.isSending &&
                      !widget.controller.isMuted;

                  final btnBg =
                      canSend
                          ? const Color(0xFF07C160)
                          : (isDark
                              ? const Color(0xFF2E2E2E)
                              : const Color(0xFFE5E5E5));
                  final btnFg =
                      canSend
                          ? Colors.white
                          : (isDark
                              ? const Color(0xFF666666)
                              : const Color(0xFFAAAAAA));

                  return Container(
                    height: 28,
                    decoration: BoxDecoration(
                      color: btnBg,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 发送主体按钮
                        InkWell(
                          onTap: canSend ? _sendDesktopText : null,
                          hoverColor: canSend ? const Color(0xFF06AD56) : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Center(
                              child: Text(
                                '发送(S)',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: btnFg,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // 细微竖分割线
                        Container(
                          width: 1,
                          height: 16,
                          color:
                              canSend
                                  ? Colors.white24
                                  : (isDark ? Colors.white10 : Colors.black12),
                        ),
                        // 下拉切换快捷键小三角
                        Theme(
                          data: Theme.of(
                            context,
                          ).copyWith(hoverColor: Colors.transparent),
                          child: PopupMenuButton<bool>(
                            tooltip: '发送快捷键设置',
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              Icons.arrow_drop_down_rounded,
                              size: 16,
                              color: btnFg,
                            ),
                            offset: const Offset(0, -95),
                            onSelected: (mode) {
                              setState(() => _sendOnEnter = mode);
                              showToast(
                                mode
                                    ? '已切换为: 按 Enter 键发送'
                                    : '已切换为: 按 Ctrl+Enter 键发送',
                                type: ToastType.info,
                              );
                            },
                            itemBuilder:
                                (ctx) => [
                                  PopupMenuItem(
                                    value: true,
                                    child: Row(
                                      children: [
                                        Icon(
                                          _sendOnEnter
                                              ? Icons.check_rounded
                                              : Icons.check_box_outline_blank,
                                          size: 16,
                                          color:
                                              _sendOnEnter
                                                  ? const Color(0xFF07C160)
                                                  : Colors.transparent,
                                        ),
                                        const SizedBox(width: 8),
                                        const Text(
                                          '按 Enter 键发送消息',
                                          style: TextStyle(fontSize: 12.5),
                                        ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: false,
                                    child: Row(
                                      children: [
                                        Icon(
                                          !_sendOnEnter
                                              ? Icons.check_rounded
                                              : Icons.check_box_outline_blank,
                                          size: 16,
                                          color:
                                              !_sendOnEnter
                                                  ? const Color(0xFF07C160)
                                                  : Colors.transparent,
                                        ),
                                        const SizedBox(width: 8),
                                        const Text(
                                          '按 Ctrl+Enter 键发送消息',
                                          style: TextStyle(fontSize: 12.5),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDesktopComposer(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF7F7F7);
    final borderColor =
        isDark ? const Color(0x1FFFFFFF) : const Color(0x1F000000);
    final quoted = widget.controller.quoting;

    return Container(
      height: _desktopComposerHeight,
      decoration: BoxDecoration(color: bg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. 微信同款顶部可拖拽高度调节分割条 (Resize Handle)
          MouseRegion(
            cursor: SystemMouseCursors.resizeUpDown,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragStart:
                  (_) => setState(() => _isDraggingSplitter = true),
              onVerticalDragEnd:
                  (_) => setState(() => _isDraggingSplitter = false),
              onVerticalDragCancel:
                  () => setState(() => _isDraggingSplitter = false),
              onVerticalDragUpdate: (details) {
                setState(() {
                  _desktopComposerHeight =
                      (_desktopComposerHeight - details.delta.dy).clamp(
                        _minDesktopComposerHeight,
                        _maxDesktopComposerHeight,
                      );
                });
              },
              child: Container(
                height: 6,
                color: Colors.transparent,
                child: Center(
                  child: Container(
                    height: 1,
                    color:
                        _isDraggingSplitter
                            ? const Color(0xFF07C160)
                            : borderColor,
                  ),
                ),
              ),
            ),
          ),

          // 2. 引用消息展示
          if (quoted != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              color:
                  isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.black.withValues(alpha: 0.03),
              child: Row(
                children: [
                  Expanded(child: widget.quoteContentBuilder(quoted)),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 16),
                    onPressed: widget.controller.cancelQuote,
                    tooltip: '移除引用',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

          // 3. 顶部微信同款工具栏 (表情、发送文件、屏幕截图、聊天记录、发送图片、背景)
          _buildDesktopToolbar(context),

          // 4. 多行文本输入区 (Expanded 随拖拽高度弹性拉伸)
          Expanded(child: _buildDesktopTextInput(isDark)),

          // 5. 底部状态与微信同款“发送(S)”组合按钮
          _buildDesktopBottomBar(context, isDark),
        ],
      ),
    );
  }

  Widget _buildDesktopScreenshotTool(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DesktopToolIcon(
          icon: Icons.crop_free_rounded,
          tooltip: '屏幕截图 (Alt+A)',
          onPressed: _handleDesktopScreenshot,
        ),
        Theme(
          data: Theme.of(context).copyWith(hoverColor: Colors.transparent),
          child: PopupMenuButton<String>(
            tooltip: '截图设置',
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.arrow_drop_down_rounded, size: 16),
            offset: const Offset(0, -95),
            onSelected: (value) {
              if (value == 'toggle_hide') {
                setState(() {
                  _hideWindowOnScreenshot = !_hideWindowOnScreenshot;
                });
                showToast(
                  _hideWindowOnScreenshot ? '已开启截屏时隐藏窗口' : '已关闭截屏时隐藏窗口',
                  type: ToastType.info,
                );
              } else if (value == 'capture') {
                _handleDesktopScreenshot();
              }
            },
            itemBuilder:
                (ctx) => [
                  const PopupMenuItem(
                    value: 'capture',
                    child: Row(
                      children: [
                        Icon(Icons.crop_free_rounded, size: 16),
                        SizedBox(width: 8),
                        Text('立即截屏 (Alt+A)', style: TextStyle(fontSize: 12.5)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'toggle_hide',
                    child: Row(
                      children: [
                        Icon(
                          _hideWindowOnScreenshot
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded,
                          size: 16,
                          color:
                              _hideWindowOnScreenshot
                                  ? const Color(0xFF07C160)
                                  : null,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          '截屏时隐藏当前窗口',
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ],
          ),
        ),
      ],
    );
  }
}

class _DesktopToolIcon extends StatelessWidget {
  const _DesktopToolIcon({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? const Color(0xFFB0B0B0) : const Color(0xFF555555);

    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onPressed,
        hoverColor: isDark ? Colors.white10 : Colors.black12,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }
}
