import 'dart:async';
import 'package:flutter/material.dart';

import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/half_page_sheet.dart';
import '../../application/chat_controller.dart';
import '../../data/models/chat_message.dart';
import 'chat_function_panel.dart';
import 'chat_mention_panel.dart';
import 'chat_public_account_menu.dart';
import 'chat_quote_preview.dart';
import 'chat_recording_panel.dart';

/// 底部消息输入与操作区组件（ChatComposer）
///
/// 核心职责：
/// 1. 文本输入：多行自适应输入框，支持 Enter 换行与禁言状态禁用；
/// 2. 语音输入切换：长按录音、声波振幅实时采样、上滑取消与超时自动发送；
/// 3. 表情与附件功能面板切换：软键盘与功能托盘平滑高度无缝衔接；
/// 4. 引用回复：顶部浮层展示被引用消息，支持一键移除引用；
/// 5. 群聊 `@` 艾特触发：输入 `@` 字符自动唤起成员选择浮层。
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    required this.controller,
    required this.input,
    required this.quoteContentBuilder,
    super.key,
  });

  /// 聊天状态控制器
  final ChatController controller;

  /// 输入框文本控制器
  final TextEditingController input;

  /// 引用消息内容构建器
  final Widget Function(ChatMessage quote) quoteContentBuilder;

  @override
  State<ChatComposer> createState() => ChatComposerState();
}

class ChatComposerState extends State<ChatComposer>
    with WidgetsBindingObserver {

  final FocusNode _focusNode = FocusNode();
  final PageController _pageController = PageController();
  bool _showFunctions = false;
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

  static const _functions = <ChatFunctionItem>[
    ChatFunctionItem('相册', Icons.photo_outlined),
    ChatFunctionItem('拍摄', Icons.camera_alt_outlined),
    ChatFunctionItem('视频', Icons.videocam_outlined),
    ChatFunctionItem('文件', Icons.insert_drive_file_outlined, enabled: true),
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
  static const _fallbackFunctionTrayHeight = 238.0;
  double _keyboardTrayHeight = _fallbackFunctionTrayHeight;

  @override
  void initState() {
    super.initState();
    _menuMode = widget.controller.isOfficialAccount;
    WidgetsBinding.instance.addObserver(this);
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
    final view = View.of(context);
    final height = view.viewInsets.bottom / view.devicePixelRatio;
    if (height < 180) return;
    final clampedHeight = height.clamp(200.0, 420.0);
    if ((clampedHeight - _keyboardTrayHeight).abs() < 1) return;
    setState(() => _keyboardTrayHeight = clampedHeight);
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
    super.dispose();
  }

  void _toggleFunctions() {
    if (_showFunctions) {
      setState(() => _showFunctions = false);
      _focusNode.requestFocus();
    } else {
      _focusNode.unfocus();
      setState(() => _showFunctions = true);
    }
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
    if (_showFunctions) setState(() => _showFunctions = false);
  }

  void focusText() {
    if (_voiceMode || _showFunctions) {
      setState(() {
        _voiceMode = false;
        _showFunctions = false;
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
        selection: TextSelection.collapsed(
          offset: newText.length,
        ),
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
    setState(() {
      _showFunctions = false;
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
            top: MediaQuery.paddingOf(context).top + kToolbarHeight + 18,
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
  Widget build(BuildContext context) => Material(
    elevation: 8,
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (_menuMode && widget.controller.officialAccountMenus.isNotEmpty)
            ChatPublicAccountMenu(
              menus: widget.controller.officialAccountMenus
                  .map(PublicAccountMenuItem.fromJson)
                  .toList(),
              onToggleKeyboard: () => setState(() => _menuMode = false),
              onMenuItemSelected: _onMenuItemSelected,
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  SizedBox(
                    width: 44,
                    height: 42,
                    child: IconButton(
                      tooltip: widget.controller.isOfficialAccount
                          ? '切换公众号菜单'
                          : (_voiceMode ? '切换键盘' : '语音输入'),
                      onPressed: widget.controller.isOfficialAccount
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
                              height: 42,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color:
                                    _recording
                                        ? Theme.of(
                                          context,
                                        ).colorScheme.primaryContainer
                                        : Theme.of(
                                          context,
                                        ).colorScheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _recording
                                    ? (_cancelRecording ? '松开取消' : '松开发送')
                                    : '按住说话',
                              ),
                            ),
                          )
                          : ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 132),
                            child: TextField(
                              controller: widget.input,
                              focusNode: _focusNode,
                              onTap: () {
                                if (_showFunctions) {
                                  setState(() => _showFunctions = false);
                                }
                              },
                              onChanged: _onInputChanged,
                              enabled: !widget.controller.isMuted,
                              minLines: 1,
                              maxLines: 5,
                              textInputAction: TextInputAction.newline,
                              decoration: InputDecoration(
                                hintText:
                                    widget.controller.isMuted
                                        ? '你已被禁言，暂不能发言'
                                        : '输入消息',
                                isDense: true,
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                ),
                if (!_voiceMode)
                  SizedBox(
                    width: 44,
                    height: 42,
                    child: IconButton(
                      tooltip: _showFunctions ? '打开键盘' : '更多功能',
                      onPressed: _toggleFunctions,
                      padding: EdgeInsets.zero,
                      icon: AnimatedRotation(
                        turns: _showFunctions ? 0.125 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: const Icon(Icons.add_circle_outline),
                      ),
                    ),
                  ),
                if (!_voiceMode)
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(56, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed:
                        widget.controller.isSending || widget.controller.isMuted
                            ? null
                            : () {
                              final value = widget.input.text;
                              widget.input.clear();
                              widget.controller.send(value);
                            },
                    child: const Text('发送'),
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
          TweenAnimationBuilder<double>(
            tween: Tween<double>(end: _showFunctions ? 1 : 0),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: SizedBox(
              height: _keyboardTrayHeight,
              child: ChatFunctionPanel(
                items: _functions,
                pageController: _pageController,
                page: _page,
                onPageChanged: (value) => setState(() => _page = value),
                onSelected: _selectFunction,
              ),
            ),
            builder: (context, heightFactor, child) {
              if (heightFactor <= 0) return const SizedBox.shrink();
              return ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: heightFactor,
                  child: child,
                ),
              );
            },
          ),
        ],
      ],
    ),
  ),
);
}
