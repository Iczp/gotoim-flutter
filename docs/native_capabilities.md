# Native 与设备硬件能力规范 (Native / Device Capabilities)

本文档根据 `AGENTS.md` 第 17 节（Native 能力）与第 25 节（开发诊断中心）规范，详细说明 GotoIM Flutter 客户端的原生/设备硬件能力架构、Dart 门面方法、JSBridge 通信协议、入参与出参格式、事件推送格式及开发诊断中心使用方式。

---

## 1. 架构设计与目录结构

所有 Native 能力统一收敛于 `lib/core/native/`，业务层或 JSBridge 统一通过 `Native` 门面访问，禁止业务页面直接硬编码 MethodChannel 或底层插件。

```text
lib/core/native/
├── native.dart   # 统一门面 Native 及 Riverpod Providers (nativeSystemProvider, nativeDeviceProvider, nativeSensorProvider)
├── system.dart   # 系统级能力 NativeSystem (主题、窗口尺寸、内存告警、截屏监听、拨打电话)
├── device.dart   # 硬件控制 NativeDevice (触觉与振动、电池电量、屏幕亮度读取与调节)
└── sensor.dart   # 运动与环境传感器 NativeSensor (加速度计、陀螺仪、距离传感器及启停注销)
```

### 平台实现与降级原则

1. **Flutter 内置优先**：能使用系统回调（如 `WidgetsBindingObserver`、`HapticFeedback`、`PlatformDispatcher`）的能力直接使用。
2. **成熟插件与原生 Channel**：硬件特定能力（截屏广播、距离传感器、屏幕亮度、精确电量）通过 Android Kotlin (`NativeDevicePlugin.kt`) 与 iOS Swift (`AppDelegate.swift`) 实现。
3. **安全降级**：在桌面端、Web 端或未编译原生代码的测试环境下安全降级并提供默认返回值，杜绝崩溃（No Crash）。
4. **生命周期可注销**：所有事件流均支持显式注销（`offAccelerometer`、`offGyroscope`、`offProximity`、`sub.cancel()`），防止内存泄漏与多余耗电。

---

## 2. 能力清单与参数规范

### 2.1 设备控制 (Device)

#### 1. 设备振动 / 触觉反馈 (`vibrate`)
- **说明**：触发设备振动反馈或系统语义触觉。
- **Dart 调用**：`await Native.vibrate(HapticFeedbackType.medium, [int? durationMs]);`
- **JSBridge Action**：`vibrate` 或 `device.vibrate`
- **入参 (`data`)**：
  ```json
  {
    "style": "light",     // 可选: "light" | "medium" | "heavy" | "selection" | "vibrate"
    "duration": 200       // 可选: 自定义振动毫秒数 (Android/iOS 支持平台有效)
  }
  ```
- **出参 (`data`)**：
  ```json
  { "ok": true }
  ```

#### 2. 获取电池信息 (`getBatteryInfo`)
- **说明**：获取当前设备电量百分比、充电状态及电池状态。
- **Dart 调用**：`BatteryInfo info = await Native.getBatteryInfo();`
- **JSBridge Action**：`getBatteryInfo` 或 `device.getBatteryInfo`
- **入参 (`data`)**：`{}`
- **出参 (`data`)**：
  ```json
  {
    "level": 85,              // 电量百分比 (0 ~ 100)
    "isCharging": true,       // 是否正在充电
    "status": "charging"      // "charging" | "discharging" | "full" | "notCharging" | "unknown"
  }
  ```

#### 3. 读取屏幕亮度 (`getScreenBrightness`)
- **说明**：读取当前应用窗口的屏幕亮度。
- **Dart 调用**：`double brightness = await Native.getScreenBrightness();`
- **JSBridge Action**：`getScreenBrightness` 或 `device.getScreenBrightness`
- **入参 (`data`)**：`{}`
- **出参 (`data`)**：
  ```json
  { "value": 0.8 }            // 亮度值 (0.0 最暗 ~ 1.0 最亮)
  ```

#### 4. 设置屏幕亮度 (`setScreenBrightness`)
- **说明**：调节当前应用窗口的屏幕亮度。
- **Dart 调用**：`bool ok = await Native.setScreenBrightness(0.8);`
- **JSBridge Action**：`setScreenBrightness` 或 `device.setScreenBrightness`
- **入参 (`data`)**：
  ```json
  { "value": 0.8 }            // 浮点数 (0.0 ~ 1.0)
  ```
- **出参 (`data`)**：
  ```json
  { "ok": true, "value": 0.8 }
  ```

#### 5. 后置闪光灯 (`setFlashlight`)
- **说明**：独立于扫码页的闪光灯控制，打开或关闭设备后置摄像头 Torch。
- **Dart 调用**：`await Native.setFlashlight(true);`
- **JSBridge Action**：`setFlashlight` 或 `device.setFlashlight`
- **平台**：Android、iOS；没有后置闪光灯或未获相机访问许可时返回 `false`。
- **入参 / 出参**：`{ "enabled": true }` → `{ "ok": true, "enabled": true }`

#### 6. 媒体音量 (`getSystemVolume` / `setSystemVolume`)
- **说明**：读取或设置媒体输出音量，范围为 `0.0 ~ 1.0`。
- **Dart 调用**：`await Native.getSystemVolume();`、`await Native.setSystemVolume(0.5);`
- **JSBridge Action**：`device.getSystemVolume`、`device.setSystemVolume`
- **平台**：Android、iOS；其他平台读取返回 `-1`，设置返回 `false`。

---

### 2.2 系统能力与事件 (System)

#### 1. 拨打电话 (`makePhoneCall`)
- **说明**：调起系统拨号盘并填入目标号码。
- **Dart 调用**：`bool ok = await Native.makePhoneCall("10086");`
- **JSBridge Action**：`makePhoneCall` 或 `system.makePhoneCall`
- **入参 (`data`)**：
  ```json
  { "phoneNumber": "10086" }
  ```
- **出参 (`data`)**：
  ```json
  { "ok": true }
  ```

#### 2. 桌面角标 (`setDesktopBadge`)
- **说明**：设置 macOS Dock 中的应用角标，传 `0`、负数或 `null` 清除角标。
- **Dart 调用**：`await Native.setDesktopBadge(12);`
- **JSBridge Action**：`setDesktopBadge` 或 `desktop.setBadge`
- **平台**：当前仅 macOS；Windows、Linux、Web 和移动端安全返回 `false`。

#### 3. 用户截屏监听 (`onUserCaptureScreen` / `offUserCaptureScreen`)
- **说明**：监听用户在 App 内主动执行的截屏操作。
- **Dart 调用**：
  ```dart
  final sub = Native.onUserCaptureScreen((timestamp) {
    print('用户截屏时间: $timestamp');
  });
  ```
- **JSBridge 订阅 Action**：`onUserCaptureScreen` 或 `system.onUserCaptureScreen`
  - 入参：`{ "subscriptionId": "ss-1" }`（可选，未填则自动生成 UUID）
  - 出参：`{ "subscriptionId": "ss-1" }`
- **JSBridge 推送事件** (`system.userCaptureScreen`)：
  ```json
  {
    "event": "system.userCaptureScreen",
    "data": {
      "subscriptionId": "ss-1",
      "timestamp": "2026-08-22T17:40:00.000Z"
    }
  }
  ```
- **JSBridge 取消订阅 Action**：`offUserCaptureScreen`
  - 入参：`{ "subscriptionId": "ss-1" }`
  - 出参：`{ "removed": true }`

#### 4. 系统主题变化监听 (`onThemeChange` / `offThemeChange`)
- **说明**：监听系统明暗模式（Light / Dark）切换。
- **Dart 调用**：
  ```dart
  final sub = Native.onThemeChange((brightness) {
    print('系统主题切换为: ${brightness.name}');
  });
  ```
- **JSBridge 订阅 Action**：`onThemeChange` 或 `system.onThemeChange`
  - 出参：`{ "subscriptionId": "theme-1", "currentBrightness": "light" }`
- **JSBridge 推送事件** (`system.themeChange`)：
  ```json
  {
    "event": "system.themeChange",
    "data": {
      "subscriptionId": "theme-1",
      "brightness": "dark"     // "light" | "dark"
    }
  }
  ```
- **JSBridge 取消订阅 Action**：`offThemeChange`

#### 5. 窗口尺寸与旋转监听 (`onResize` / `offResize`)
- **说明**：监听窗口大小改变、平板折叠屏展开或屏幕横竖屏旋转。
- **Dart 调用**：
  ```dart
  final sub = Native.onResize((size) {
    print('新窗口尺寸: ${size.width}x${size.height}');
  });
  ```
- **JSBridge 订阅 Action**：`onResize` 或 `system.onResize`
  - 出参：`{ "subscriptionId": "resize-1", "currentSize": { "width": 1080, "height": 2400 } }`
- **JSBridge 推送事件** (`system.resize`)：
  ```json
  {
    "event": "system.resize",
    "data": {
      "subscriptionId": "resize-1",
      "width": 2400,
      "height": 1080
    }
  }
  ```
- **JSBridge 取消订阅 Action**：`offResize`

#### 6. 内存不足告警监听 (`onMemoryWarning` / `offMemoryWarning`)
- **说明**：监听系统低内存压力警告，用于触发缓存清理。
- **Dart 调用**：
  ```dart
  final sub = Native.onMemoryWarning((timestamp) {
    print('收到系统低内存警告!');
  });
  ```
- **JSBridge 订阅 Action**：`onMemoryWarning` 或 `system.onMemoryWarning`
  - 出参：`{ "subscriptionId": "mem-1" }`
- **JSBridge 推送事件** (`system.memoryWarning`)：
  ```json
  {
    "event": "system.memoryWarning",
    "data": {
      "subscriptionId": "mem-1",
      "timestamp": "2026-08-22T17:40:00.000Z"
    }
  }
  ```
- **JSBridge 取消订阅 Action**：`offMemoryWarning`

---

### 2.3 传感器能力 (Sensor)

#### 1. 加速度计 (`onAccelerometerChange` / `offAccelerometerChange`)
- **说明**：获取 3 轴加速度计数据（X, Y, Z m/s²），默认约 5 次/秒（200ms 间隔）。
- **Dart 调用**：
  ```dart
  final sub = Native.onAccelerometerChange((event) {
    print('加速度 X: ${event.x}, Y: ${event.y}, Z: ${event.z}');
  }, intervalMs: 200);
  
  // 取消监听
  Native.offAccelerometer();
  ```
- **JSBridge 订阅 Action**：`onAccelerometerChange` 或 `sensor.onAccelerometerChange`
  - 入参：`{ "subscriptionId"?: "acc-1", "interval"?: 200 }`
  - 出参：`{ "subscriptionId": "acc-1" }`
- **JSBridge 推送事件** (`sensor.accelerometerChange`)：
  ```json
  {
    "event": "sensor.accelerometerChange",
    "data": {
      "subscriptionId": "acc-1",
      "x": 0.12,
      "y": 9.81,
      "z": -0.05,
      "timestamp": "2026-08-22T17:40:00.000Z"
    }
  }
  ```
- **JSBridge 取消订阅 Action**：`offAccelerometerChange`

#### 2. 陀螺仪 (`onGyroscopeChange` / `offGyroscopeChange`)
- **说明**：获取 3 轴角速度陀螺仪数据（X, Y, Z rad/s）。
- **Dart 调用**：
  ```dart
  final sub = Native.onGyroscopeChange((event) {
    print('角速度 X: ${event.x}, Y: ${event.y}, Z: ${event.z}');
  }, intervalMs: 200);
  
  // 取消监听
  Native.offGyroscope();
  ```
- **JSBridge 订阅 Action**：`onGyroscopeChange` 或 `sensor.onGyroscopeChange`
  - 入参：`{ "subscriptionId"?: "gyro-1", "interval"?: 200 }`
  - 出参：`{ "subscriptionId": "gyro-1" }`
- **JSBridge 推送事件** (`sensor.gyroscopeChange`)：
  ```json
  {
    "event": "sensor.gyroscopeChange",
    "data": {
      "subscriptionId": "gyro-1",
      "x": 0.01,
      "y": -0.02,
      "z": 0.05,
      "timestamp": "2026-08-22T17:40:00.000Z"
    }
  }
  ```
- **JSBridge 取消订阅 Action**：`offGyroscopeChange`

#### 3. 距离传感器 (`onProximityChange` / `offProximityChange`)
- **说明**：检测是否有物体贴近屏幕（如通话贴耳）。
- **Dart 调用**：
  ```dart
  final sub = Native.onProximityChange((event) {
    print('是否贴近: ${event.isNear}, 距离: ${event.distance}cm');
  });
  
  // 取消监听
  Native.offProximity();
  ```
- **JSBridge 订阅 Action**：`onProximityChange` 或 `sensor.onProximityChange`
  - 出参：`{ "subscriptionId": "prox-1" }`
- **JSBridge 推送事件** (`sensor.proximityChange`)：
  ```json
  {
    "event": "sensor.proximityChange",
    "data": {
      "subscriptionId": "prox-1",
      "distance": 0.0,
      "isNear": true
    }
  }
  ```
- **JSBridge 取消订阅 Action**：`offProximityChange`

---

## 3. 平台支持矩阵

| 能力 | Android | iOS / iPad | Windows | macOS | Linux | Web |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| 截屏监听 (`onUserCaptureScreen`) | ✓ (ContentObserver) | ✓ (NotificationCenter) | 降级 | 降级 | 降级 | 降级 |
| 振动 / 触觉 (`vibrate`) | ✓ (Vibrator/Haptics) | ✓ (UIFeedbackGenerator) | 降级 | 降级 | 降级 | ✓ (navigator.vibrate) |
| 系统主题 (`onThemeChange`) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| 窗口尺寸 (`onResize`) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| 内存告警 (`onMemoryWarning`) | ✓ | ✓ | ✓ | ✓ | ✓ | 降级 |
| 加速度计 (`onAccelerometerChange`) | ✓ (SensorManager) | ✓ (CMMotionManager) | 降级 | 降级 | 降级 | 降级 |
| 陀螺仪 (`onGyroscopeChange`) | ✓ (SensorManager) | ✓ (CMMotionManager) | 降级 | 降级 | 降级 | 降级 |
| 距离传感器 (`onProximityChange`) | ✓ (SensorManager) | ✓ (proximityMonitoring) | 降级 | 降级 | 降级 | 降级 |
| 拨打电话 (`makePhoneCall`) | ✓ (ACTION_DIAL) | ✓ (tel: URL) | 降级 | 降级 | 降级 | ✓ (tel: link) |
| 屏幕亮度 (`get/setScreenBrightness`)| ✓ (Window Attributes) | ✓ (UIScreen) | 降级 | 降级 | 降级 | 降级 |
| 电量信息 (`getBatteryInfo`) | ✓ (BatteryManager) | ✓ (UIDevice.battery) | 降级 (100%) | 降级 (100%) | 降级 (100%) | ✓ (getBattery) |
| 后置闪光灯 (`setFlashlight`) | ✓ (CameraManager) | ✓ (AVCaptureDevice) | 降级 | 降级 | 降级 | 降级 |
| 媒体音量 (`get/setSystemVolume`) | ✓ (AudioManager) | ✓ (AVAudioSession / MPVolumeView) | 降级 | 降级 | 降级 | 降级 |
| 桌面角标 (`setDesktopBadge`) | 降级 | 降级 | 降级 | ✓ (Dock badge) | 降级 | 降级 |

---

## 4. 开发诊断中心

在 **开发诊断中心** 中提供两个对应测试入口：

1. **Native / Device 设备能力 (`/diagnostics/native`)**：
   - 实时传感器波形与数值监控（加速度计 X/Y/Z、陀螺仪 X/Y/Z、距离传感器）。
   - 硬件控制测试（电池电量进度条、屏幕亮度滑块、多档振动反馈、拨打电话输入与发起）。
   - 系统级事件实时日志（主题切换、屏幕旋转尺寸、内存告警计数、用户截屏事件通知）。
   - 平台支持状态指示芯片。
2. **JS Bridge 测试与 Harness (`/diagnostics/js-bridge` & `/diagnostics/js-bridge-harness`)**：
   - 提供 Native JSAPI 全部预设按钮（电量查询、设备振动、读取亮度、设置亮度、拨打电话、截屏监听、加速度计、陀螺仪、距离传感器、主题变化、内存告警、窗口尺寸）。
   - 包含双向 JSON 调度输入框、响应结果面板与异步事件推送实时展示。
