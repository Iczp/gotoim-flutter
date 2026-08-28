import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/parametric_chat_bubble.dart';

/// Live visual tuner for the parametric inverted-S chat bubble.
class ChatBubbleDiagnosticsPage extends StatefulWidget {
  const ChatBubbleDiagnosticsPage({super.key});

  @override
  State<ChatBubbleDiagnosticsPage> createState() =>
      _ChatBubbleDiagnosticsPageState();
}

class _ChatBubbleDiagnosticsPageState extends State<ChatBubbleDiagnosticsPage> {
  ParametricBubbleConfig _config = const ParametricBubbleConfig();
  Color _backgroundColor = const Color(0xFFDCE5FF);
  Color _textColor = const Color(0xFF172033);

  void _update(ParametricBubbleConfig next) => setState(() => _config = next);

  Map<String, Object> get _generatedParameters => <String, Object>{
    ..._config.toJson(),
    'style': <String, String>{
      'backgroundColor': _hexColor(_backgroundColor),
      'textColor': _hexColor(_textColor),
    },
  };

  String _hexColor(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

  String _inversionHint(double value) {
    if (value < .34) return '轻微内收';
    if (value < .67) return 'S 型微凹';
    return '强反角收紧';
  }

  String _sharpnessHint(double value) {
    if (value < .34) return '圆润尾端';
    if (value < .67) return '清晰尖端';
    return '极尖挑刺';
  }

  Future<void> _copyJson() async {
    await Clipboard.setData(
      ClipboardData(
        text: const JsonEncoder.withIndent('  ').convert(_generatedParameters),
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('气泡参数 JSON 已复制')));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final json = const JsonEncoder.withIndent(
      '  ',
    ).convert(_generatedParameters);
    return Scaffold(
      appBar: AppBar(
        title: const Text('聊天气泡参数调节器'),
        actions: <Widget>[
          IconButton(
            tooltip: '复制 JSON 参数',
            onPressed: _copyJson,
            icon: const Icon(Icons.content_copy_outlined),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 420;
          final previewHeight = compact ? 112.0 : 174.0;
          return Column(
            children: <Widget>[
              if (!compact)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(
                    '实时预览反角微凹 S 曲线尾巴。修改任一参数会立即重绘，不会影响正式聊天消息。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              SizedBox(height: compact ? 8 : 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _PreviewCard(
                  config: _config,
                  backgroundColor: _backgroundColor,
                  textColor: _textColor,
                  height: previewHeight,
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              Expanded(
                // This panel contains a small, fixed set of controls. A single
                // scroll child avoids SliverList relayout while sliders rebuild.
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        '方向与锚点',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<ParametricBubbleSide>(
                        segments: const <ButtonSegment<ParametricBubbleSide>>[
                          ButtonSegment(
                            value: ParametricBubbleSide.left,
                            icon: Icon(Icons.format_align_left_rounded),
                            label: Text('左侧接入'),
                          ),
                          ButtonSegment(
                            value: ParametricBubbleSide.right,
                            icon: Icon(Icons.format_align_right_rounded),
                            label: Text('右侧接入'),
                          ),
                        ],
                        selected: <ParametricBubbleSide>{_config.side},
                        onSelectionChanged:
                            (selected) =>
                                _update(_config.copyWith(side: selected.first)),
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<ParametricBubbleAnchor>(
                        segments: const <ButtonSegment<ParametricBubbleAnchor>>[
                          ButtonSegment(
                            value: ParametricBubbleAnchor.top,
                            icon: Icon(Icons.vertical_align_top_rounded),
                            label: Text('顶部锚点'),
                          ),
                          ButtonSegment(
                            value: ParametricBubbleAnchor.bottom,
                            icon: Icon(Icons.vertical_align_bottom_rounded),
                            label: Text('底部锚点'),
                          ),
                        ],
                        selected: <ParametricBubbleAnchor>{_config.anchor},
                        onSelectionChanged:
                            (selected) => _update(
                              _config.copyWith(anchor: selected.first),
                            ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '几何参数',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      _SliderSetting(
                        label: '垂直偏移 offset',
                        value: _config.offset,
                        min: 0,
                        max: 100,
                        unit: 'px',
                        onChanged:
                            (value) => _update(_config.copyWith(offset: value)),
                      ),
                      _SliderSetting(
                        label: '尾巴长度 tailLength',
                        value: _config.tailLength,
                        min: 4,
                        max: 48,
                        unit: 'px',
                        onChanged:
                            (value) =>
                                _update(_config.copyWith(tailLength: value)),
                      ),
                      _SliderSetting(
                        label: '尾巴高度 tailHeight',
                        value: _config.tailHeight,
                        min: 8,
                        max: 48,
                        unit: 'px',
                        onChanged:
                            (value) =>
                                _update(_config.copyWith(tailHeight: value)),
                      ),
                      _SliderSetting(
                        label:
                            '反角凹陷度 inversion（${_inversionHint(_config.inversion)}）',
                        value: _config.inversion,
                        min: 0,
                        max: 1,
                        unit: '',
                        onChanged:
                            (value) =>
                                _update(_config.copyWith(inversion: value)),
                      ),
                      _SliderSetting(
                        label:
                            '尖端锐度 sharpness（${_sharpnessHint(_config.sharpness)}）',
                        value: _config.sharpness,
                        min: 0,
                        max: 1,
                        unit: '',
                        onChanged:
                            (value) =>
                                _update(_config.copyWith(sharpness: value)),
                      ),
                      _SliderSetting(
                        label: '主体圆角 radius',
                        value: _config.radius,
                        min: 4,
                        max: 40,
                        unit: 'px',
                        onChanged:
                            (value) => _update(_config.copyWith(radius: value)),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '样式颜色',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      _ColorSetting(
                        label: '气泡背景 backgroundColor',
                        color: _backgroundColor,
                        onChanged:
                            (color) => setState(() => _backgroundColor = color),
                      ),
                      _ColorSetting(
                        label: '文字颜色 textColor',
                        color: _textColor,
                        onChanged:
                            (color) => setState(() => _textColor = color),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '生成参数',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        // Copy is provided explicitly below. A plain Text avoids the
                        // selection overlay intercepting vertical drags in this panel.
                        child: Text(
                          json,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontFamily: 'monospace'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          OutlinedButton.icon(
                            onPressed:
                                () => setState(() {
                                  _config = const ParametricBubbleConfig();
                                  _backgroundColor = const Color(0xFFDCE5FF);
                                  _textColor = const Color(0xFF172033);
                                }),
                            icon: const Icon(Icons.restart_alt_rounded),
                            label: const Text('恢复默认'),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: _copyJson,
                            icon: const Icon(Icons.content_copy_outlined),
                            label: const Text('复制参数'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.config,
    required this.backgroundColor,
    required this.textColor,
    required this.height,
  });

  final ParametricBubbleConfig config;
  final Color backgroundColor;
  final Color textColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isRight = config.side == ParametricBubbleSide.right;
    return Container(
      height: height,
      padding: EdgeInsets.all(height < 140 ? 12 : 20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Align(
        alignment: isRight ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: ParametricChatBubble(
            config: config,
            color: backgroundColor,
            child: Text(
              '这是可实时调节的参数化聊天气泡。\n拖动滑块观察反角 S 曲线尾巴的变化。',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: textColor),
            ),
          ),
        ),
      ),
    );
  }
}

class _SliderSetting extends StatelessWidget {
  const _SliderSetting({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String unit;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      const SizedBox(height: 10),
      Row(
        children: <Widget>[
          Expanded(child: Text(label)),
          Text('${value.toStringAsFixed(2)}$unit'),
        ],
      ),
      Slider(value: value, min: min, max: max, onChanged: onChanged),
    ],
  );
}

class _ColorSetting extends StatelessWidget {
  const _ColorSetting({
    required this.label,
    required this.color,
    required this.onChanged,
  });

  final String label;
  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    final hsv = HSVColor.fromColor(color);
    final colorText =
        '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(label)),
            Text(colorText),
          ],
        ),
        _ColorChannelSlider(
          label: '色相 H',
          value: hsv.hue,
          max: 360,
          onChanged: (value) => onChanged(hsv.withHue(value).toColor()),
        ),
        _ColorChannelSlider(
          label: '饱和度 S',
          value: hsv.saturation * 100,
          max: 100,
          onChanged:
              (value) => onChanged(hsv.withSaturation(value / 100).toColor()),
        ),
        _ColorChannelSlider(
          label: '明度 V',
          value: hsv.value * 100,
          max: 100,
          onChanged: (value) => onChanged(hsv.withValue(value / 100).toColor()),
        ),
      ],
    );
  }
}

class _ColorChannelSlider extends StatelessWidget {
  const _ColorChannelSlider({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      SizedBox(width: 44, child: Text(label)),
      Expanded(
        child: Slider(value: value, min: 0, max: max, onChanged: onChanged),
      ),
      SizedBox(
        width: 36,
        child: Text(value.round().toString(), textAlign: TextAlign.end),
      ),
    ],
  );
}
