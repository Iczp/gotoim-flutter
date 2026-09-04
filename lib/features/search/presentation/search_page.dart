import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_modal.dart';
import '../application/search_controller.dart';
import '../domain/search_models.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  late final TextEditingController _textController;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _focusNode = FocusNode();
    _textController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    setState(() {});
    ref.read(globalSearchControllerProvider).onQueryChanged(_textController.text);
  }

  void _onSearchSubmit(String text) {
    if (text.trim().isNotEmpty) {
      ref.read(globalSearchControllerProvider).recordKeyword(text);
    }
  }

  void _selectHistory(String term) {
    _textController.text = term;
    _textController.selection = TextSelection.fromPosition(
      TextPosition(offset: term.length),
    );
    ref.read(globalSearchControllerProvider).onQueryChanged(term);
    ref.read(globalSearchControllerProvider).recordKeyword(term);
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final controller = ref.watch(globalSearchControllerProvider);
    final searchState = controller.state;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        titleSpacing: 0,
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Container(
          height: 40,
          margin: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(20),
          ),
          child: TextField(
            controller: _textController,
            focusNode: _focusNode,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: _onSearchSubmit,
            style: theme.textTheme.bodyMedium,
            decoration: InputDecoration(
              hintText: '搜索联系人、群聊、聊天记录...',
              hintStyle: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: colorScheme.onSurfaceVariant,
                size: 20,
              ),
              suffixIcon: _textController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        Icons.cancel_rounded,
                        color: colorScheme.onSurfaceVariant,
                        size: 18,
                      ),
                      onPressed: () {
                        _textController.clear();
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 9),
            ),
          ),
        ),
      ),
      body: searchState.isEmptyQuery
          ? _buildHistorySection(context, searchState, controller)
          : _buildSearchResults(context, searchState, controller),
    );
  }

  Widget _buildHistorySection(
    BuildContext context,
    SearchResultState state,
    GlobalSearchController controller,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '搜索历史',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (state.history.isNotEmpty)
              IconButton(
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
                tooltip: '清空历史',
                onPressed: () async {
                  final confirmed = await showConfirmModal(
                    context: context,
                    title: '清空搜索历史',
                    message: '确定要清空全部搜索记录吗？',
                    confirmText: '清空',
                    isDestructive: true,
                  );
                  if (confirmed) {
                    controller.clearAllHistory();
                  }
                },
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (state.history.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                '暂无搜索历史',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final term in state.history)
                InkWell(
                  onTap: () => _selectHistory(term),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.only(
                      left: 12,
                      right: 6,
                      top: 6,
                      bottom: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          term,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => controller.deleteHistoryItem(term),
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              Icons.close_rounded,
                              size: 14,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildSearchResults(
    BuildContext context,
    SearchResultState state,
    GlobalSearchController controller,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final keyword = state.keyword.trim();

    if (!state.hasAnyResult && !state.isLocalLoading && !state.isRemoteLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 56,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              '未找到与 "$keyword" 相关的内容',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // 1. 本地 Friend 表联系人（排第一位，点击直接进入聊天）
        if (state.localContacts.isNotEmpty || state.isLocalLoading) ...[
          _buildSectionHeader(
            context,
            title: '联系人',
            count: state.localContacts.length,
            isLoading: state.isLocalLoading,
          ),
          for (final contact in state.localContacts)
            ListTile(
              leading: AppAvatar(
                name: contact.title,
                imageUrl: contact.avatarUrl,
                radius: 20,
              ),
              title: _buildHighlightedText(
                text: contact.title,
                keyword: keyword,
                context: context,
                isTitle: true,
              ),
              subtitle: contact.subtitle != null
                  ? _buildHighlightedText(
                      text: contact.subtitle!,
                      keyword: keyword,
                      context: context,
                      isTitle: false,
                    )
                  : null,
              trailing: contact.isRoom
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '群聊',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.primary,
                        ),
                      ),
                    )
                  : null,
              onTap: () {
                controller.recordKeyword(keyword);
                final ownerId = contact.ownerId ?? 0;
                context.push(
                  '/chat/${Uri.encodeComponent(contact.id)}'
                  '?ownerId=$ownerId'
                  '&title=${Uri.encodeQueryComponent(contact.title)}',
                );
              },
            ),
        ],

        // 2. 本地聊天记录
        if (state.localMessages.isNotEmpty) ...[
          const Divider(height: 16),
          _buildSectionHeader(
            context,
            title: '聊天记录',
            count: state.localMessages.length,
          ),
          for (final msg in state.localMessages)
            ListTile(
              leading: AppAvatar(
                name: msg.sessionTitle ?? msg.senderName ?? 'IM',
                imageUrl: msg.senderAvatarUrl,
                radius: 20,
              ),
              title: Text(
                msg.sessionTitle ?? msg.senderName ?? '会话记录',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: _buildHighlightedText(
                text: msg.contentSnippet,
                keyword: keyword,
                context: context,
                isTitle: false,
              ),
              trailing: msg.timestamp != null
                  ? Text(
                      _formatMessageTime(msg.timestamp!),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    )
                  : null,
              onTap: () {
                controller.recordKeyword(keyword);
                context.push(
                  '/chat/${Uri.encodeComponent(msg.sessionUnitId)}'
                  '?title=${Uri.encodeQueryComponent(msg.sessionTitle ?? '')}',
                );
              },
            ),
        ],

        // 3. 线上搜索预览
        if (state.remoteContacts.isNotEmpty || state.isRemoteLoading) ...[
          const Divider(height: 16),
          _buildSectionHeader(
            context,
            title: '网络搜索预览',
            count: state.remoteContacts.length,
            isLoading: state.isRemoteLoading,
          ),
          if (state.isRemoteLoading && state.remoteContacts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '正在检索线上结果...',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          for (final remote in state.remoteContacts)
            ListTile(
              leading: AppAvatar(
                name: remote.name,
                imageUrl: remote.avatarUrl,
                radius: 20,
              ),
              title: _buildHighlightedText(
                text: remote.name,
                keyword: keyword,
                context: context,
                isTitle: true,
              ),
              subtitle: Text(
                remote.objectTypeDescription ?? (remote.code != null ? '编码: ${remote.code}' : '线上联系人'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: remote.isFriend
                  ? OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () {
                        controller.recordKeyword(keyword);
                        context.push(
                          '/chat/${Uri.encodeComponent(remote.id)}'
                          '?title=${Uri.encodeQueryComponent(remote.name)}',
                        );
                      },
                      child: const Text('发消息'),
                    )
                  : FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () {
                        controller.recordKeyword(keyword);
                        context.push(
                          '/add-friend?keyword=${Uri.encodeComponent(remote.name)}',
                        );
                      },
                      child: const Text('加好友'),
                    ),
            ),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    required int count,
    bool isLoading = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          if (count > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (isLoading) ...[
            const SizedBox(width: 8),
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHighlightedText({
    required String text,
    required String keyword,
    required BuildContext context,
    required bool isTitle,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final baseStyle = isTitle
        ? theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)
        : theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant);

    if (keyword.isEmpty || !text.toLowerCase().contains(keyword.toLowerCase())) {
      return Text(text, style: baseStyle, maxLines: 1, overflow: TextOverflow.ellipsis);
    }

    final spans = <TextSpan>[];
    final lowerText = text.toLowerCase();
    final lowerKeyword = keyword.toLowerCase();
    int start = 0;

    while (start < text.length) {
      final index = lowerText.indexOf(lowerKeyword, start);
      if (index == -1) {
        spans.add(TextSpan(text: text.substring(start), style: baseStyle));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index), style: baseStyle));
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + keyword.length),
          style: baseStyle?.copyWith(
            color: colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
      start = index + keyword.length;
    }

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(children: spans),
    );
  }

  String _formatMessageTime(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }
    return '${dt.month}/${dt.day}';
  }
}
