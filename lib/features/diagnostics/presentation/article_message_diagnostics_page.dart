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
  /// 单图文用例（参考截图1: 央视新闻）
  static const _sampleSingle = '''{
  "items": [
    {
      "title": "这位快递小哥的“移动工位”，火了！",
      "description": "近日，一位快递小哥改装的整洁有序'移动工位'在网络走红，引得众多网友点赞转发。",
      "coverImageUrl": "https://picsum.photos/seed/cctv_express/800/450",
      "author": "央视新闻",
      "originalUrl": "https://news.cctv.com/article/express-post"
    }
  ]
}''';

  /// 多图文用例（参考截图2: 腾讯新闻）
  static const _sampleMulti = '''{
  "items": [
    {
      "title": "俄军反制不隔夜，火力全开击打日本工厂，现场化为一片火海",
      "coverImageUrl": "https://picsum.photos/seed/tencent_news1/800/450",
      "originalUrl": "https://news.qq.com/article/1"
    },
    {
      "title": "《庆余年》神预测：京都掀起鏖战，人质拿捏东宫",
      "description": "二皇子绝地反扑，范闲运筹帷幄，关键对峙一触即发。",
      "coverImageUrl": "https://picsum.photos/seed/tencent_news2/200/200",
      "originalUrl": "https://news.qq.com/article/2"
    },
    {
      "title": "山东小伙模仿“济公”爆火全网，长相、声音完美复刻，网友直呼太像了",
      "coverImageUrl": "https://picsum.photos/seed/tencent_news3/200/200",
      "originalUrl": "https://news.qq.com/article/3"
    },
    {
      "title": "女子裸身去民宿客厅竟发现有监控 向房东索赔3000 派出所不予立案",
      "coverImageUrl": "https://picsum.photos/seed/tencent_news4/200/200",
      "originalUrl": "https://news.qq.com/article/4"
    },
    {
      "title": "一张歼15D从福建舰电磁弹射起飞的图片在军迷圈刷屏了",
      "coverImageUrl": "https://picsum.photos/seed/tencent_news5/200/200",
      "originalUrl": "https://news.qq.com/article/5"
    }
  ]
}''';

  final _input = TextEditingController(text: _sampleMulti);
  ChatMessage? _message;
  String _result = '尚未执行';
  String _status = '未执行';
  int _elapsedMs = 0;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _run() {
    setState(() {
      _running = true;
      _status = '执行中';
      _result = '正在解析…';
    });
    final timer = Stopwatch()..start();
    try {
      final content = jsonDecode(_input.text);
      if (content is! Map && content is! List) {
        throw const FormatException('内容必须为对象或数组格式');
      }
      final message = ChatMessage.fromJson(
        {'id': 110, 'messageType': 11, 'content': content},
        ownerId: 1,
        sessionUnitId: 'diagnostics',
      );
      if (message.articleItems.isEmpty) {
        throw const FormatException('未找到可展示的文章（items 为空或缺少必要字段）');
      }
      timer.stop();
      final ms = timer.elapsedMicroseconds;
      setState(() {
        _message = message;
        _status = '成功';
        _elapsedMs = ms;
        _result =
            '解析成功：共 ${message.articleItems.length} 篇图文，耗时: $ms μs\n'
            '${const JsonEncoder.withIndent('  ').convert(message.articleItems.map((e) => e.toJson()).toList())}';
      });
    } catch (error, stack) {
      timer.stop();
      setState(() {
        _message = null;
        _status = '失败';
        _elapsedMs = timer.elapsedMicroseconds;
        _result = '解析失败：$error\n\nStackTrace:\n$stack';
      });
    } finally {
      setState(() => _running = false);
    }
  }

  void _loadPreset(String preset) {
    _input.text = preset;
    _run();
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(body: Center(child: Text('开发诊断仅在 Debug 模式可用。')));
    }
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('文章消息排版诊断')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 模块介绍卡片
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '微信公众号图文卡片排版规范',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '• 单图文：顶部 16:9 封面大图，底部白色标题独立区域（参考央视新闻）\n'
                    '• 多图文：首条封面大图底部半透渐变遮罩浮层标题，次条列表式左标题右缩略图（参考腾讯新闻）\n'
                    '• 支持平台：Android ✓  iOS ✓  iPad ✓  Windows ✓  macOS ✓  Linux ✓  Web ✓',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 快捷模板选择
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.newspaper, size: 16),
                label: const Text('载入多图文（腾讯新闻示例）'),
                onPressed: () => _loadPreset(_sampleMulti),
              ),
              ActionChip(
                avatar: const Icon(Icons.article_outlined, size: 16),
                label: const Text('载入单图文（央视新闻示例）'),
                onPressed: () => _loadPreset(_sampleSingle),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // JSON 输入框
          TextField(
            controller: _input,
            minLines: 6,
            maxLines: 14,
            decoration: const InputDecoration(
              labelText: '文章内容 JSON',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          // 操作按钮行
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.play_arrow, size: 18),
                onPressed: _running ? null : _run,
                label: const Text('执行解析与渲染'),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _result));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已复制诊断结果到剪贴板')),
                  );
                },
                label: const Text('复制结果'),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh, size: 16),
                onPressed: () => _loadPreset(_sampleMulti),
                label: const Text('重置为默认'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 状态与耗时指示
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _status == '成功'
                  ? Colors.green.withValues(alpha: 0.1)
                  : _status == '失败'
                      ? Colors.red.withValues(alpha: 0.1)
                      : Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Text(
                  '执行状态: $_status',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _status == '成功'
                        ? Colors.green.shade700
                        : _status == '失败'
                            ? Colors.red.shade700
                            : Colors.grey.shade700,
                  ),
                ),
                const SizedBox(width: 16),
                Text('耗时: $_elapsedMs μs'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.3,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              _result,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
          // 模拟聊天会话区域中的真实渲染效果
          if (_message != null) ...[
            const SizedBox(height: 16),
            Text(
              '真实界面渲染效果预览 (模拟聊天时间线):',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark
                    ? Colors.black26
                    : const Color(0xFFF2F4F7), // 模拟微信灰底背景
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                children: [
                  const Text(
                    '8月23日 11:55',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: ArticleMessageContent(
                      message: _message!,
                      maxWidth: 380,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

