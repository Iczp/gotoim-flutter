# SignalR 网关

## 配置

SignalR 配置位于项目根目录的环境文件中：

| 配置项 | 含义 |
| --- | --- |
| `SIGNALR_BASE_URL` | 聊天实时服务地址 |
| `SIGNALR_HUB_PATH` | 当前 UniApp 聊天 Hub：`/signalr-hubs/chat` |
| `SIGNALR_SKIP_NEGOTIATION` | 仅当服务端支持直连 WebSocket 时设为 `true` |
| `SIGNALR_RECONNECT_DELAYS_MS` | 逗号分隔的重试延迟，例如 `0,2000,10000,30000` |

`SignalRNetcoreGateway` 使用 `HttpTransportType.WebSockets`，注册唯一的
应用级 `ReceivedMessage` 回调，并通过 `accessTokenFactory` 从
`TokenStorage` 读取当前 access token。不会为每一个聊天页面建立连接。

Hub URL 会追加与现有 UniApp 一致的设备查询参数：`appId`、`appName`、
`deviceId`、`deviceType`、`pushClientId`、`brand`、`model`、`platform`、
`browser`。当前尚未接入推送 SDK，因此 `pushClientId` 为空；接入 FCM/APNs
后由平台适配层提供该值，不影响业务代码。

## 事件模型

当前 UniApp 应用接收 `ReceivedMessage` 信封并按其中的 `command` 分发。
Flutter 网关保留这些 command 值，并转为类型化枚举：

| SignalR `command` | Flutter 枚举 |
| --- | --- |
| `offline@me` / `online@me` | `offlineMe` / `onlineMe` |
| `offline@friend` / `online@friend` | `offlineFriend` / `onlineFriend` |
| `created@message` | `messageCreated` |
| `forwarded@message` | `messageForwarded` |
| `updated@message` | `messageUpdated` |
| `updated-badge@message` | `messageBadgeUpdated` |
| `rollbacked@message` | `messageRollbacked` |
| `changed@session-unit` | `sessionUnitChanged` |
| `kicked` / `welcome` | `kicked` / `welcome` |

未知或格式不正确的信封会成为 `SignalRUnknownCommandEvent`，不会被静默丢弃。
连接状态变化会产生 `SignalRConnectionEvent`，状态包括 `connecting`、
`connected`、`reconnecting`、`disconnecting`、`disconnected`。

## Repository 使用方式

组合根提供 `signalRGatewayProvider`，认证成功之前不会连接。`AuthController`
会在登录成功或会话恢复后启动连接，并在退出登录时断开。Repository 而不是 UI
订阅命令流：

```dart
gateway.events.forCommand(SignalRCommand.messageCreated).listen((event) async {
  // 校验 DTO -> 写入/更新 Drift -> Riverpod 监听数据库更新 UI
});
```

重连后的 `connected` 事件到达时，Repository 必须执行 HTTP 增量同步。SignalR
是低延迟通知通道，不是离线数据的权威来源，不能直接用它更新页面状态。

## 初始连接失败与重试

自动重连仅适用于已经建立过的连接。认证或应用生命周期层应决定首次
`connect()` 失败后的重试策略（通常应采用有上限、可观测的退避策略），不能让
登录页无限等待。该行为与 [Microsoft SignalR 客户端文档](https://learn.microsoft.com/en-us/aspnet/core/signalr/javascript-client?view=aspnetcore-10.0)
描述的重连模型一致。

## 平台说明

当前项目锁定 `signalr_netcore` 1.3.6，以兼容已安装的 Dart 2.19 SDK。因此 IO
实现覆盖 Android、iOS、Windows、macOS 和 Linux。Web 条件实现当前为明确的
不支持桩；待升级 Flutter SDK 并验证可用的 Web SignalR 客户端后再实现。共享
业务代码不依赖任何平台 API。

## 开发诊断入口

Debug 模式下，首页右上角进入“开发诊断中心”。认证页允许查看、复制并手动操作
Token，仅用于本地联调；接口与 SignalR 页用于业务 API 和 Hub 验证。诊断页不会
在 Release 构建中提供内容，且不得截图、录屏或提交敏感输出。
