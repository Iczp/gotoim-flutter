# GotoIM Flutter 音视频通话与屏幕共享方案（`gotoim-flutter`）

> 适用仓库：`gotoim-flutter`（Android / iOS / Windows / macOS / Web）  
> 协议基线：[`IczpNet.Chat/docs/protocols/video-call/v1/specification.md`](../../abpvnext/IczpNet.Chat/docs/protocols/video-call/v1/specification.md)

---

## 1. 依赖与平台权限配置

### 1.1 `pubspec.yaml`
新增依赖：
- `livekit_client`（统一封装 WebRTC、Simulcast、房间与音视频轨道管理）

### 1.2 开发期无 SSL 证书局域网联调配置
- **Android**：
  - `android/app/src/main/AndroidManifest.xml`：增加 `CAMERA`、`RECORD_AUDIO`、`MODIFY_AUDIO_SETTINGS`、`BLUETOOTH_CONNECT`（Android 12+ 蓝牙耳机路由）、`FOREGROUND_SERVICE` 与 `FOREGROUND_SERVICE_MEDIA_PROJECTION`（屏幕共享必需）；开发期配置 `android:usesCleartextTraffic="true"` 或在 `network_security_config.xml` 放行局域网 IP（如 `10.0.5.20`）的 `ws://` 与 `http://` 通信。
- **iOS**：
  - `ios/Runner/Info.plist`：配置 `NSCameraUsageDescription`、`NSMicrophoneUsageDescription`、`NSLocalNetworkUsageDescription`，开启后台音频模式 `UIBackgroundModes -> audio`（防止锁屏或切后台通话断音）。
  - 若 V1 在 iOS 需支持**发起屏幕共享**，需在 Xcode 新建 ReplayKit `BroadcastUploadExtension` App Group；若 iOS 首期仅支持“观看桌面端屏幕共享 + 自身摄像头/麦克风”，可暂缓 Extension。
- **Windows / macOS**：
  - macOS 在 `.entitlements` 中配置相机、麦克风与网络客户端权限。

---

## 2. 核心模块规划（`lib/features/call/`）

```text
lib/features/call/
  data/
    call_api.dart                 # 对接 /api/chat/call/* (invite/accept/join/reject/cancel/hangup/active/refresh-token)
    call_models.dart              # CallMode / CallMediaType / CallEndReason / CallJoinResult / CallContentInfo
  application/
    call_controller.dart          # Riverpod Notifier：维护全局唯一活跃通话状态、Room 连接与重连恢复
    call_ringtone_service.dart    # 来电响铃与震动控制（收到 call.handled@rtc / call.canceled@rtc 立即停铃）
  presentation/
    incoming_call_overlay.dart    # 全局来电悬浮/全屏接听界面（1v1 与群通话均适用）
    call_room_page.dart           # 路由 /call/:callId（1v1 大小窗切换、群通话宫格/焦点+屏幕共享视图、音频设备切换）
    group_call_banner.dart        # 群聊会话顶部“X 人正在通话中 [加入]”横幅
    widgets/
      call_message_bubble.dart    # ChatMessage messageType == 20 气泡渲染与一键回拨
```

### 关键对接点
1. **SignalR 信令接入（`lib/core/realtime/signalr_gateway.dart`）**：
   - 注册 `call.invited@rtc`、`call.accepted@rtc`、`call.rejected@rtc`、`call.canceled@rtc`、`call.handled@rtc`、`call.room_updated@rtc`、`call.ended@rtc` 到统一流，转发给 `CallController`。
   - SignalR 重连成功后自动调用 `GET /api/chat/call/active` 同步服务端状态（防止后台断网错过结束或停铃指令）。
2. **`MessageTypes.Call = 20` 适配（`lib/features/chat/`）**：
   - 更新 `ChatMessage` 及会话最后一条消息摘要：支持解析 `messageType == 20` 与 `CallContentInfo`（展示时长/未接来电/群通话），并支持点击 1v1 气泡直接发起同媒体类型回拨。
   - Drift 本地数据库无需为瞬态信令建表，仅通过现有消息同步链路保存结束后的通话记录消息。
3. **屏幕共享适配**：
   - 使用 `livekit_client` 的 `LocalParticipant.setScreenShareEnabled(true)`：
     - Windows/macOS 弹出系统/窗口选择列表；
     - Android 弹出系统录屏授权并拉起 `MediaProjection` 前台通知；
     - 任一端发布 `TrackSource.screenShareVideo` 后，移动端通话页自动切换至主画面展示共享内容，并支持双指捏合缩放查看细节。
