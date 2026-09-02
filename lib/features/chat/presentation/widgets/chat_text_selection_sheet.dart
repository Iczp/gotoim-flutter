import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/widgets/app_toast.dart';

/// 显示文本消息部分选择弹窗。
Future<void> showChatTextSelectionSheet(
  BuildContext context, {
  required String text,
}) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  final mediaQuery = MediaQuery.of(context);

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: theme.scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: mediaQuery.size.height * 0.75,
            minHeight: 220,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. 顶部操作栏
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  border: Border(
                    bottom: BorderSide(
                      color: theme.dividerColor.withValues(alpha: 0.15),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: '关闭',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Navigator.of(sheetContext).pop(),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        '选择文本',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                      ),
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('复制全文'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: text));
                        showToast('已复制全文');
                        Navigator.of(sheetContext).pop();
                      },
                    ),
                  ],
                ),
              ),

              // 2. 可选择文本内容区域
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: SelectionArea(
                    child: SelectableText(
                      text,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.6,
                        color: colorScheme.onSurface,
                      ),
                      cursorColor: colorScheme.primary,
                      showCursor: true,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
