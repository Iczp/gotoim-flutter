import 'dart:convert';

/// 自定义模板消息协议规范 (v1) 常量
const int templateSchemaVersion = 1;
const int maxTemplateNodes = 50;
const int maxTemplateDepth = 6;
const int maxActions = 3;
const int maxStaticTextLength = 1000;
const int maxFieldTextLength = 2000;
const int maxFallbackTextLength = 256;

const Set<String> allowedNodeTypes = {
  'card',
  'column',
  'row',
  'text',
  'field',
  'badge',
  'image',
  'divider',
  'button',
};

/// 检查是否为合法的 HTTP/HTTPS 链接
bool isSafeHttpUrl(String? url) {
  if (url == null || url.trim().isEmpty) return false;
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return false;
  return (uri.scheme.toLowerCase() == 'http' ||
          uri.scheme.toLowerCase() == 'https') &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      !url.contains(RegExp(r'[\x00-\x20\x7f\\]'));
}

/// 动作定义
class TemplateAction {
  const TemplateAction({
    required this.id,
    required this.type,
    required this.bind,
  });

  final String id;
  final String type;
  final String bind;

  factory TemplateAction.fromJson(Map<String, dynamic> json) => TemplateAction(
    id: (json['id'] ?? '').toString().trim(),
    type: (json['type'] ?? '').toString().trim(),
    bind: (json['bind'] ?? '').toString().trim(),
  );
}

/// 基础模板节点
abstract class TemplateNode {
  const TemplateNode(this.type);
  final String type;
}

class CardNode extends TemplateNode {
  const CardNode({required this.children}) : super('card');
  final List<TemplateNode> children;
}

class ColumnNode extends TemplateNode {
  const ColumnNode({required this.children, this.gap}) : super('column');
  final List<TemplateNode> children;
  final String? gap;
}

class RowNode extends TemplateNode {
  const RowNode({required this.children, this.gap}) : super('row');
  final List<TemplateNode> children;
  final String? gap;
}

class TextNode extends TemplateNode {
  const TextNode({this.text, this.bind, this.style = 'body'}) : super('text');
  final String? text;
  final String? bind;
  final String style;
}

class FieldNode extends TemplateNode {
  const FieldNode({required this.label, required this.bind}) : super('field');
  final String label;
  final String bind;
}

class BadgeNode extends TemplateNode {
  const BadgeNode({this.text, this.bind, this.tone = 'neutral'})
    : super('badge');
  final String? text;
  final String? bind;
  final String tone;
}

class ImageNode extends TemplateNode {
  const ImageNode({this.resourceId, this.bind, this.aspectRatio = 'landscape'})
    : super('image');
  final String? resourceId;
  final String? bind;
  final String aspectRatio;
}

class DividerNode extends TemplateNode {
  const DividerNode() : super('divider');
}

class ButtonNode extends TemplateNode {
  const ButtonNode({required this.label, required this.actionId})
    : super('button');
  final String label;
  final String actionId;
}

/// 解析与校验结果
class ParsedTemplateResult {
  const ParsedTemplateResult({
    required this.valid,
    required this.fallbackText,
    this.snapshot,
    this.errorReason,
  });

  final bool valid;
  final String fallbackText;
  final TemplateSnapshot? snapshot;
  final String? errorReason;
}

/// 模板快照结构
class TemplateSnapshot {
  const TemplateSnapshot({
    required this.schemaVersion,
    required this.templateId,
    required this.templateVersion,
    this.templateName,
    this.fallbackText,
    required this.data,
    required this.layout,
    this.actions = const [],
    this.resources,
  });

  final int schemaVersion;
  final String templateId;
  final int templateVersion;
  final String? templateName;
  final String? fallbackText;
  final Map<String, dynamic> data;
  final CardNode layout;
  final List<TemplateAction> actions;
  final Map<String, String>? resources;

  static ParsedTemplateResult parse(Object? input) {
    var fallback = '[模板消息] 内容暂不可用';
    try {
      if (input is String) {
        if (utf8.encode(input).length > 65536) {
          return _invalid(fallback, 'payload_too_large');
        }
        try {
          input = jsonDecode(input);
        } on FormatException {
          return _invalid(fallback, 'corrupted_json');
        }
      }
      var obj = _object(input);
      // Fixture envelopes are unwrapped here; production content is the snapshot.
      if (obj['schemaVersion'] == null && obj['snapshot'] is Map) {
        obj = _object(obj['snapshot']);
      }
      fallback = templateFallbackText(obj['fallbackText']);
      if (utf8.encode(jsonEncode(obj)).length > 65536) {
        return _invalid(fallback, 'payload_too_large');
      }
      if (obj['schemaVersion'] != templateSchemaVersion) {
        return _invalid(fallback, 'unsupported_schema_version');
      }
      _check(obj['schemaVersion'] is int, 'invalid_schema_version');
      _check(
        obj['templateId'] is String &&
            RegExp(
              r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
            ).hasMatch(obj['templateId'] as String),
        'invalid_template_id',
      );
      _check(
        obj['templateVersion'] is int && (obj['templateVersion'] as int) > 0,
        'invalid_template_version',
      );
      if (obj['templateName'] != null) _text(obj['templateName'], 80);
      if (obj['fallbackText'] != null) {
        _text(obj['fallbackText'], maxFallbackTextLength);
      }
      final data = _object(obj['data']);
      _check(data.length <= 30, 'too_many_fields');
      for (final entry in data.entries) {
        _check(_binding(entry.key), 'invalid_field_name');
        final value = entry.value;
        _check(
          value is String || value is bool || value is num,
          'invalid_field_value',
        );
        if (value is String) _text(value, maxFieldTextLength);
        if (value is num) {
          _check(
            value.isFinite && value.abs() <= 9007199254740991,
            'invalid_numeric_value',
          );
        }
      }
      // Blob references remain closed until authorized resource retention is supported.
      final resources = obj['resources'];
      _check(
        resources == null || (resources is List && resources.isEmpty),
        'unsupported_resources',
      );
      final rawActions = obj['actions'] ?? <Object?>[];
      _check(
        rawActions is List && rawActions.length <= maxActions,
        'exceeded_max_actions',
      );
      final actions = <TemplateAction>[];
      final actionIds = <String>{};
      for (final rawAction in rawActions as List) {
        final action = _object(rawAction);
        _attributes(action, {'id', 'type', 'bind'});
        final id = _text(action['id'], 64, required: true);
        _check(actionIds.add(id), 'invalid_action_id');
        _check(
          action['type'] == 'openUrl' || action['type'] == 'copyText',
          'unknown_action_type',
        );
        final bind = _text(action['bind'], 64, required: true);
        _check(_binding(bind), 'invalid_binding');
        final value = data[bind];
        _check(value == null || value is String, 'invalid_action_value');
        if (action['type'] == 'openUrl' && value != null && value != '') {
          _check(isSafeHttpUrl(value as String), 'unsafe_url');
        }
        actions.add(
          TemplateAction(id: id, type: action['type'] as String, bind: bind),
        );
      }
      final layout = _object(obj['layout']);
      _check(layout['type'] == 'card', 'root_node_must_be_card');
      final layoutNode = _buildNode(layout, 1, _NodeCounter(), data, actionIds);
      final snapshot = TemplateSnapshot(
        schemaVersion: templateSchemaVersion,
        templateId: obj['templateId'] as String,
        templateVersion: obj['templateVersion'] as int,
        templateName: obj['templateName'] as String?,
        fallbackText: fallback,
        data: Map<String, dynamic>.unmodifiable(data),
        layout: layoutNode as CardNode,
        actions: List<TemplateAction>.unmodifiable(actions),
      );
      return ParsedTemplateResult(
        valid: true,
        fallbackText: fallback,
        snapshot: snapshot,
      );
    } on FormatException catch (error) {
      return _invalid(fallback, error.message);
    } catch (_) {
      return _invalid(fallback, 'corrupted_payload');
    }
  }
}

ParsedTemplateResult _invalid(String fallback, String reason) =>
    ParsedTemplateResult(
      valid: false,
      fallbackText: fallback,
      errorReason: reason,
    );

/// Summary data is untrusted even when a future protocol cannot be rendered.
String templateFallbackText(Object? value) {
  if (value is! String || value.trim().isEmpty) return '[模板消息] 内容暂不可用';
  return value
      .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ')
      .trim()
      .runes
      .take(maxFallbackTextLength)
      .fold<String>('', (text, rune) => text + String.fromCharCode(rune));
}

void _check(bool condition, String reason) {
  if (!condition) throw FormatException(reason);
}

Map<String, dynamic> _object(Object? value) {
  _check(value is Map, 'invalid_object');
  final map = value as Map;
  _check(map.keys.every((key) => key is String), 'invalid_object_key');
  return Map<String, dynamic>.from(map);
}

String _text(Object? value, int maxLength, {bool required = false}) {
  _check(value is String, 'invalid_string');
  final text = value as String;
  _check(text.length <= maxLength, 'static_text_too_long');
  _check(!required || text.trim().isNotEmpty, 'missing_required_string');
  return text;
}

bool _binding(String bind) =>
    RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]{0,63}$').hasMatch(bind) &&
    !{'__proto__', 'prototype', 'constructor'}.contains(bind);

void _attributes(Map<String, dynamic> map, Set<String> allowed) {
  _check(map.keys.every(allowed.contains), 'unknown_attribute');
}

class _NodeCounter {
  int count = 0;
  int images = 0;
}

TemplateNode _buildNode(
  Map<String, dynamic> map,
  int depth,
  _NodeCounter counter,
  Map<String, dynamic> data,
  Set<String> actionIds,
) {
  _check(depth <= maxTemplateDepth, 'exceeded_max_depth');
  _check(++counter.count <= maxTemplateNodes, 'exceeded_max_nodes');
  final type = map['type'];
  _check(
    type is String && allowedNodeTypes.contains(type),
    'unknown_component_$type',
  );
  final attributes = <String, Set<String>>{
    'card': {'type', 'children'},
    'column': {'type', 'children', 'gap'},
    'row': {'type', 'children', 'gap'},
    'text': {'type', 'text', 'bind', 'style'},
    'field': {'type', 'label', 'bind'},
    'badge': {'type', 'text', 'bind', 'tone'},
    'image': {'type', 'resourceId', 'bind', 'aspectRatio'},
    'divider': {'type'},
    'button': {'type', 'label', 'actionId'},
  };
  _attributes(map, attributes[type]!);
  String binding() {
    final bind = _text(map['bind'], 64, required: true);
    _check(_binding(bind), 'invalid_binding');
    return bind;
  }

  String choice(String key, Set<String> options, String defaultValue) {
    final value = map[key] ?? defaultValue;
    _check(value is String && options.contains(value), 'invalid_$key');
    return value as String;
  }

  if (type == 'card' || type == 'column' || type == 'row') {
    _check(type != 'card' || depth == 1, 'nested_card_forbidden');
    final rawChildren = map['children'];
    _check(rawChildren is List, 'invalid_children');
    _check(
      type != 'row' || (rawChildren as List).length <= 3,
      'row_children_exceeded',
    );
    final children = (rawChildren as List)
        .map(
          (child) =>
              _buildNode(_object(child), depth + 1, counter, data, actionIds),
        )
        .toList(growable: false);
    if (type == 'card') return CardNode(children: children);
    final gap = choice('gap', {'small', 'medium', 'large'}, 'medium');
    return type == 'column'
        ? ColumnNode(children: children, gap: gap)
        : RowNode(children: children, gap: gap);
  }
  if (type == 'text' || type == 'badge') {
    _check(
      map.containsKey('text') != map.containsKey('bind'),
      'invalid_text_binding',
    );
    final text =
        map.containsKey('text')
            ? _text(map['text'], maxStaticTextLength)
            : null;
    final bind = map.containsKey('bind') ? binding() : null;
    return type == 'text'
        ? TextNode(
          text: text,
          bind: bind,
          style: choice('style', {'heading', 'body', 'secondary'}, 'body'),
        )
        : BadgeNode(
          text: text,
          bind: bind,
          tone: choice('tone', {
            'neutral',
            'success',
            'warning',
            'danger',
          }, 'neutral'),
        );
  }
  if (type == 'field') {
    return FieldNode(
      label: _text(map['label'], maxStaticTextLength),
      bind: binding(),
    );
  }
  if (type == 'image') {
    _check(++counter.images <= 3, 'too_many_images');
    _check(!map.containsKey('resourceId'), 'unsupported_resources');
    final bind = binding();
    final value = data[bind];
    _check(
      value == null || value == '' || (value is String && isSafeHttpUrl(value)),
      'unsafe_url',
    );
    return ImageNode(
      bind: bind,
      aspectRatio: choice('aspectRatio', {
        'square',
        'landscape',
        'portrait',
      }, 'landscape'),
    );
  }
  if (type == 'button') {
    final actionId = _text(map['actionId'], 64, required: true);
    _check(actionIds.contains(actionId), 'unknown_action_reference');
    return ButtonNode(
      label: _text(map['label'], maxStaticTextLength, required: true),
      actionId: actionId,
    );
  }
  return const DividerNode();
}
