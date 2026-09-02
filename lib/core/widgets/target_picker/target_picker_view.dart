import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_avatar.dart';
import '../app_toast.dart';
import 'target_picker_models.dart';

/// 目标选择器核心内容视图（支持嵌入页面或在半屏/弹窗中独立使用）。
class TargetPickerView<T> extends StatefulWidget {
  const TargetPickerView({
    required this.items,
    this.options = const TargetPickerOptions(),
    this.onConfirm,
    this.onCancel,
    super.key,
  });

  /// 候选列表。
  final List<TargetPickerItem<T>> items;

  /// 选择器配置。
  final TargetPickerOptions options;

  /// 确认选择回调。
  final ValueChanged<List<TargetPickerItem<T>>>? onConfirm;

  /// 取消/关闭回调。
  final VoidCallback? onCancel;

  @override
  State<TargetPickerView<T>> createState() => _TargetPickerViewState<T>();
}

class _TargetPickerViewState<T> extends State<TargetPickerView<T>> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _chipScrollController = ScrollController();

  late Set<String> _selectedIds;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedIds = Set<String>.from(widget.options.initialSelectedIds);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void didUpdateWidget(covariant TargetPickerView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!setEquals(
      oldWidget.options.initialSelectedIds,
      widget.options.initialSelectedIds,
    )) {
      _selectedIds = Set<String>.from(widget.options.initialSelectedIds);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _chipScrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    if (query != _searchQuery) {
      setState(() => _searchQuery = query);
    }
  }

  List<TargetPickerItem<T>> get _filteredItems {
    if (_searchQuery.isEmpty) return widget.items;
    return widget.items.where((item) {
      final inTitle = item.title.toLowerCase().contains(_searchQuery);
      final inSub = item.subtitle?.toLowerCase().contains(_searchQuery) ?? false;
      final inCat = item.category?.toLowerCase().contains(_searchQuery) ?? false;
      return inTitle || inSub || inCat;
    }).toList(growable: false);
  }

  List<TargetPickerItem<T>> get _selectedItems {
    final map = {for (final item in widget.items) item.id: item};
    return _selectedIds
        .map((id) => map[id])
        .whereType<TargetPickerItem<T>>()
        .toList(growable: false);
  }

  bool _isItemDisabled(TargetPickerItem<T> item) {
    return item.disabled || widget.options.disabledIds.contains(item.id);
  }

  void _onItemTap(TargetPickerItem<T> item) {
    if (_isItemDisabled(item)) {
      showToast(item.disabledReason ?? '该项已被禁用，不可选择');
      return;
    }

    if (widget.options.multiple) {
      final isSelected = _selectedIds.contains(item.id);
      if (isSelected) {
        setState(() {
          _selectedIds.remove(item.id);
        });
      } else {
        if (widget.options.maxCount != null &&
            _selectedIds.length >= widget.options.maxCount!) {
          showToast('最多只能选择 ${widget.options.maxCount} 项');
          return;
        }
        setState(() {
          _selectedIds.add(item.id);
        });
        _scrollToChipEnd();
      }
    } else {
      // 单选模式
      if (!widget.options.effectiveShowConfirmButton) {
        // 无确定按钮，点击直接确定返回
        widget.onConfirm?.call(<TargetPickerItem<T>>[item]);
      } else {
        setState(() {
          _selectedIds = <String>{item.id};
        });
      }
    }
  }

  void _removeSelected(String id) {
    setState(() {
      _selectedIds.remove(id);
    });
  }

  void _scrollToChipEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chipScrollController.hasClients) {
        _chipScrollController.animateTo(
          _chipScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleConfirm() {
    final selected = _selectedItems;
    if (selected.length < widget.options.effectiveMinCount) {
      showToast('请至少选择 ${widget.options.effectiveMinCount} 项');
      return;
    }
    if (widget.options.maxCount != null &&
        selected.length > widget.options.maxCount!) {
      showToast('最多只能选择 ${widget.options.maxCount} 项');
      return;
    }
    widget.onConfirm?.call(selected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final filtered = _filteredItems;
    final selected = _selectedItems;

    final canConfirm =
        selected.length >= widget.options.effectiveMinCount &&
        (widget.options.maxCount == null ||
            selected.length <= widget.options.maxCount!);

    return Material(
      color: theme.scaffoldBackgroundColor,
      child: Column(
        children: [
          // 1. Header Bar
          _buildHeader(context, colorScheme, canConfirm, selected.length),

          // 2. Selected Chips Preview Bar (Multi-select: always present to prevent layout jitter)
          if (widget.options.multiple && widget.options.showSelectedPreviewBar)
            _buildSelectedChipsBar(theme, colorScheme, selected),

          // 3. Search Bar
          if (widget.options.enableSearch)
            _buildSearchBar(theme, colorScheme),

          // 4. Candidate List / Empty State
          Expanded(
            child: filtered.isEmpty
                ? _buildEmptyState(theme)
                : _buildCandidateList(theme, colorScheme, filtered),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ColorScheme colorScheme,
    bool canConfirm,
    int selectedCount,
  ) {
    String confirmLabel = widget.options.confirmText;
    if (widget.options.multiple) {
      if (widget.options.maxCount != null) {
        confirmLabel = '$confirmLabel ($selectedCount/${widget.options.maxCount})';
      } else if (selectedCount > 0) {
        confirmLabel = '$confirmLabel ($selectedCount)';
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // Cancel / Close
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: '取消',
            onPressed: widget.onCancel ?? () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 8),

          // Title & Subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.options.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (widget.options.subtitle != null &&
                    widget.options.subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.options.subtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).hintColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          // Confirm Button (if enabled)
          if (widget.options.effectiveShowConfirmButton)
            FilledButton(
              onPressed: canConfirm ? _handleConfirm : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: Text(confirmLabel),
            ),
        ],
      ),
    );
  }

  Widget _buildSelectedChipsBar(
    ThemeData theme,
    ColorScheme colorScheme,
    List<TargetPickerItem<T>> selected,
  ) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.15),
            width: 0.5,
          ),
        ),
      ),
      child: selected.isEmpty
          ? Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Icon(
                    Icons.touch_app_outlined,
                    size: 18,
                    color: theme.hintColor.withValues(alpha: 0.8),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '请选择',
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.hintColor,
                    ),
                  ),
                ],
              ),
            )
          : ListView.separated(
              controller: _chipScrollController,
              scrollDirection: Axis.horizontal,
              itemCount: selected.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = selected[index];
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Tooltip(
                message: item.title,
                child: GestureDetector(
                  onTap: () => _removeSelected(item.id),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4, right: 4),
                    child: AppAvatar(
                      name: item.title,
                      imageUrl: item.avatarUrl,
                      size: 40,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: GestureDetector(
                  onTap: () => _removeSelected(item.id),
                  child: Container(
                    decoration: BoxDecoration(
                      color: colorScheme.error,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(2),
                    child: const Icon(
                      Icons.close,
                      size: 10,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: widget.options.searchHint,
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => _searchController.clear(),
                )
              : null,
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildCandidateList(
    ThemeData theme,
    ColorScheme colorScheme,
    List<TargetPickerItem<T>> items,
  ) {
    final hasCategories = items.any((e) => e.category != null);
    final List<Widget> listChildren = [];

    if (!hasCategories || _searchQuery.isNotEmpty) {
      for (final item in items) {
        listChildren.add(_buildItemTile(theme, colorScheme, item));
      }
    } else {
      final Map<String, List<TargetPickerItem<T>>> groups = {};
      for (final item in items) {
        final category = item.category ?? '其他';
        groups.putIfAbsent(category, () => <TargetPickerItem<T>>[]).add(item);
      }
      for (final entry in groups.entries) {
        listChildren.add(
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: theme.scaffoldBackgroundColor,
            child: Text(
              entry.key,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: theme.hintColor,
              ),
            ),
          ),
        );
        for (final item in entry.value) {
          listChildren.add(_buildItemTile(theme, colorScheme, item));
        }
      }
    }

    return ListView(
      children: listChildren,
    );
  }

  Widget _buildItemTile(
    ThemeData theme,
    ColorScheme colorScheme,
    TargetPickerItem<T> item,
  ) {
    final isSelected = _selectedIds.contains(item.id);
    final isDisabled = _isItemDisabled(item);

    return Opacity(
      opacity: isDisabled ? 0.45 : 1.0,
      child: ListTile(
        onTap: () => _onItemTap(item),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Selection indicator
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? colorScheme.primary : Colors.transparent,
                  border: Border.all(
                    color: isSelected
                        ? colorScheme.primary
                        : (isDisabled ? theme.disabledColor : theme.dividerColor),
                    width: 1.5,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
            ),

            // Avatar
            AppAvatar(
              name: item.title,
              imageUrl: item.avatarUrl,
              size: 42,
            ),
          ],
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                item.title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isDisabled ? theme.disabledColor : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (item.badge != null)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  item.badge!,
                  style: TextStyle(
                    fontSize: 10,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
          ],
        ),
        subtitle: (item.subtitle != null && item.subtitle!.isNotEmpty)
            ? Text(
                item.subtitle!,
                style: TextStyle(
                  fontSize: 12,
                  color: isDisabled ? theme.disabledColor : theme.hintColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        trailing: isDisabled && item.disabledReason != null
            ? Text(
                item.disabledReason!,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.disabledColor,
                ),
              )
            : (!widget.options.multiple && !widget.options.effectiveShowConfirmButton
                ? const Icon(Icons.chevron_right, size: 18, color: Colors.grey)
                : null),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.people_outline,
            size: 48,
            color: theme.hintColor.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            widget.options.emptyText,
            style: TextStyle(color: theme.hintColor),
          ),
        ],
      ),
    );
  }
}
