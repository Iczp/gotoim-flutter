import 'package:flutter/material.dart';

/// Local new-tab content: no network, WebView or security request until submit.
class BrowserHomePage extends StatefulWidget {
  const BrowserHomePage({required this.onNavigate, super.key});
  final ValueChanged<String> onNavigate;
  @override
  State<BrowserHomePage> createState() => _BrowserHomePageState();
}

class _BrowserHomePageState extends State<BrowserHomePage> {
  final _input = TextEditingController();
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _submit(String value) {
    final text = value.trim();
    if (text.isEmpty) return;
    final isAddress =
        !text.contains(' ') &&
        (text.contains('.') ||
            text.startsWith('http://') ||
            text.startsWith('https://'));
    widget.onNavigate(
      isAddress
          ? text
          : Uri.https('www.bing.com', '/search', {'q': text}).toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surfaceContainerLowest,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF07A86A).withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.travel_explore_rounded,
                    size: 42,
                    color: Color(0xFF07A86A),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '从这里，开始探索',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '打开聊天中的链接，或搜索你想了解的内容',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _input,
                  onSubmitted: _submit,
                  textInputAction: TextInputAction.go,
                  decoration: InputDecoration(
                    hintText: '输入网址或搜索内容',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: colors.surfaceContainerLow,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: IconButton(
                      tooltip: '打开',
                      onPressed: () => _submit(_input.text),
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 18,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    _hint(Icons.tab_rounded, '多标签浏览'),
                    _hint(Icons.open_in_new_rounded, '支持独立窗口'),
                    _hint(Icons.verified_user_outlined, '链接安全核验'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _hint(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        icon,
        size: 15,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 5),
      Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}
