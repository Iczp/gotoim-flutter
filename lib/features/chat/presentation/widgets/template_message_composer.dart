import 'dart:convert';

import 'package:flutter/material.dart';

import '../../application/chat_controller.dart';
import '../../data/models/chat_message.dart';
import '../../data/models/template_message_content.dart';
import '../message_content/template_message_content.dart';
import '../message_content/chat_message_presentation.dart';

/// A sender fills a fixed published revision; layouts remain read-only.
class TemplateMessageComposer extends StatefulWidget {
  const TemplateMessageComposer({required this.controller, super.key});
  final ChatController controller;

  static Future<void> open(BuildContext context, ChatController controller) =>
      showDialog<void>(
        context: context,
        builder: (_) => TemplateMessageComposer(controller: controller),
      );

  @override
  State<TemplateMessageComposer> createState() =>
      _TemplateMessageComposerState();
}

class _TemplateMessageComposerState extends State<TemplateMessageComposer> {
  final _formKey = GlobalKey<FormState>();
  final _templates = <Map<String, dynamic>>[];
  final _inputs = <String, TextEditingController>{};
  final _values = <String, Object>{};
  Map<String, dynamic>? _selected;
  Map<String, dynamic>? _definition;
  Map<String, dynamic>? _preview;
  var _total = 0;
  var _loading = true;
  var _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  @override
  void dispose() {
    for (final input in _inputs.values) {
      input.dispose();
    }
    super.dispose();
  }

  Future<void> _loadMore() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.controller.loadUsableTemplates(
        skipCount: _templates.length,
      );
      if (!mounted) return;
      setState(() {
        _templates.addAll(
          (result['items'] as List).map(
            (item) => Map<String, dynamic>.from(item as Map),
          ),
        );
        _total = (result['totalCount'] as num).toInt();
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = '无法加载可用模板，请检查权限或稍后重试';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _select(Map<String, dynamic> template) async {
    setState(() {
      _loading = true;
      _error = null;
      _preview = null;
      _definition = null;
    });
    try {
      final version = (template['publishedVersion'] as num).toInt();
      final revision = await widget.controller.loadTemplateRevision(
        template['id'].toString(),
        version,
      );
      if (!mounted) return;
      final definition =
          jsonDecode(revision['definitionJson'] as String)
              as Map<String, dynamic>;
      if (definition['schemaVersion'] != 1 || definition['fields'] is! List) {
        throw const FormatException('Unsupported definition');
      }
      if ((definition['fields'] as List).length > 30) {
        throw const FormatException('Too many fields');
      }
      for (final input in _inputs.values) {
        input.dispose();
      }
      _inputs.clear();
      _values.clear();
      for (final raw in definition['fields'] as List) {
        final field = raw as Map;
        final name = field['name'] as String;
        if (!{
          'string',
          'integer',
          'number',
          'boolean',
        }.contains(field['type'])) {
          throw const FormatException('Unsupported field');
        }
        _inputs[name] = TextEditingController();
      }
      setState(() {
        _selected = template;
        _definition = definition;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = '无法读取该模板版本，请重新选择';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Map<String, dynamic> _data() {
    final data = <String, dynamic>{};
    for (final raw in _definition!['fields'] as List) {
      final field = raw as Map;
      final name = field['name'] as String;
      final value = _inputs[name]?.text.trim() ?? '';
      if (field['type'] == 'boolean' || field['enum'] is List) {
        if (_values[name] != null) data[name] = _values[name];
      } else if (value.isNotEmpty) {
        data[name] =
            field['type'] == 'integer'
                ? int.parse(value)
                : field['type'] == 'number'
                ? num.parse(value)
                : value;
      }
    }
    return data;
  }

  Map<String, dynamic>? _buildPreview() {
    if (_formKey.currentState?.validate() != true) return null;
    final data = _data();
    final summary = _definition!['summary'] as Map? ?? {};
    final keys = summary['fields'] as List? ?? [];
    final text = keys
        .where((name) => data[name] != null)
        .map(
          (name) =>
              data[name] is bool
                  ? (data[name] == true ? '是' : '否')
                  : '${data[name]}',
        )
        .join(summary['separator'] as String? ?? '：');
    final snapshot = <String, dynamic>{
      'schemaVersion': 1,
      'templateId': _selected!['id'],
      'templateVersion': _selected!['publishedVersion'],
      'templateName': _selected!['name'],
      'fallbackText': templateFallbackText('${summary['prefix'] ?? ''}$text'),
      'data': data,
      'layout': _definition!['layout'],
      'actions': _definition!['actions'] ?? [],
      if (_definition!['resources'] != null)
        'resources': _definition!['resources'],
    };
    if (!TemplateSnapshot.parse(snapshot).valid) {
      setState(() {
        _error = '模板内容暂不受支持或数据不符合要求';
      });
      return null;
    }
    setState(() {
      _preview = snapshot;
      _error = null;
    });
    return snapshot;
  }

  Future<void> _send() async {
    final snapshot = _buildPreview();
    if (snapshot == null) return;
    setState(() {
      _sending = true;
    });
    try {
      await widget.controller.sendTemplate({
        'templateId': _selected!['id'],
        'templateVersion': _selected!['publishedVersion'],
        'data': snapshot['data'],
      }, snapshot);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = '暂时无法发送，请稍后重试';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  Widget _field(Map field) {
    final name = field['name'] as String;
    final required = field['required'] == true;
    final label = '$name${required ? ' *' : ''}';
    final options =
        field['type'] == 'boolean'
            ? <Object>[true, false]
            : field['enum'] is List
            ? List<Object>.from(field['enum'] as List)
            : null;
    if (options != null) {
      return DropdownButtonFormField<Object>(
        decoration: InputDecoration(labelText: label),
        items: [
          for (final value in options)
            DropdownMenuItem(
              value: value,
              child: Text(value is bool ? (value ? '是' : '否') : '$value'),
            ),
        ],
        onChanged:
            _sending
                ? null
                : (value) {
                  setState(() {
                    if (value == null) {
                      _values.remove(name);
                    } else {
                      _values[name] = value;
                    }
                    _preview = null;
                  });
                },
        validator: (value) => required && value == null ? '请选择$label' : null,
      );
    }
    return TextFormField(
      controller: _inputs[name],
      enabled: !_sending,
      decoration: InputDecoration(labelText: label),
      maxLength: (field['maxLength'] as num?)?.toInt().clamp(1, 2000) ?? 2000,
      keyboardType:
          field['type'] == 'string'
              ? TextInputType.text
              : const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
      onChanged: (_) {
        if (_preview != null) {
          setState(() {
            _preview = null;
          });
        }
      },
      validator: (raw) {
        final value = raw?.trim() ?? '';
        if (value.isEmpty) return required ? '请填写$label' : null;
        if (field['type'] == 'number' || field['type'] == 'integer') {
          final number = num.tryParse(value);
          if (number == null ||
              !number.isFinite ||
              number.abs() > 9007199254740991 ||
              (field['type'] == 'integer' && int.tryParse(value) == null)) {
            return '请输入有效数字';
          }
        }
        if (field['format'] == 'url' && !isSafeHttpUrl(value)) {
          return '请输入安全的网页地址';
        }
        return null;
      },
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      _selected == null
          ? '选择消息模板'
          : '${_selected!['name']} · v${_selected!['publishedVersion']}',
    ),
    content: SizedBox(
      width: 400,
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_loading) const Center(child: CircularProgressIndicator()),
              if (_definition == null && !_loading) ...[
                for (final template in _templates)
                  ListTile(
                    title: Text('${template['name']}'),
                    subtitle: Text('版本 ${template['publishedVersion']}'),
                    onTap: () => _select(template),
                  ),
                if (_templates.isEmpty && _error == null) const Text('暂无可用模板'),
                if (_templates.length < _total)
                  TextButton(onPressed: _loadMore, child: const Text('加载更多')),
                if (_error != null)
                  TextButton(onPressed: _loadMore, child: const Text('重试')),
              ],
              if (_definition != null && !_loading) ...[
                for (final raw in _definition!['fields'] as List)
                  _field(raw as Map),
                if (_preview != null)
                  TemplateMessageContent(
                    key: ValueKey(_preview),
                    presentation: ChatMessagePresentation.quote,
                    message: ChatMessage.fromJson(
                      {'id': 0, 'messageType': 13, 'content': _preview},
                      ownerId: widget.controller.ownerId,
                      sessionUnitId: widget.controller.sessionUnitId,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _sending ? null : () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      if (_definition != null && !_loading) ...[
        TextButton(
          onPressed: _sending ? null : _buildPreview,
          child: const Text('预览摘要'),
        ),
        FilledButton(
          onPressed: _sending ? null : _send,
          child: Text(_sending ? '发送中' : '发送'),
        ),
      ],
    ],
  );
}
