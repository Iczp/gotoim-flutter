import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/parametric_chat_bubble.dart';

/// Focused visual tuner for the two independently curved tail lines.
class ChatBubbleDiagnosticsPage extends StatefulWidget {
  const ChatBubbleDiagnosticsPage({super.key});

  @override
  State<ChatBubbleDiagnosticsPage> createState() =>
      _ChatBubbleDiagnosticsPageState();
}

class _ChatBubbleDiagnosticsPageState extends State<ChatBubbleDiagnosticsPage> {
  ParametricBubbleConfig _config = const ParametricBubbleConfig();

  Map<String, double> get _generatedParameters => <String, double>{
    'leadingCurveBend': _config.leadingCurveBend,
    'trailingCurveBend': _config.trailingCurveBend,
  };

  Set<int> get _uniformBendSelection {
    if (_config.leadingCurveBend == 1 && _config.trailingCurveBend == 1) {
      return <int>{1};
    }
    if (_config.leadingCurveBend == -1 && _config.trailingCurveBend == -1) {
      return <int>{-1};
    }
    return <int>{};
  }

  void _setUniformBend(int direction) => setState(() {
    _config = _config.copyWith(
      leadingCurveBend: direction.toDouble(),
      trailingCurveBend: direction.toDouble(),
    );
  });

  Future<void> _copyJson() async {
    await Clipboard.setData(
      ClipboardData(
        text: const JsonEncoder.withIndent('  ').convert(_generatedParameters),
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('曲线参数 JSON 已复制')));
  }

  @override
  Widget build(BuildContext context) {
    final json = const JsonEncoder.withIndent(
      '  ',
    ).convert(_generatedParameters);
    return Scaffold(
      appBar: AppBar(
        title: const Text('聊天气泡曲线调节器'),
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
          if (constraints.maxHeight <= 0) return const SizedBox.shrink();
          final previewHeight =
              (constraints.maxHeight * .30).clamp(0.0, 174.0).toDouble();
          final showPreview = previewHeight >= 72;
          return Column(
            children: <Widget>[
              if (showPreview)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: _PreviewCard(config: _config, height: previewHeight),
                ),
              if (showPreview) const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        '快捷预设',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<int>(
                        segments: const <ButtonSegment<int>>[
                          ButtonSegment(
                            value: 1,
                            icon: Icon(Icons.south_rounded),
                            label: Text('两段向下凹'),
                          ),
                          ButtonSegment(
                            value: -1,
                            icon: Icon(Icons.north_rounded),
                            label: Text('两段向上凹'),
                          ),
                        ],
                        selected: _uniformBendSelection,
                        emptySelectionAllowed: true,
                        onSelectionChanged:
                            (selected) => _setUniformBend(selected.first),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '单独微调',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      _CurveSlider(
                        label: '第一段曲线凹向',
                        value: _config.leadingCurveBend,
                        onChanged:
                            (value) => setState(() {
                              _config = _config.copyWith(
                                leadingCurveBend: value,
                              );
                            }),
                      ),
                      _CurveSlider(
                        label: '第二段曲线凹向',
                        value: _config.trailingCurveBend,
                        onChanged:
                            (value) => setState(() {
                              _config = _config.copyWith(
                                trailingCurveBend: value,
                              );
                            }),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '生成参数',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      _JsonCard(json: json),
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          OutlinedButton.icon(
                            onPressed:
                                () => setState(() {
                                  _config = const ParametricBubbleConfig();
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
  const _PreviewCard({required this.config, required this.height});

  final ParametricBubbleConfig config;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: height,
      padding: EdgeInsets.all(height < 140 ? 12 : 20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: ParametricChatBubble(
            config: config,
            color: colors.surfaceContainerHighest,
            child: Text(
              '独立调节两段曲线的凹向。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      ),
    );
  }
}

class _CurveSlider extends StatelessWidget {
  const _CurveSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      const SizedBox(height: 10),
      Row(
        children: <Widget>[
          Expanded(child: Text(label)),
          Text(value.toStringAsFixed(2)),
        ],
      ),
      const Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[Text('向上凹 -1'), Text('直线 0'), Text('向下凹 1')],
      ),
      Slider(value: value, min: -1, max: 1, onChanged: onChanged),
    ],
  );
}

class _JsonCard extends StatelessWidget {
  const _JsonCard({required this.json});

  final String json;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      json,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
    ),
  );
}
