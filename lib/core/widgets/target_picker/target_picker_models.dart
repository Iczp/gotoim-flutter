import 'package:flutter/foundation.dart';

import '../../../features/session/data/models/session_summary.dart';

/// 目标选择器模式。
enum TargetPickerMode {
  /// 单选模式
  single,

  /// 多选模式
  multiple,
}

/// 选择器项目通用模型。
@immutable
class TargetPickerItem<T> {
  const TargetPickerItem({
    required this.id,
    required this.title,
    this.subtitle,
    this.avatarUrl,
    this.badge,
    this.category,
    this.disabled = false,
    this.disabledReason,
    this.data,
  });

  /// 唯一标识（例如 sessionUnitId, userId, contactId）。
  final String id;

  /// 主标题（姓名/群名称/昵称）。
  final String title;

  /// 副标题（最后一条消息/部门/简介）。
  final String? subtitle;

  /// 头像地址。
  final String? avatarUrl;

  /// 标签或徽标（例如「群聊」「客服」「内部」）。
  final String? badge;

  /// 分组名称（例如「最近会话」「好友」「群组」）。
  final String? category;

  /// 是否禁用（置灰且无法选择）。
  final bool disabled;

  /// 禁用原因提示（点击时 Toast 提示）。
  final String? disabledReason;

  /// 关联的原始业务数据对象。
  final T? data;

  /// 从 [SessionSummary] 快捷构造。
  static TargetPickerItem<SessionSummary> fromSessionSummary(
    SessionSummary session, {
    bool disabled = false,
    String? disabledReason,
    String? category,
  }) {
    return TargetPickerItem<SessionSummary>(
      id: session.id,
      title: session.title,
      subtitle: session.preview,
      avatarUrl: session.raw['destination']?['avatarUrl']?.toString() ??
          session.raw['avatarUrl']?.toString(),
      badge: session.raw['session']?['type'] == 2 ? '群聊' : null,
      category: category ?? '最近会话',
      disabled: disabled,
      disabledReason: disabledReason,
      data: session,
    );
  }

  TargetPickerItem<T> copyWith({
    String? id,
    String? title,
    String? subtitle,
    String? avatarUrl,
    String? badge,
    String? category,
    bool? disabled,
    String? disabledReason,
    T? data,
  }) {
    return TargetPickerItem<T>(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      badge: badge ?? this.badge,
      category: category ?? this.category,
      disabled: disabled ?? this.disabled,
      disabledReason: disabledReason ?? this.disabledReason,
      data: data ?? this.data,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TargetPickerItem &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// 选择器的配置选项。
@immutable
class TargetPickerOptions {
  const TargetPickerOptions({
    this.title = '选择目标',
    this.subtitle,
    this.multiple = false,
    this.showConfirmButton,
    this.confirmText = '确定',
    this.minCount,
    this.maxCount,
    this.initialSelectedIds = const <String>{},
    this.disabledIds = const <String>{},
    this.enableSearch = true,
    this.searchHint = '搜索名称、备注或简介...',
    this.showSelectedPreviewBar = true,
    this.heightFactor = 0.82,
    this.emptyText = '未找到匹配项',
  });

  /// 弹层标题。
  final String title;

  /// 弹层副标题或说明。
  final String? subtitle;

  /// 是否多选。
  final bool multiple;

  /// 是否显示确定按钮。
  ///
  /// - 多选时默认为 `true`；
  /// - 单选时默认为 `false`（点击列表项直接确定返回）；如果显式设为 `true`，则单选需点击确定按钮。
  final bool? showConfirmButton;

  /// 确定按钮文案。
  final String confirmText;

  /// 最少选择数量限制（低于此值无法确定）。
  final int? minCount;

  /// 最多选择数量限制（达到上限后不可继续选择，并提示用户）。
  final int? maxCount;

  /// 初始已选中的 ID 集合。
  final Set<String> initialSelectedIds;

  /// 禁选的 ID 集合（置灰）。
  final Set<String> disabledIds;

  /// 是否显示搜索输入栏。
  final bool enableSearch;

  /// 搜索框占位文案。
  final String searchHint;

  /// 多选模式下是否在顶部显示已选头像预览条（支持点击移除）。
  final bool showSelectedPreviewBar;

  /// 半屏页高度占比（0.0 ~ 1.0）。
  final double heightFactor;

  /// 空列表提示文字。
  final String emptyText;

  /// 计算实际是否应展示确定按钮。
  bool get effectiveShowConfirmButton =>
      showConfirmButton ?? (multiple ? true : false);

  /// 计算实际最小选择数。
  int get effectiveMinCount => minCount ?? (multiple ? 1 : 0);
}
