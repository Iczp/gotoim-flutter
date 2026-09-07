import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// 正则表达式：匹配 `<a uid="...">text</a>`、`<a oid="...">text</a>` 或通用 `<a>text</a>` 等标签。
final RegExp _kMessageTagRegex = RegExp(
  r'<a(?:\s+uid="([^"]+)"|\s+oid="([^"]+)"|[^>]*)>([^<]*)</a>',
  caseSensitive: false,
);

/// 剥离消息中的 HTML/自定义标签（如 `<a uid="...">用户</a>`、`<a>user</a>` 等），返回纯文本。
///
/// 同时规范化空白字符：将换行符替换为单个空格或指定分隔符，以便单行摘要展示。
String stripMessageTags(
  String? input, {
  bool replaceNewlines = true,
  String newlineReplacement = ' ',
}) {
  if (input == null || input.isEmpty) return '';

  var text = input.replaceAllMapped(_kMessageTagRegex, (match) {
    // 匹配标签内的文本内容 (group 3 是内部文字)
    final inner = match.group(3);
    return inner ?? '';
  });

  // 处理可能残留的简单 html 标签，如 <b>、<span> 等
  text = text.replaceAll(RegExp(r'</?[^>]+(>|$)'), '');

  if (replaceNewlines) {
    text = text.replaceAll(RegExp(r'[\r\n]+'), newlineReplacement);
  }

  return text.trim();
}

/// 描述标签解析出的文本分段类型。
enum MessageTagType { text, sessionUnit, chatObject, genericLink }

/// 结构化标签解析结果项。
class MessageTagNode {
  const MessageTagNode({
    required this.type,
    required this.text,
    this.value,
  });

  final MessageTagType type;
  final String text;
  final String? value;
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
    final innerText = match.group(3) ?? '';

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
