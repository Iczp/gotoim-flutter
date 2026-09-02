import 'package:flutter/material.dart';

import '../../../features/session/data/models/session_summary.dart';
import '../half_page_sheet.dart';
import 'target_picker_models.dart';
import 'target_picker_view.dart';

export 'target_picker_models.dart';
export 'target_picker_view.dart';

/// 通用目标/人员选择器门面。
///
/// 适用于：
/// - 消息单条转发 / 合并转发
/// - 发起群聊 / 邀请新成员
/// - 分享到会话 / 推荐名片
/// - 业务对象单选 / 多选
abstract final class TargetPicker {
  /// 展示目标选择器并返回选中的项目列表。
  ///
  /// 如果用户取消或关闭弹窗，返回 `null`。
  static Future<List<TargetPickerItem<T>>?> show<T>({
    required BuildContext context,
    required List<TargetPickerItem<T>> items,
    TargetPickerOptions options = const TargetPickerOptions(),
  }) async {
    return showHalfPageSheet<List<TargetPickerItem<T>>>(
      context: context,
      options: HalfPageSheetOptions(
        heightFactor: options.heightFactor,
        constraints: const BoxConstraints(maxWidth: 580),
        keyboardBehavior: HalfPageSheetKeyboardBehavior.resize,
      ),
      builder: (sheetContext) => TargetPickerView<T>(
        items: items,
        options: options,
        onConfirm: (selected) => Navigator.of(sheetContext).pop(selected),
        onCancel: () => Navigator.of(sheetContext).pop(null),
      ),
    );
  }

  /// 单选模式快捷方法。
  ///
  /// 当 [showConfirmButton] 为 `false`（默认）时，用户点击目标直接返回结果。
  static Future<TargetPickerItem<T>?> pickSingle<T>({
    required BuildContext context,
    required List<TargetPickerItem<T>> items,
    String title = '选择目标',
    String? subtitle,
    bool showConfirmButton = false,
    String? initialSelectedId,
    Set<String> disabledIds = const <String>{},
    bool enableSearch = true,
  }) async {
    final result = await show<T>(
      context: context,
      items: items,
      options: TargetPickerOptions(
        title: title,
        subtitle: subtitle,
        multiple: false,
        showConfirmButton: showConfirmButton,
        initialSelectedIds: initialSelectedId != null ? {initialSelectedId} : const {},
        disabledIds: disabledIds,
        enableSearch: enableSearch,
      ),
    );
    if (result != null && result.isNotEmpty) {
      return result.first;
    }
    return null;
  }

  /// 多选模式快捷方法。
  static Future<List<TargetPickerItem<T>>?> pickMultiple<T>({
    required BuildContext context,
    required List<TargetPickerItem<T>> items,
    String title = '选择多个目标',
    String? subtitle,
    int? minCount = 1,
    int? maxCount,
    Set<String> initialSelectedIds = const <String>{},
    Set<String> disabledIds = const <String>{},
    bool enableSearch = true,
  }) {
    return show<T>(
      context: context,
      items: items,
      options: TargetPickerOptions(
        title: title,
        subtitle: subtitle,
        multiple: true,
        showConfirmButton: true,
        minCount: minCount,
        maxCount: maxCount,
        initialSelectedIds: initialSelectedIds,
        disabledIds: disabledIds,
        enableSearch: enableSearch,
      ),
    );
  }

  /// 从会话列表 ([SessionSummary]) 中快捷选择转发/分享目标。
  static Future<List<SessionSummary>?> pickSessionUnits({
    required BuildContext context,
    required List<SessionSummary> sessions,
    String title = '选择转发会话',
    String? subtitle,
    bool multiple = false,
    bool? showConfirmButton,
    int? maxCount,
    int? minCount,
    Set<String> initialSelectedIds = const <String>{},
    Set<String> disabledIds = const <String>{},
  }) async {
    final items = sessions
        .map((s) => TargetPickerItem.fromSessionSummary(s))
        .toList(growable: false);

    final selected = await show<SessionSummary>(
      context: context,
      items: items,
      options: TargetPickerOptions(
        title: title,
        subtitle: subtitle,
        multiple: multiple,
        showConfirmButton: showConfirmButton,
        maxCount: maxCount,
        minCount: minCount,
        initialSelectedIds: initialSelectedIds,
        disabledIds: disabledIds,
      ),
    );

    if (selected == null) return null;
    return selected
        .map((e) => e.data)
        .whereType<SessionSummary>()
        .toList(growable: false);
  }
}
