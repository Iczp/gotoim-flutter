import 'native.dart';

/// 统一触感与振动反馈门面 (App Haptic & Vibration Facade).
///
/// 针对华为 (HarmonyOS / EMUI)、荣耀等品牌手机在 Flutter [HapticFeedback] 下
/// 因系统全局开关或焦点问题导致无触感反馈的情况，采用「原生底层硬件 Vibrator + 系统触感」
/// 双通道保障机制，提供高可用且细腻的触觉体验。
class AppHaptics {
  AppHaptics._();

  /// 选择项切换触感（18ms 微振动），适用于：
  /// - 通讯录字母索引滑动切换
  /// - 轮播图指示器切换
  /// - Picker 滚轮齿轮感
  static Future<void> selection() {
    return Native.device.vibrate(
      type: HapticFeedbackType.selection,
      durationMs: 18,
    );
  }

  /// 轻度触感（25ms 轻击），适用于：
  /// - 按钮点击
  /// - Tab 切换
  /// - 开关切换
  static Future<void> light() {
    return Native.device.vibrate(
      type: HapticFeedbackType.light,
      durationMs: 25,
    );
  }

  /// 中度触感（40ms 敲击），适用于：
  /// - 列表项长按（如会话列表长按弹出操作 Sheet）
  /// - 消息气泡长按弹出菜单
  /// - 拖拽开始 / 释放
  static Future<void> medium() {
    return Native.device.vibrate(
      type: HapticFeedbackType.medium,
      durationMs: 40,
    );
  }

  /// 重度触感（65ms 顿挫），适用于：
  /// - 删除、撤回、清空等危险操作
  /// - 校验失败、错误警报
  static Future<void> heavy() {
    return Native.device.vibrate(
      type: HapticFeedbackType.heavy,
      durationMs: 65,
    );
  }

  /// 自定义或较长振动（默认 100ms），适用于新消息提醒或系统提醒。
  static Future<void> vibrate([int durationMs = 100]) {
    return Native.device.vibrate(
      type: HapticFeedbackType.vibrate,
      durationMs: durationMs,
    );
  }
}
