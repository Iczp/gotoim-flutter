# GotoIM Flutter 音视频通话与屏幕共享方案（`gotoim-flutter` 冻结基线）

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
| **Web** | ❌ V1 不支持 | ❌ 不支持 | ❌ 不支持 | ❌（当前 `signalr_gateway_factory.dart` 走 `stub` 无实时长连接，UI 隐藏通话入口） |

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
    call_api.dart                 # 对接 /api/chat/call/* (全写操作带 requestId 幂等键，accept/reject 绑定传入 inviteRound)
    call_models.dart              # CallMode / CallMediaType / CallEndReason / ActiveCallSnapshotDto / CallJoinResultDto / CallHeartbeatResultDto
  application/
    call_controller.dart          # Riverpod Notifier：双域 stateVersion、轮次去重、范围收敛 active 对账、heartbeat/断开主动换房
    call_ringtone_service.dart    # 来电响铃与震动控制（受 personalStateVersion 与 dismissedInviteKeys 保护）
  presentation/
    incoming_call_overlay.dart    # 前台全局来电悬浮/全屏接听界面
    call_room_page.dart           # 路由 /call/:callId（1v1 大小窗、群宫格/焦点+屏幕共享捏合缩放、设备/扬声器切换）
    group_call_banner.dart        # 群聊会话顶部“X 人正在通话中 [加入]”横幅
    widgets/
      call_message_bubble.dart    # ChatMessage messageType == 20 气泡渲染（1v1 支持一键回拨，禁用转发）
```

---

## 4. 关键协议对接与验收清单

1. **双域版本号、轮次去重与 `active` 范围/序号对账**：
   - `SignalRGateway` 注册 `call.*@rtc` 事件至 `CallController`。
   - 对每个 `callId` 分别维护 **`personalStateVersion`** 与 **`bannerStateVersion`**：`call.room_updated@rtc` 仅更新 `bannerStateVersion`，绝不误丢同版本 `call.invited@rtc`。
   - 按 **`dismissedInviteKeys`（`${callId}:${inviteRound}`）** 抑制已处理轮次的迟到来电，支持 `inviteMore` 发起新一轮（`inviteRound++`）时正常重新响铃。
   - **范围收敛与乱序淘汰**：
     - 按 `(accountId, scopeKey)`（`'global'` 或 `'session:' + sessionId`）维护请求序号 `lastIssuedSeq` / `lastAppliedSeq`：响应返回若 `reqSeq < lastIssuedSeq` 或 `<= lastAppliedSeq` 直接丢弃整份响应；
     - 未传 `sessionId` 的 `'global'` 查询**禁止清理任何群横幅 `sessionGroupCall`**，仅显式传 `sessionId` 的查询才核对并清理对应群横幅；
     - 仅清理 `item.updatedAtEpoch <= queryStartEpoch` 的本地对象，查询 RTT 期间的新通话/新来电不被旧快照误挂断。
2. **被动断开 & 心跳 `roomEpoch` 主动换房恢复**：
   - `heartbeat`（30s）若发现服务端 `roomEpoch > localRoomEpoch`（哪怕丢失了 `call.room_rotated@rtc`），立即调 `refresh-token` 切换至新房间；
   - LiveKit `RoomDisconnectedEvent`（非本端主动挂断）触发时立即调用 `GET /api/chat/call/active` 对账：若 `currentCall` 仍在且 `boundDeviceId` 匹配本机设备，立即调用 `refresh-token` 重连新房，否则清理退出。
3. **URL 与内置 TURN 约定**：
   - `livekit_client` 自动追加 `/rtc`，客户端直接将 `rtcUrl`（不手动拼接 `/rtc`）及 `iceTransportPolicy` 传入 `Room.connect(rtcUrl, token, connectOptions: ConnectOptions(rtcConfiguration: RTCConfiguration(iceTransportPolicy: ...)))`；TURN 由 LiveKit 信令自动下发。
4. **`MessageTypes.Call = 20` 适配与转发限制**：
   - `ChatMessage`（`lib/features/chat/data/models/chat_message.dart`）支持解析 `messageType == 20` 与 `CallContentInfo`；未知/损坏结构降级渲染安全文案；
   - 气泡长按转发与多选合并转发均禁用 `messageType == 20`。
5. **验收测试清单**：
   - `stateVersion` 双域乱序、`(callId, inviteRound)` 再次邀请响铃（含第 1 轮迟到 `accept`/`reject` 不影响第 2 轮）、`'global'` 查询不误清群横幅、同范围旧非空响应被 `reqSeq` 淘汰、`updatedAtEpoch > queryStartEpoch` 不被空快照误挂断等单元测试；
   - Web 平台自动隐藏通话入口验证，iOS 平台隐藏发起共享按钮但正常观看桌面端共享；
   - Android/iOS/Windows/macOS 前台语音聊天与视频聊天均与 Electron 正常互呼、同账号双端抢占 1 秒内停铃、Android 发起屏幕共享、丢包 `call.room_rotated@rtc` 下经 `heartbeat`/`RoomDisconnected` 主动换房恢复、强制 `relay` 模式下 WebRTC Stats 验证 `relay` 双向互通。
