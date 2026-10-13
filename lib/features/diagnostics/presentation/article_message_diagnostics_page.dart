import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../chat/data/models/chat_message.dart';
import '../../chat/presentation/message_content/article_message_content.dart';

class ArticleMessageDiagnosticsPage extends StatefulWidget {
  const ArticleMessageDiagnosticsPage({super.key});
  @override
  State<ArticleMessageDiagnosticsPage> createState() =>
      _ArticleMessageDiagnosticsPageState();
}

class _ArticleMessageDiagnosticsPageState
    extends State<ArticleMessageDiagnosticsPage> {
  static const _sample =
      '''{"items":[{"title":"头条文章","description":"可编辑 JSON，验证单篇和多篇卡片。","originalUrl":"https://example.com/article-1"},{"title":"第二篇文章","originalUrl":"https://example.com/article-2"}]}''';
  final _input = TextEditingController(text: _sample);
  ChatMessage? _message;
  String _result = '尚未执行';
  bool _running = false;
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _run() {
    setState(() {
      _running = true;
      _result = '正在解析';
    });
    final timer = Stopwatch()..start();
    try {
      final content = jsonDecode(_input.text);
      if (content is! Map && content is! List) {
        throw const FormatException('内容必须为对象或数组');
      }
      final message = ChatMessage.fromJson(
        {'id': 1, 'messageType': 11, 'content': content},
        ownerId: 1,
        sessionUnitId: 'diagnostics',
      );
      if (message.articleItems.isEmpty) {
        throw const FormatException('未找到可展示的文章');
      }
      setState(() {
        _message = message;
        _result =
            '成功：${message.articleItems.length} 篇，耗时 ${timer.elapsedMicroseconds} μs\n${const JsonEncoder.withIndent('  ').convert(message.articleItems.map((e) => e.toJson()).toList())}';
      });
    } catch (error) {
      setState(() {
        _message = null;
        _result = '失败：$error';
      });
    } finally {
      setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(body: Center(child: Text('开发诊断仅在 Debug 模式可用。')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('文章消息诊断')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _input,
            minLines: 5,
            maxLines: 12,
            decoration: const InputDecoration(
              labelText: '文章内容 JSON',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: _running ? null : _run,
                child: const Text('执行解析与预览'),
              ),
              OutlinedButton(
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: _result)),
                child: const Text('复制结果'),
              ),
              OutlinedButton(
                onPressed: () {
                  _input.text = _sample;
                  setState(() {
                    _message = null;
                    _result = '尚未执行';
                  });
                },
                child: const Text('重置'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SelectableText(_result),
          if (_message != null) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: ArticleMessageContent(message: _message!, maxWidth: 320),
            ),
          ],
        ],
      ),
    );
  }
}
