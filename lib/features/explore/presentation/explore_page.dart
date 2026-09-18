import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/scan/unified_scan_dispatcher.dart';
import '../../../core/widgets/cell_group.dart';
import '../../../core/widgets/glass_container.dart';
import '../../session/application/session_list_controller.dart';

class ExplorePage extends ConsumerStatefulWidget {
  const ExplorePage({required this.isCompact, super.key});
  final bool isCompact;

  @override
  ConsumerState<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends ConsumerState<ExplorePage> {
  final search = TextEditingController();
  String query = '';
  _ExploreCategory category = _ExploreCategory.all;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(sessionListControllerProvider);
    final features = _features
        .where((item) {
          final categoryMatches =
              category == _ExploreCategory.all || item.category == category;
          final keyword = query.trim().toLowerCase();
          return categoryMatches &&
              (keyword.isEmpty ||
                  item.title.toLowerCase().contains(keyword) ||
                  item.description.toLowerCase().contains(keyword) ||
                  item.keywords.any((value) => value.contains(keyword)));
        })
        .toList(growable: false);
    final horizontal = widget.isCompact ? 8.0 : 16.0;

    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: <Widget>[
        SliverToBoxAdapter(child: _hero(context)),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: horizontal),
          sliver: SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children:
                    _ExploreCategory.values.map((item) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          selected: category == item,
                          label: Text(item.label),
                          avatar: Icon(item.icon, size: 17),
                          onSelected: (_) => setState(() => category = item),
                        ),
                      );
                    }).toList(),
              ),
            ),
          ),
        ),

        // ── 我的内容 ──────────────────────────────────────────────
        SliverPadding(
          padding: EdgeInsets.fromLTRB(horizontal, 12, horizontal, 0),
          sliver: SliverToBoxAdapter(
            child: CellGroup(
              // title: '我的内容',
              children: [
                Cell(
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  title: '扫一扫',
                  showArrow: true,
                  onTap: () {
                    ref
                        .read(unifiedScanDispatcherProvider)
                        .openAndDispatch(context, ref);
                  },
                ),
              ],
            ),
          ),
        ),

        SliverPadding(
          padding: EdgeInsets.fromLTRB(horizontal, 12, horizontal, 6),
          sliver: SliverToBoxAdapter(
            child: _ExploreHeading(
              title: query.isEmpty ? '发现功能' : '搜索结果',

              subtitle:
                  query.isEmpty
                      ? 'GotoIM 中已经可以使用的能力'
                      : '找到 ${features.length} 项',
            ),
          ),
        ),
        if (features.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptySearch(onClear: _clearSearch),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, 32),
            sliver: SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: widget.isCompact ? 1 : 2,
                mainAxisExtent: 132,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemCount: features.length,
              itemBuilder:
                  (context, index) => _FeatureCard(
                    feature: features[index],
                    onTap: () {
                      final item = features[index];
                      if (item.route == '/scan-login/scan') {
                        ref
                            .read(unifiedScanDispatcherProvider)
                            .openAndDispatch(context, ref);
                      } else {
                        context.push(item.route);
                      }
                    },
                  ),
            ),
          ),
      ],
    );
  }

  Widget _hero(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              colors.primaryContainer.withValues(alpha: .72),
              colors.tertiaryContainer.withValues(alpha: .42),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.explore_rounded, color: colors.primary, size: 30),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '探索 GotoIM',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                '从聊天出发，发现设备协同、文件传输和效率工具。',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 18),
              SearchBar(
                controller: search,
                hintText: '搜索功能、设备或工具',
                leading: const Icon(Icons.search_rounded),
                trailing:
                    query.isEmpty
                        ? const <Widget>[]
                        : <Widget>[
                          IconButton(
                            tooltip: '清除',
                            onPressed: _clearSearch,
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                onChanged: (value) => setState(() => query = value),
                onSubmitted: (value) => setState(() => query = value),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _clearSearch() {
    search.clear();
    setState(() => query = '');
  }
}

class _ExploreHeading extends StatelessWidget {
  const _ExploreHeading({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Expanded(
        child: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      Text(subtitle, style: Theme.of(context).textTheme.labelMedium),
    ],
  );
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.feature, required this.onTap});
  final _ExploreFeature feature;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GlassCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: feature.color(colors).withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  feature.icon,
                  color: feature.color(colors),
                  size: 28,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      feature.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      feature.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 15),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptySearch extends StatelessWidget {
  const _EmptySearch({required this.onClear});
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(Icons.travel_explore_rounded, size: 52),
        const SizedBox(height: 12),
        const Text('没有找到相关功能'),
        TextButton(onPressed: onClear, child: const Text('清除搜索条件')),
      ],
    ),
  );
}

enum _ExploreCategory { all, connect, files, tools, developer }

extension on _ExploreCategory {
  String get label => switch (this) {
    _ExploreCategory.all => '全部',
    _ExploreCategory.connect => '连接',
    _ExploreCategory.files => '文件',
    _ExploreCategory.tools => '工具',
    _ExploreCategory.developer => '开发',
  };
  IconData get icon => switch (this) {
    _ExploreCategory.all => Icons.auto_awesome_rounded,
    _ExploreCategory.connect => Icons.hub_outlined,
    _ExploreCategory.files => Icons.folder_copy_outlined,
    _ExploreCategory.tools => Icons.widgets_outlined,
    _ExploreCategory.developer => Icons.developer_mode_outlined,
  };
}

class _ExploreFeature {
  const _ExploreFeature({
    required this.title,
    required this.description,
    required this.icon,
    required this.route,
    required this.category,
    this.keywords = const <String>[],
  });
  final String title;
  final String description;
  final IconData icon;
  final String route;
  final _ExploreCategory category;
  final List<String> keywords;

  Color color(ColorScheme colors) => switch (category) {
    _ExploreCategory.connect => colors.primary,
    _ExploreCategory.files => colors.tertiary,
    _ExploreCategory.tools => colors.secondary,
    _ExploreCategory.developer => colors.error,
    _ExploreCategory.all => colors.primary,
  };
}

const _features = <_ExploreFeature>[
  // ── 连接 ─────────────────────────────────────────────────────────────────
  _ExploreFeature(
    title: '扫一扫',
    description: '扫描二维码添加好友或扫码登录',
    icon: Icons.qr_code_scanner_rounded,
    route: '/scan-login/scan',
    category: _ExploreCategory.connect,
    keywords: <String>['扫码', '二维码', 'qr', '扫描'],
  ),
  _ExploreFeature(
    title: '添加好友',
    description: '搜索账号或手机号添加联系人',
    icon: Icons.person_add_alt_1_rounded,
    route: '/add-friend',
    category: _ExploreCategory.connect,
    keywords: <String>['好友', '添加', '搜索', '联系人'],
  ),
  _ExploreFeature(
    title: '创建群组',
    description: '选择联系人并发起群聊',
    icon: Icons.group_add_rounded,
    route: '/create-group',
    category: _ExploreCategory.connect,
    keywords: <String>['群组', '群聊', '创建', '发起'],
  ),
  _ExploreFeature(
    title: '扫码登录',
    description: '扫描桌面端二维码快速完成登录授权',
    icon: Icons.cast_rounded,
    route: '/scan-login/scan',
    category: _ExploreCategory.connect,
    keywords: <String>['扫码登录', '桌面', '授权', '二维码'],
  ),
  // ── 文件 ─────────────────────────────────────────────────────────────────
  _ExploreFeature(
    title: '局域网快传',
    description: '在同一 Wi-Fi 下与其他设备高速互传文件',
    icon: Icons.wifi_tethering_rounded,
    route: '/local-file-server',
    category: _ExploreCategory.files,
    keywords: <String>['局域网', '文件', '传输', 'wifi', '快传'],
  ),
  _ExploreFeature(
    title: '共享文件管理',
    description: '查看和管理已共享的本地文件列表',
    icon: Icons.folder_shared_rounded,
    route: '/local-file-server/files',
    category: _ExploreCategory.files,
    keywords: <String>['文件', '共享', '管理', '列表'],
  ),
  // ── 工具 ─────────────────────────────────────────────────────────────────
  _ExploreFeature(
    title: '外观主题',
    description: '切换深色 / 浅色模式及主题色',
    icon: Icons.palette_rounded,
    route: '/settings/theme',
    category: _ExploreCategory.tools,
    keywords: <String>['主题', '深色', '浅色', '颜色', '外观'],
  ),
  _ExploreFeature(
    title: '设置',
    description: '账号、通知、语言和隐私等全局设置',
    icon: Icons.settings_rounded,
    route: '/settings',
    category: _ExploreCategory.tools,
    keywords: <String>['设置', '通知', '隐私', '账号'],
  ),
  _ExploreFeature(
    title: '登录设备管理',
    description: '查看所有已登录设备并一键远程退出',
    icon: Icons.devices_rounded,
    route: '/devices',
    category: _ExploreCategory.tools,
    keywords: <String>['设备', '登录', '远程退出', '安全'],
  ),
  _ExploreFeature(
    title: '工作台',
    description: '快速访问常用工作应用与企业服务',
    icon: Icons.grid_view_rounded,
    route: '/workbench',
    category: _ExploreCategory.tools,
    keywords: <String>['工作台', '应用', '企业', '服务'],
  ),
  // ── 开发 ─────────────────────────────────────────────────────────────────
  _ExploreFeature(
    title: '开发诊断中心',
    description: '检查网络、数据库、SignalR 和原生能力',
    icon: Icons.monitor_heart_rounded,
    route: '/diagnostics',
    category: _ExploreCategory.developer,
    keywords: <String>['调试', '网络', '数据库', 'signalr', '诊断'],
  ),
  _ExploreFeature(
    title: 'SignalR 实时诊断',
    description: '实时查看连接状态、事件流和延迟',
    icon: Icons.cable_rounded,
    route: '/diagnostics/signalr',
    category: _ExploreCategory.developer,
    keywords: <String>['signalr', '实时', '连接', 'websocket'],
  ),
  _ExploreFeature(
    title: '数据库诊断',
    description: '浏览本地 Drift/SQLite 数据库内容',
    icon: Icons.storage_rounded,
    route: '/diagnostics/database',
    category: _ExploreCategory.developer,
    keywords: <String>['数据库', 'sqlite', 'drift', '本地'],
  ),
  _ExploreFeature(
    title: 'JSBridge 测试台',
    description: '测试 H5 ↔ Flutter JSBridge API 调用',
    icon: Icons.javascript_rounded,
    route: '/diagnostics/js-bridge-harness',
    category: _ExploreCategory.developer,
    keywords: <String>['jsbridge', 'h5', 'webview', 'js'],
  ),
  _ExploreFeature(
    title: '原生能力诊断',
    description: '测试传感器、摄像头、通知等原生功能',
    icon: Icons.developer_board_rounded,
    route: '/diagnostics/native',
    category: _ExploreCategory.developer,
    keywords: <String>['原生', '传感器', '摄像头', '通知', 'native'],
  ),
  _ExploreFeature(
    title: '合规与版本升级',
    description: '隐私合规授权 & App 版本检测诊断',
    icon: Icons.verified_rounded,
    route: '/diagnostics/privacy-and-update',
    category: _ExploreCategory.developer,
    keywords: <String>['合规', '隐私', '升级', '版本', '协议'],
  ),
];
