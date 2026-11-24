import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// 正则表达式：匹配 `<a uid="...">`、`<a oid="...">`、`<a href="...">` 或通用 `<a>text</a>` 等标签。
final RegExp _kMessageTagRegex = RegExp(
  r'''<a(?:\s+uid=["']([^"']+)["']|\s+oid=["']([^"']+)["']|\s+href=["']([^"']+)["']|[^>]*)>([\s\S]*?)</a>''',
  caseSensitive: false,
);

const List<String> kDefaultAppLinkSchemes = ['im', 'app'];
List<String> _configuredAppLinkSchemes = List<String>.from(kDefaultAppLinkSchemes);

/// 配置应用内自定义协议 Scheme（默认 `['im', 'app']`）
void configureAppLinkSchemes(List<String> schemes) {
  final cleaned = schemes
      .map((s) => s.trim().toLowerCase())
      .where((s) => s.isNotEmpty)
      .toSet()
      .toList();
  if (cleaned.isNotEmpty) {
    _configuredAppLinkSchemes = cleaned;
  }
}

List<String> get appLinkSchemes => List.unmodifiable(_configuredAppLinkSchemes);

String _unescapeHtmlEntities(String raw) {
  if (raw.isEmpty || !raw.contains('&')) return raw;
  return raw
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}

class AppLinkUri {
  const AppLinkUri({
    required this.scheme,
    required this.route,
    required this.params,
    required this.id,
  });

  final String scheme;
  final String route;
  final Map<String, String> params;
  final String id;
}

AppLinkUri? parseAppLinkUri(String rawHref, {List<String>? schemes}) {
  final trimmed = rawHref.trim();
  final match = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*):\/\/(.*)$').firstMatch(trimmed);
  if (match == null) return null;

  final scheme = match.group(1)!.toLowerCase();
  final allowed = schemes ?? _configuredAppLinkSchemes;
  if (!allowed.contains(scheme)) return null;

  final rest = match.group(2) ?? '';
  final qIndex = rest.indexOf('?');
  final pathPart = (qIndex >= 0 ? rest.substring(0, qIndex) : rest)
      .replaceAll(RegExp(r'^/+'), '')
      .replaceAll(RegExp(r'/+$'), '');
  final queryPart = qIndex >= 0 ? rest.substring(qIndex + 1) : '';

  final params = <String, String>{};
  if (queryPart.isNotEmpty) {
    for (final pair in queryPart.split('&')) {
      if (pair.isEmpty) continue;
      final eqIdx = pair.indexOf('=');
      if (eqIdx >= 0) {
        final k = Uri.decodeComponent(pair.substring(0, eqIdx));
        final v = Uri.decodeComponent(pair.substring(eqIdx + 1));
        if (k.isNotEmpty) params[k] = v;
      } else {
        final k = Uri.decodeComponent(pair);
        if (k.isNotEmpty) params[k] = '';
      }
    }
  }

  var route = pathPart.toLowerCase();
  if (route == 'pages/im/announcement') {
    route = 'announcement';
  }
  final id = params['id'] ?? '';
  return AppLinkUri(scheme: scheme, route: route, params: params, id: id);
}

/// 剥离消息中的 HTML/自定义标签（如 `<a href="im://...">用户</a>`、`<a uid="...">用户</a>` 等），返回纯文本。
///
/// 同时规范化空白字符：将换行符替换为单个空格或指定分隔符，以便单行摘要展示。
String stripMessageTags(
  String? input, {
  bool replaceNewlines = true,
  String newlineReplacement = ' ',
}) {
  if (input == null || input.isEmpty) return '';

  var text = input.replaceAllMapped(_kMessageTagRegex, (match) {
    final inner = match.group(4);
    return _unescapeHtmlEntities(inner ?? '');
  });

  // 处理可能残留的简单 html 标签，如 <b>、<span> 等
  text = text.replaceAll(RegExp(r'</?[^>]+(>|$)'), '');

  if (replaceNewlines) {
    text = text.replaceAll(RegExp(r'[\r\n]+'), newlineReplacement);
  }

  return text.trim();
}

/// 描述标签解析出的文本分段类型。
enum MessageTagType { text, sessionUnit, chatObject, appLink, link, genericLink }

/// 结构化标签解析结果项。
class MessageTagNode {
  const MessageTagNode({
    required this.type,
    required this.text,
    this.value,
    this.href,
    this.scheme,
    this.route,
    this.params,
  });

  final MessageTagType type;
  final String text;
  final String? value;
  final String? href;
  final String? scheme;
  final String? route;
  final Map<String, String>? params;
}

/// 将包含特定标签的消息字符串解析为结构化节点列表。
List<MessageTagNode> parseMessageTagNodes(String? input) {
  if (input == null || input.isEmpty) return const [];

  final nodes = <MessageTagNode>[];
  var lastIndex = 0;

  for (final match in _kMessageTagRegex.allMatches(input)) {
    if (match.start > lastIndex) {
      nodes.add(MessageTagNode(
        type: MessageTagType.text,
        text: input.substring(lastIndex, match.start),
      ));
    }

    final uid = match.group(1);
    final oid = match.group(2);
    final rawHref = match.group(3);
    final innerText = _unescapeHtmlEntities(match.group(4) ?? '');

    if (uid != null && uid.isNotEmpty) {
      nodes.add(MessageTagNode(
        type: MessageTagType.sessionUnit,
        text: innerText,
        value: uid,
      ));
    } else if (oid != null && oid.isNotEmpty) {
      nodes.add(MessageTagNode(
        type: MessageTagType.chatObject,
        text: innerText,
        value: oid,
      ));
    } else if (rawHref != null && rawHref.isNotEmpty) {
      final href = _unescapeHtmlEntities(rawHref);
      final appLink = parseAppLinkUri(href);
      if (appLink != null) {
        if (appLink.route == 'session-unit') {
          nodes.add(MessageTagNode(
            type: MessageTagType.sessionUnit,
            text: innerText,
            value: appLink.id,
            href: href,
            scheme: appLink.scheme,
            route: appLink.route,
            params: appLink.params,
          ));
        } else if (appLink.route == 'chat-object') {
          nodes.add(MessageTagNode(
            type: MessageTagType.chatObject,
            text: innerText,
            value: appLink.id,
            href: href,
            scheme: appLink.scheme,
            route: appLink.route,
            params: appLink.params,
          ));
        } else {
          nodes.add(MessageTagNode(
            type: MessageTagType.appLink,
            text: innerText,
            value: appLink.id,
            href: href,
            scheme: appLink.scheme,
            route: appLink.route,
            params: appLink.params,
          ));
        }
      } else {
        nodes.add(MessageTagNode(
          type: MessageTagType.link,
          text: innerText.isEmpty ? href : innerText,
          href: href,
          value: href,
        ));
      }
    } else {
      nodes.add(MessageTagNode(
        type: MessageTagType.genericLink,
        text: innerText,
      ));
    }

    lastIndex = match.end;
  }

  if (lastIndex < input.length) {
    nodes.add(MessageTagNode(
      type: MessageTagType.text,
      text: input.substring(lastIndex),
    ));
  }

  return nodes;
}

/// 将包含标签的消息文本解析为可在界面展示的 [InlineSpan] 列表。
List<InlineSpan> parseMessageTagsToSpans(
  String? input, {
  required TextStyle textStyle,
  required TextStyle linkStyle,
  void Function(String uid, String name)? onSessionUnitTap,
  void Function(String oid, String name)? onChatObjectTap,
  void Function(MessageTagNode node)? onAppLinkTap,
  void Function(String url)? onExternalLinkTap,
}) {
  final nodes = parseMessageTagNodes(input);
  final spans = <InlineSpan>[];

  for (final node in nodes) {
    switch (node.type) {
      case MessageTagType.sessionUnit:
        final uid = node.value ?? '';
        spans.add(TextSpan(
          text: node.text,
          style: linkStyle,
          recognizer: (onSessionUnitTap != null)
              ? (TapGestureRecognizer()..onTap = () => onSessionUnitTap(uid, node.text))
              : null,
        ));
      case MessageTagType.chatObject:
        final oid = node.value ?? '';
        spans.add(TextSpan(
          text: node.text,
          style: linkStyle,
          recognizer: (onChatObjectTap != null)
              ? (TapGestureRecognizer()..onTap = () => onChatObjectTap(oid, node.text))
              : null,
        ));
      case MessageTagType.appLink:
        spans.add(TextSpan(
          text: node.text,
          style: linkStyle,
          recognizer: (onAppLinkTap != null)
              ? (TapGestureRecognizer()..onTap = () => onAppLinkTap(node))
              : null,
        ));
      case MessageTagType.link:
        final url = node.href ?? node.value ?? '';
        spans.add(TextSpan(
          text: node.text,
          style: linkStyle,
          recognizer: (onExternalLinkTap != null && url.isNotEmpty)
              ? (TapGestureRecognizer()..onTap = () => onExternalLinkTap(url))
              : null,
        ));
      case MessageTagType.genericLink:
      case MessageTagType.text:
        spans.add(TextSpan(
          text: node.text,
          style: node.type == MessageTagType.genericLink ? linkStyle : textStyle,
        ));
    }
  }

  return spans;
}
