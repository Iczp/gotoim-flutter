import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/glass_container.dart';
import '../../session/application/session_list_controller.dart';
import '../../session/presentation/chat_object_avatar.dart';

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
    final sessions = ref.watch(sessionListControllerProvider);
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
    final horizontal = widget.isCompact ? 16.0 : 32.0;

    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: <Widget>[
        SliverPadding(
          padding: EdgeInsets.fromLTRB(horizontal, 18, horizontal, 12),
          sliver: SliverToBoxAdapter(child: _hero(context)),
        ),
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
        if (query.isEmpty && sessions.sessions.isNotEmpty) ...<Widget>[
          SliverPadding(
            padding: EdgeInsets.fromLTRB(horizontal, 22, horizontal, 10),
            sliver: const SliverToBoxAdapter(
              child: _ExploreHeading(title: '继续聊天', subtitle: '最近活跃的会话'),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 112,
              child: ListView.separated(
                padding: EdgeInsets.symmetric(horizontal: horizontal),
                scrollDirection: Axis.horizontal,
                itemCount: sessions.sessions.take(8).length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final item = sessions.sessions[index];
                  return _RecentSessionCard(
                    title: item.title,
                    subtitle: item.preview,
                    onTap:
                        () => context.push(
                          '/chat/${Uri.encodeComponent(item.id)}'
                          '?ownerId=${item.ownerId ?? sessions.currentOwner?.id ?? 0}'
                          '&title=${Uri.encodeQueryComponent(item.title)}',
                        ),
                  );
                },
              ),
            ),
          ),
        ],
        SliverPadding(
          padding: EdgeInsets.fromLTRB(horizontal, 24, horizontal, 10),
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
                    onTap: () => context.push(features[index].route),
                  ),
            ),
          ),
      ],
    );
  }

  Widget _hero(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(20),
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
          padding: const EdgeInsets.all(20),
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

class _RecentSessionCard extends StatelessWidget {
  const _RecentSessionCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 220,
    child: GlassCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: <Widget>[
              ChatObjectAvatar(name: title, imageUrl: null, radius: 23),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle.isEmpty ? '开始聊天' : subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
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
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Row(
            children: <Widget>[
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: feature.color(colors).withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(17),
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
  _ExploreFeature(
    title: '扫码连接',
    description: '扫描二维码登录其他终端或识别连接信息',
    icon: Icons.qr_code_scanner_rounded,
    route: '/scan-login/scan',
    category: _ExploreCategory.connect,
    keywords: <String>['扫码', '登录', '二维码'],
  ),
  _ExploreFeature(
    title: '登录设备',
    description: '查看当前账号已经登录的手机、平板和桌面设备',
    icon: Icons.devices_rounded,
    route: '/devices',
    category: _ExploreCategory.connect,
    keywords: <String>['终端', '设备', '在线'],
  ),
  _ExploreFeature(
    title: '局域网文件站',
    description: '在附近设备间浏览、上传与下载文件',
    icon: Icons.folder_shared_rounded,
    route: '/local-file-server',
    category: _ExploreCategory.files,
    keywords: <String>['局域网', '传输', '共享'],
  ),
  _ExploreFeature(
    title: '工作台',
    description: '打开已接入的应用与效率工具',
    icon: Icons.grid_view_rounded,
    route: '/workbench',
    category: _ExploreCategory.tools,
    keywords: <String>['应用', '效率', '小程序'],
  ),
  _ExploreFeature(
    title: '媒体能力',
    description: '验证图片、视频、录音与文件选择能力',
    icon: Icons.perm_media_rounded,
    route: '/diagnostics/media',
    category: _ExploreCategory.tools,
    keywords: <String>['图片', '视频', '语音'],
  ),
  _ExploreFeature(
    title: '开发诊断中心',
    description: '检查网络、数据库、SignalR 和原生能力',
    icon: Icons.monitor_heart_rounded,
    route: '/diagnostics',
    category: _ExploreCategory.developer,
    keywords: <String>['调试', '网络', '数据库', 'signalr'],
  ),
];
