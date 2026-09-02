import 'package:flutter/material.dart';

/// 底部功能项描述（相册、拍照、视频、文件、位置等）
class ChatFunctionItem {
  const ChatFunctionItem(this.label, this.icon, {this.enabled = false});

  /// 功能项名称
  final String label;

  /// 功能项图标
  final IconData icon;

  /// 是否已启用（未接入时置灰或提示暂未接入）
  final bool enabled;
}

/// 底部“更多功能”分页网格托盘组件（ChatFunctionPanel）
///
/// 核心职责：
/// 1. 网格化分页展示聊天附加功能（每页 8 个，4x2 布局）；
/// 2. 底部动态圆点分页指示器联动；
/// 3. 自适应字体缩放与图标比例计算。
class ChatFunctionPanel extends StatelessWidget {
  const ChatFunctionPanel({
    required this.items,
    required this.pageController,
    required this.page,
    required this.onPageChanged,
    required this.onSelected,
    super.key,
  });

  /// 功能项列表
  final List<ChatFunctionItem> items;

  /// 分页滑动控制器
  final PageController pageController;

  /// 当前所在页码（从 0 开始）
  final int page;

  /// 页面滑动切换回调
  final ValueChanged<int> onPageChanged;

  /// 点击功能项回调
  final ValueChanged<ChatFunctionItem> onSelected;


  @override
  Widget build(BuildContext context) {
    final pageCount = (items.length / 8).ceil();
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
        ),
      ),
      child: Column(
        children: <Widget>[
          Expanded(
            child: PageView.builder(
              controller: pageController,
              itemCount: pageCount,
              onPageChanged: onPageChanged,
              itemBuilder: (context, pageIndex) {
                final start = pageIndex * 8;
                final pageItems = items.skip(start).take(8).toList();
                return GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.18,
                  ),
                  itemCount: pageItems.length,
                  itemBuilder: (context, index) {
                    final item = pageItems[index];
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onSelected(item),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final iconSize = (constraints.maxHeight - 22).clamp(
                            34.0,
                            44.0,
                          );
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Container(
                                width: iconSize,
                                height: iconSize,
                                decoration: BoxDecoration(
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Icon(
                                  item.icon,
                                  size: (iconSize * 0.54).clamp(19.0, 24.0),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Flexible(
                                child: Text(
                                  item.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textScaler: MediaQuery.textScalerOf(
                                    context,
                                  ).clamp(maxScaleFactor: 1.3),
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List<Widget>.generate(
              pageCount,
              (index) => AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: index == page ? 14 : 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
                decoration: BoxDecoration(
                  color:
                      index == page
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
