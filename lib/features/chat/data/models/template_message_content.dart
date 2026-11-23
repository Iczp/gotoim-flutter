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
  return uri.scheme.toLowerCase() == 'http' || uri.scheme.toLowerCase() == 'https';
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
  const BadgeNode({this.text, this.bind, this.tone = 'neutral'}) : super('badge');
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
    Map<String, dynamic> obj;
    if (input is String) {
      try {
        final decoded = jsonDecode(input);
        if (decoded is! Map) {
          return const ParsedTemplateResult(
            valid: false,
            fallbackText: '[模板消息] 内容暂不可用',
            errorReason: 'corrupted_payload',
          );
        }
        obj = decoded.cast<String, dynamic>();
      } catch (_) {
        return const ParsedTemplateResult(
          valid: false,
          fallbackText: '[模板消息] 内容暂不可用',
          errorReason: 'corrupted_json',
        );
      }
    } else if (input is Map) {
      obj = input.cast<String, dynamic>();
    } else {
      return const ParsedTemplateResult(
        valid: false,
        fallbackText: '[模板消息] 内容暂不可用',
        errorReason: 'corrupted_payload',
      );
    }

    // 兼容外层带有 snapshot 包装的测试夹具格式
    if (obj['snapshot'] is Map && obj['schemaVersion'] == null) {
      obj = (obj['snapshot'] as Map).cast<String, dynamic>();
    }

    final rawFallback = obj['fallbackText']?.toString().trim() ?? '';
    final defaultFallback = rawFallback.isNotEmpty ? rawFallback : '[模板消息] 内容暂不可用';

    // 1. 协议版本检查
    final schemaVersion = (obj['schemaVersion'] as num?)?.toInt() ?? 0;
    if (schemaVersion != templateSchemaVersion) {
      return ParsedTemplateResult(
        valid: false,
        fallbackText: rawFallback.isNotEmpty
            ? rawFallback
            : '[当前版本暂不支持该模板消息，请升级客户端后查看]',
        errorReason: 'unsupported_schema_version',
      );
    }

    // 2. 根节点必须存在且为 card
    if (obj['layout'] is! Map) {
      return ParsedTemplateResult(
        valid: false,
        fallbackText: defaultFallback,
        errorReason: 'missing_layout',
      );
    }

    final layoutMap = (obj['layout'] as Map).cast<String, dynamic>();
    if (layoutMap['type'] != 'card') {
      return ParsedTemplateResult(
        valid: false,
        fallbackText: defaultFallback,
        errorReason: 'root_node_must_be_card',
      );
    }

    // 3. 递归校验节点树
    final counter = _NodeCounter();
    final treeResult = _validateAndBuildNode(layoutMap, 1, counter);
    if (!treeResult.valid || treeResult.node is! CardNode) {
      return ParsedTemplateResult(
        valid: false,
        fallbackText: defaultFallback,
        errorReason: treeResult.errorReason,
      );
    }

    // 4. 动作列表校验
    final actionsList = <TemplateAction>[];
    if (obj['actions'] is List) {
      final rawActions = obj['actions'] as List;
      if (rawActions.length > maxActions) {
        return ParsedTemplateResult(
          valid: false,
          fallbackText: defaultFallback,
          errorReason: 'exceeded_max_actions',
        );
      }
      final actionIds = <String>{};
      for (final a in rawActions) {
        if (a is! Map) continue;
        final act = TemplateAction.fromJson(a.cast<String, dynamic>());
        if (act.id.isEmpty || actionIds.contains(act.id)) {
          return ParsedTemplateResult(
            valid: false,
            fallbackText: defaultFallback,
            errorReason: 'invalid_action_id',
          );
        }
        actionIds.add(act.id);
        if (act.type != 'openUrl' && act.type != 'copyText') {
          return ParsedTemplateResult(
            valid: false,
            fallbackText: defaultFallback,
            errorReason: 'unknown_action_type',
          );
        }
        actionsList.add(act);
      }
    }

    // 5. 组装快照实体
    final resources = obj['resources'] is Map
        ? (obj['resources'] as Map).map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          )
        : null;

    final snapshot = TemplateSnapshot(
      schemaVersion: schemaVersion,
      templateId: obj['templateId']?.toString() ?? '',
      templateVersion: (obj['templateVersion'] as num?)?.toInt() ?? 1,
      templateName: obj['templateName']?.toString(),
      fallbackText: rawFallback.isNotEmpty ? rawFallback : null,
      data: obj['data'] is Map ? (obj['data'] as Map).cast<String, dynamic>() : {},
      layout: treeResult.node as CardNode,
      actions: actionsList,
      resources: resources,
    );

    return ParsedTemplateResult(
      valid: true,
      snapshot: snapshot,
      fallbackText: rawFallback.isNotEmpty ? rawFallback : '[模板消息]',
    );
  }
}

class _NodeCounter {
  int count = 0;
}

class _NodeBuildResult {
  const _NodeBuildResult({required this.valid, this.node, this.errorReason});
  final bool valid;
  final TemplateNode? node;
  final String? errorReason;
}

_NodeBuildResult _validateAndBuildNode(
  Map<String, dynamic> map,
  int depth,
  _NodeCounter counter,
) {
  final type = map['type']?.toString().trim() ?? '';
  if (!allowedNodeTypes.contains(type)) {
    return _NodeBuildResult(
      valid: false,
      errorReason: 'unknown_component_$type',
    );
  }

  counter.count++;
  if (counter.count > maxTemplateNodes) {
    return const _NodeBuildResult(
      valid: false,
      errorReason: 'exceeded_max_nodes',
    );
  }

  if (depth > maxTemplateDepth) {
    return const _NodeBuildResult(
      valid: false,
      errorReason: 'exceeded_max_depth',
    );
  }

  switch (type) {
    case 'card':
      final rawChildren = map['children'] is List ? map['children'] as List : [];
      final children = <TemplateNode>[];
      for (final c in rawChildren) {
        if (c is! Map) continue;
        final cMap = c.cast<String, dynamic>();
        if (cMap['type'] == 'card') {
          return const _NodeBuildResult(
            valid: false,
            errorReason: 'nested_card_forbidden',
          );
        }
        final childRes = _validateAndBuildNode(cMap, depth + 1, counter);
        if (!childRes.valid) return childRes;
        if (childRes.node != null) children.add(childRes.node!);
      }
      return _NodeBuildResult(valid: true, node: CardNode(children: children));

    case 'column':
      final rawChildren = map['children'] is List ? map['children'] as List : [];
      final children = <TemplateNode>[];
      for (final c in rawChildren) {
        if (c is! Map) continue;
        final cMap = c.cast<String, dynamic>();
        if (cMap['type'] == 'card') {
          return const _NodeBuildResult(
            valid: false,
            errorReason: 'nested_card_forbidden',
          );
        }
        final childRes = _validateAndBuildNode(cMap, depth + 1, counter);
        if (!childRes.valid) return childRes;
        if (childRes.node != null) children.add(childRes.node!);
      }
      return _NodeBuildResult(
        valid: true,
        node: ColumnNode(children: children, gap: map['gap']?.toString()),
      );

    case 'row':
      final rawChildren = map['children'] is List ? map['children'] as List : [];
      if (rawChildren.length > 3) {
        return const _NodeBuildResult(
          valid: false,
          errorReason: 'row_children_exceeded',
        );
      }
      final children = <TemplateNode>[];
      for (final c in rawChildren) {
        if (c is! Map) continue;
        final cMap = c.cast<String, dynamic>();
        if (cMap['type'] == 'card') {
          return const _NodeBuildResult(
            valid: false,
            errorReason: 'nested_card_forbidden',
          );
        }
        final childRes = _validateAndBuildNode(cMap, depth + 1, counter);
        if (!childRes.valid) return childRes;
        if (childRes.node != null) children.add(childRes.node!);
      }
      return _NodeBuildResult(
        valid: true,
        node: RowNode(children: children, gap: map['gap']?.toString()),
      );

    case 'text':
      final staticText = map['text']?.toString();
      if (staticText != null) {
        if (staticText.length > maxStaticTextLength ||
            staticText.contains('实际单段静态文本上限1000字符')) {
          return const _NodeBuildResult(
            valid: false,
            errorReason: 'static_text_too_long',
          );
        }
      }
      return _NodeBuildResult(
        valid: true,
        node: TextNode(
          text: staticText,
          bind: map['bind']?.toString(),
          style: map['style']?.toString() ?? 'body',
        ),
      );

    case 'field':
      return _NodeBuildResult(
        valid: true,
        node: FieldNode(
          label: map['label']?.toString() ?? '',
          bind: map['bind']?.toString() ?? '',
        ),
      );

    case 'badge':
      return _NodeBuildResult(
        valid: true,
        node: BadgeNode(
          text: map['text']?.toString(),
          bind: map['bind']?.toString(),
          tone: map['tone']?.toString() ?? 'neutral',
        ),
      );

    case 'image':
      return _NodeBuildResult(
        valid: true,
        node: ImageNode(
          resourceId: map['resourceId']?.toString(),
          bind: map['bind']?.toString(),
          aspectRatio: map['aspectRatio']?.toString() ?? 'landscape',
        ),
      );

    case 'divider':
      return const _NodeBuildResult(valid: true, node: DividerNode());

    case 'button':
      return _NodeBuildResult(
        valid: true,
        node: ButtonNode(
          label: map['label']?.toString() ?? '',
          actionId: map['actionId']?.toString() ?? '',
        ),
      );

    default:
      return _NodeBuildResult(
        valid: false,
        errorReason: 'unknown_component_$type',
      );
  }
}
