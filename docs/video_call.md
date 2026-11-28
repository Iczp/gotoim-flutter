# GotoIM Flutter 音视频通话与屏幕共享方案（`gotoim-flutter` 冻结候选版）

> 适用仓库：`gotoim-flutter`（Android / iOS / Windows / macOS）  
> 后端协议基准：[`IczpNet.Chat/docs/protocols/video-call/v1/specification.md`](../../../abpvnext/IczpNet.Chat/docs/protocols/video-call/v1/specification.md)

---

## 1. 逐平台能力边界承诺（V1 冻结范围）

根据 `lib/core/realtime/signalr_gateway_factory.dart` 当前实现（Web 平台走 `signalr_gateway_stub.dart` 无实时 SignalR 长连接），V1 对各平台能力做如下硬性边界承诺：

| 平台 | 前台来电/通话 | 发起屏幕共享 | 观看屏幕共享 | 后台/锁屏来电 |
| --- | --- | --- | --- | --- |
| **Android** | ✅ V1 必选 | ✅ V1 必选（`MediaProjection` 前台服务） | ✅ V1 必选 | ⏳ **V1.1**（需补齐 FCM/厂商推送 + Telecom ConnectionService 契约与验收） |
| **iOS** | ✅ V1 必选 | ⏳ **V1.1**（需 Xcode 新建 ReplayKit `BroadcastUploadExtension`） | ✅ V1 必选 | ⏳ **V1.1**（需补齐 APNs VoIP PushKit + CallKit 契约与验收） |
| **Windows / macOS** | ✅ V1 必选 | ✅ V1 必选（桌面端屏幕/窗口选择） | ✅ V1 必选 | ❌ 仅桌面端运行态（托盘保活） |
| **Web** | ❌ V1 不支持 | ❌ V1 不支持 | ❌ V1 不支持 | ❌（当前 `signalr_gateway_stub.dart` 无实时长连接，UI 隐藏通话入口） |

---

## 2. 依赖与平台权限配置

### 2.1 `pubspec.yaml`
新增依赖：
- `livekit_client`（统一封装 Android / iOS / Windows / macOS 音视频、Simulcast、内置 TURN 协商、房间与屏幕共享轨道）

### 2.2 开发期无 SSL 证书局域网联调配置
- **Android**：
  - `android/app/src/main/AndroidManifest.xml`：配置 `CAMERA`、`RECORD_AUDIO`、`MODIFY_AUDIO_SETTINGS`、`BLUETOOTH_CONNECT`、`FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_MEDIA_PROJECTION`；
  - 开发构建通过 `network_security_config.xml` 放行局域网服务器 IP（如 `10.0.5.20`）的明文 `ws://` / `http://` 流量。
- **iOS**：
  - `ios/Runner/Info.plist`：配置 `NSCameraUsageDescription`、`NSMicrophoneUsageDescription`、`NSLocalNetworkUsageDescription`，启用 `UIBackgroundModes -> audio`。
- **Windows / macOS**：
  - macOS `.entitlements` 配置摄像头、麦克风与网络权限。

---

## 3. 核心模块规划（`lib/features/call/`）

```text
lib/features/call/
  data/
    call_api.dart                 # 对接 /api/chat/call/* (全写操作带 requestId 幂等键)
    call_models.dart              # CallMode / CallMediaType / CallEndReason / ActiveCallSnapshotDto / CallJoinResultDto
  application/
    call_controller.dart          # Riverpod Notifier：双域 stateVersion 控制、active 对账清理、heartbeat (30s)、refreshToken、room_rotated 换房
    call_ringtone_service.dart    # 来电响铃与震动控制（受 personalStateVersion 与 dismissedCallIds 保护）
  presentation/
    incoming_call_overlay.dart    # 前台全局来电悬浮/全屏接听界面
    call_room_page.dart           # 路由 /call/:callId（1v1 大小窗、群宫格/焦点+屏幕共享捏合缩放、设备/扬声器切换）
    group_call_banner.dart        # 群聊会话顶部“X 人正在通话中 [加入]”横幅
    widgets/
      call_message_bubble.dart    # ChatMessage messageType == 20 气泡渲染（1v1 支持一键回拨，禁用转发）
```

---

## 4. 关键协议对接与验收清单

1. **双域版本号与 `active` 对账清理**：
   - `SignalRGateway` 注册 `call.*@rtc` 事件至 `CallController`。
   - 对每个 `callId` 分别维护 **`personalStateVersion`** 与 **`bannerStateVersion`**：`call.room_updated@rtc` 仅更新 `bannerStateVersion`，绝不导致同版本 `call.invited@rtc` 被误丢；已进入本地 `Accepted/Rejected/Handled/Ended` 的 `callId` 不再因任何 `call.invited@rtc` 重新响铃。
   - SignalR 建连/重连后调用 `GET /api/chat/call/active`：本地响铃/通话若在服务端快照中已消失（或 `boundDeviceId != 本机 deviceId`），立即停铃或退出房间。
2. **URL 与内置 TURN 约定**：
   - `livekit_client` 自动追加 `/rtc`，客户端直接将 `rtcUrl`（如 `ws://10.0.5.20:7880` 或经 Caddy 代理时 `ws://10.0.5.20:8044`）传入 `Room.connect(rtcUrl, token, roomOptions: ..., connectOptions: ConnectOptions(rtcConfiguration: RTCConfiguration(iceTransportPolicy: ...)))`，不手动拼接 `/rtc`；TURN 由 LiveKit 信令自动下发，不另传静态 `iceServers`。
3. **`MessageTypes.Call = 20` 适配与转发限制**：
   - `ChatMessage`（`lib/features/chat/data/models/chat_message.dart`）支持解析 `messageType == 20` 与 `CallContentInfo`；未知/损坏结构降级渲染安全文案；
   - 气泡长按转发与多选合并转发均禁用 `messageType == 20`。
4. **验收测试清单**：
   - `stateVersion` 双域乱序与 `active` 快照消失停铃单元测试；
   - Web 平台自动隐藏通话入口验证，iOS 平台隐藏发起共享按钮但正常观看桌面端共享；
   - Android/iOS/Windows/macOS 前台与 Electron 互呼、同账号双端抢占 1 秒内停铃、Android 发起屏幕共享（通知栏前台服务保活）、强制 `relay` 模式下 WebRTC Stats 验证 `relay` 双向互通、断网 20s 内重连恢复、被踢出群后 `room_rotated` 无感切换。
