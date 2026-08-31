# 扫码登录协议与实现说明

> 适用对象：实现或维护 Goto IM 手机端、桌面端、Web 端扫码登录的开发者和 AI。
>
> 本文以当前 Flutter 实现和原 UniApp 实现为事实来源；后端 DTO 未包含在本仓库，因此所有未在客户端明确使用的返回字段都不应擅自依赖。文中的示例值均为虚构值，不能当作真实凭据使用。

## 1. 目标与角色

扫码登录让**待登录端**（通常为桌面/Web）显示二维码，由已登录的**授权端**（通常为手机）扫描并确认。二维码不是登录凭据；授权成功后，后端仅通过待登录端的 SignalR 连接发送一次短期 `scanToken`，待登录端再将它兑换成标准 OAuth Token。

| 角色 | 责任 | 身份状态 |
| --- | --- | --- |
| 待登录端 | 建立扫描专用 Hub 连接、生成并显示二维码、监听结果、用 `scanToken` 登录 | 未登录；持有 client-credentials Token |
| 授权端 | 扫码、校验二维码、展示目标设备和四位校验码、同意/拒绝/取消 | 必须已登录；持有用户 AccessToken |
| API / ScanLogin Hub | 维护二维码挑战与连接关联、校验、发出事件、签发一次性 `scanToken` | 服务端 |
| OAuth 服务 | 为 Hub 发放 client-credentials Token；用 `scan_token` 兑换用户会话 Token | 服务端 |

## 2. 端点、Hub 地址与配置

### 2.1 当前开发环境的 Hub 地址

当前 `.env.development` 配置解析出的扫描专用 Hub 地址为：

```text
http://10.0.5.20:8044/signalr-hubs/scan-login
```

这是开发环境地址，不应写死到业务代码。生产/测试环境都必须由下列配置拼接：

```text
SCAN_LOGIN_SIGNALR_BASE_URL + SCAN_LOGIN_HUB_PATH
```

默认路径为 `/signalr-hubs/scan-login`。若未单独设置 `SCAN_LOGIN_SIGNALR_BASE_URL`，Flutter 会回退到 `SIGNALR_BASE_URL`。连接采用 WebSocket，当前默认 `SIGNALR_SKIP_NEGOTIATION=true`。

### 2.2 必需配置

| 配置 | 作用 | 默认/说明 |
| --- | --- | --- |
| `API_BASE_URL` | 授权端调用 `/api/chat/scan-login/**` 的 API 根地址 | 必填 |
| `SCAN_LOGIN_SIGNALR_BASE_URL` | 待登录端扫描专用 SignalR 根地址 | 可回退到 `SIGNALR_BASE_URL` |
| `SCAN_LOGIN_HUB_PATH` | ScanLogin Hub 路径 | `/signalr-hubs/scan-login` |
| `SCAN_LOGIN_TEMPLATE` | 二维码 URI 模板 | `gotoim://scan-login?code={code}` |
| `SCAN_LOGIN_QR_EXPIRES_SECONDS` | 服务端没有 `expiredTime` 时的客户端倒计时兜底 | `90` 秒 |
| `SCAN_LOGIN_AUTH_BASE_URL` | 待登录端取得 Hub 连接 Token 的 OAuth 根地址 | 可回退到 `AUTH_BASE_URL` |
| `SCAN_LOGIN_AUTH_TOKEN_PATH` | OAuth Token 路径 | 可回退到 `/connect/token` |
| `SCAN_LOGIN_AUTH_CLIENT_ID` | client-credentials 的客户端 ID | 必填 |
| `SCAN_LOGIN_AUTH_CLIENT_SECRET` | client-credentials 的客户端密钥 | 仅配置注入，禁止写入代码、日志或文档 |
| `SCAN_LOGIN_AUTH_SCOPE` | Hub client-credentials scope | 当前为 `IM` |

### 2.3 HTTP API 一览

以下路径相对 `API_BASE_URL`。当前 Flutter 全部使用 `GET`；查询参数应 URL 编码，且参数放 query string 而非 JSON body。

| API | 鉴权 | 查询参数 | 用途 |
| --- | --- | --- | --- |
| `GET /api/chat/scan-code/scan` | 用户 AccessToken | `content`、可选 `type` | 统一识别扫码内容，确认其被后端标为 `scan-login` |
| `GET /api/chat/scan-login/scan` | 用户 AccessToken | `scanText` | 读取二维码挑战、目标设备、授权账号和有效期；成功后待登录端会收到 `scanned` |
| `GET /api/chat/scan-login/grant` | 用户 AccessToken | `scanText` | 同意登录；成功后待登录端会收到 `granted` 和 `scanToken` |
| `GET /api/chat/scan-login/reject` | 用户 AccessToken | `scanText`、可选 `reason` | 拒绝登录；待登录端收到 `rejected` |
| `GET /api/chat/scan-login/cancel` | 用户 AccessToken | `connectionId`、可选 `reason` | 授权页关闭或二维码过期时取消未完成挑战；待登录端收到 `cancelled` |

兼容提示：旧 UniApp 代码还定义了 `GET /api/chat/scan-login/generate`，但当前 Flutter 的二维码生成已迁移到 Hub 方法 `Generate`，新实现不得混用两个生成入口，除非后端明确要求回退。

## 3. 完整业务流程

```text
待登录端                             API / Hub                              已登录授权端
   |                                     |                                      |
   | OAuth client_credentials             |                                      |
   |------------------------------------>|                                      |
   | access_token                         |                                      |
   |<------------------------------------|                                      |
   | SignalR WebSocket + Bearer Token + device query                            |
   |------------------------------------>|                                      |
   | invoke Generate(state: "8451")      |                                      |
   |------------------------------------>|                                      |
   | { scanText, expiredTime }            |                                      |
   |<------------------------------------|                                      |
   | 显示 QR + 4 位 state                  |                                      |
   |                                     |  扫码 /api/chat/scan-code/scan       |
   |                                     |<-------------------------------------|
   |                                     |  命中 scan-login 后读取 /scan-login/scan
   |                                     |<-------------------------------------|
   | ReceivedMessage {command:"scanned"}|                                      |
   |<------------------------------------|                                      |
   |                                     |  用户同意 /scan-login/grant          |
   |                                     |<-------------------------------------|
   | ReceivedMessage {command:"granted", payload:{scanToken}}                  |
   |<------------------------------------|                                      |
   | OAuth grant_type=scan-token, scan_token=...                                |
   |------------------------------------>|                                      |
   | 标准 access_token / refresh_token   |                                      |
   |<------------------------------------|                                      |
   | 登录成功、停止本次 Hub 连接          |                                      |
```

### 3.1 待登录端：连接、生成与展示二维码

1. 请求扫描专用 OAuth Token：`POST {SCAN_LOGIN_AUTH_BASE_URL}{SCAN_LOGIN_AUTH_TOKEN_PATH}`，表单参数见 [第 6 节](#6-oauth-提交参数)。该 Token 只用于匿名待登录端建立挑战，必须与用户登录 Token 分开缓存。
2. 以 WebSocket 连接 `scanLoginHubUrl`。携带 Hub 的 Bearer Token，并在 URL query 附上设备元数据（见 [第 4 节](#4-signalr-连接与-hub-方法)）。
3. 注册服务端方法 `ReceivedMessage`，**在调用 `Generate` 前完成订阅**，避免漏掉快速到达的事件。
4. 生成 1000–9999 的四位随机数字字符串 `state`，调用 `Generate(state)`。
5. 从返回的 `scanText` 生成二维码，显示相同的四位 `state`，并以服务端 `expiredTime` 为准开始倒计时；只有 `expiredTime` 缺失时才使用 90 秒兜底。
6. 每次刷新都生成新的挑战。若已经收到了 `scanned`，刷新前必须二次确认，提示会使手机端当前授权失效。

### 3.2 授权端：扫码、检查与确认

1. 用户扫描二维码字符串。例如：`gotoim://scan-login?code=challenge-id`。
2. 先调用 `/api/chat/scan-code/scan?content=...&type=QR_CODE`。只有返回的 `scanHandlers` 中有 `{ action: "scan-login" }`，且后端返回的标准化 `content` 符合该 handler 的 `result` 模板（没有模板时使用 `SCAN_LOGIN_TEMPLATE`），才进入授权页。
3. 调用 `/api/chat/scan-login/scan?scanText=...`，得到目标设备信息、`state`、`expiredTime` 和当前授权账号。页面应显示设备和四位校验码，让用户核对是否与待登录端一致。
4. 用户同意则调用 `grant`；拒绝则调用 `reject`；离开页面、返回或倒计时结束但尚未完成时，调用 `cancel(connectionId, reason: "User cancelled")`。取消调用是尽力而为：本地返回不应被网络失败阻塞。
5. 一个授权请求只允许提交一次。即使网络返回失败也不可盲目重复 `grant`，应让用户重新扫码，避免重复授权。

### 3.3 待登录端：处理结果

- 收到 `scanned`：仅更新“已扫码、请在手机确认”的状态和扫码用户名，继续等待。
- 收到 `granted`：检查非空 `scanToken`，停止倒计时；可短暂展示成功状态后立即执行 `scan-token` OAuth 兑换。成功后跳转首页，失败则保留失败提示并允许重新生成二维码。
- 收到 `rejected` 或 `cancelled`：不自动复用旧二维码；向用户说明原因并让用户手动刷新。旧 UniApp 会自动生成新码，但当前 Flutter 采用手动刷新，新增实现应保持当前行为。
- 倒计时结束：本地标记过期，不能再授权或兑换；授权端还应尽力 `cancel`，待登录端应手动生成新挑战。

## 4. SignalR 连接与 Hub 方法

### 4.1 连接参数

待登录端的 Hub URL 形如：

```text
{SCAN_LOGIN_SIGNALR_BASE_URL}/signalr-hubs/scan-login
  ?appId=__UNI__39F095D
  &appName=Goto%20IM
  &deviceId=<stable-uuid>
  &deviceType=windows|macos|android|ios|web|...
  &pushClientId=<optional>
  &brand=<optional>
  &model=<optional>
  &platform=<platform-kind>
  &browser=<optional>
```

认证使用 SignalR 客户端的 `accessTokenFactory`（Bearer Access Token），不是把 Token 放到二维码、`state` 或 query 中。当前 Flutter 强制 `WebSockets` transport，并使用 `skipNegotiation` 配置。Web 平台还需要在页面预加载兼容的 SignalR JavaScript 客户端；IO 平台使用 `signalr_netcore`。

| Query 参数 | 必填性 | 含义 |
| --- | --- | --- |
| `appId` | 是 | 应用 ID |
| `appName` | 是 | 应用名称 |
| `deviceId` | 是 | 稳定、非敏感 UUID；Flutter 用安全存储持久化 |
| `deviceType` | 是 | 平台/设备类型 |
| `pushClientId` | 可空 | 推送客户端 ID |
| `brand` / `model` | 可空 | 设备品牌和型号 |
| `platform` | 是 | 平台标识 |
| `browser` | 可空 | 浏览器名；非 Web 通常为空 |

### 4.2 Hub 调用

#### `Generate`

待登录端调用：

```text
Hub method: Generate
arguments: [state]
```

`state` 必须是待登录端新生成的四位随机字符串，例如 `"8451"`。当前客户端不向此调用传递 `connectionId`；Hub 通过当前 SignalR 连接绑定挑战。

成功返回（客户端已明确使用字段）：

```json
{
  "scanText": "gotoim://scan-login?code=6f1b...",
  "expiredTime": "2026-08-25T10:00:00.000Z"
}
```

`scanText` 不能为空；`expiredTime` 应为 ISO-8601 时间。客户端可兼容缺失的 `expiredTime`，但后端应始终返回以避免时钟和有效期歧义。

#### 服务端推送入口：`ReceivedMessage`

客户端仅注册一个服务端方法：`ReceivedMessage`。其第一个参数是信封对象：

```json
{
  "command": "scanned",
  "payload": {}
}
```

`command` 不存在时事件必须忽略。不要把 `payload` 当成完整信封，也不要假设事件会以 `scanned`、`granted` 等独立 Hub 方法名推送。

## 5. SignalR 事件契约

| `command` | 触发时机 | `payload` 中已知字段 | 待登录端必须行为 |
| --- | --- | --- | --- |
| `welcome` | 连接建立后（原 UniApp 使用） | `connectionId` | 可保存连接 ID 用于诊断；当前 Flutter 不依赖它 |
| `generated` | Hub 已生成挑战（原 UniApp 使用） | 未被当前客户端依赖 | 可将状态设为已生成，但 `Generate` 的返回值才是二维码来源 |
| `scanned` | 授权端成功检查二维码 | `scanUserId`、`scanUserName`；兼容 `userName` | 显示已扫码/用户名，继续等待确认 |
| `granted` | 授权端同意且服务端完成授权 | `scanToken`、`userId`、`userName`、`expiredTime` | `scanToken` 非空才兑换 OAuth Token；立即停止倒计时 |
| `rejected` | 授权端拒绝 | 可选原因字段，未被当前客户端依赖 | 显示拒绝，旧码不可再用，等待手动刷新 |
| `cancelled` | 授权端主动离开、取消或服务端取消挑战 | 可选原因字段，未被当前客户端依赖 | 显示取消，旧码不可再用，等待手动刷新 |

推荐的测试事件示例：

```json
{"command":"scanned","payload":{"scanUserId":"u-100","scanUserName":"Alice"}}
{"command":"granted","payload":{"scanToken":"one-time-token","userId":"u-100","userName":"Alice","expiredTime":"2026-08-25T10:00:00.000Z"}}
{"command":"rejected","payload":{"reason":"User rejected"}}
{"command":"cancelled","payload":{"reason":"User cancelled"}}
```

`scanToken` 是短期且一次性的敏感值：禁止打印、持久化、写入 URL、生成二维码或通过分析日志上报。收到后仅用于一次 `scan-token` token 请求。

## 6. OAuth 提交参数

所有 OAuth 请求均为 `POST`，`Content-Type: application/x-www-form-urlencoded`。下面的 `client_secret` 仅在已配置且非空时传送；移动/桌面客户端不得硬编码或记录该字段。

### 6.1 待登录端取得 Hub Token

```text
POST {SCAN_LOGIN_AUTH_BASE_URL}{SCAN_LOGIN_AUTH_TOKEN_PATH}

client_id={SCAN_LOGIN_AUTH_CLIENT_ID}
client_secret={SCAN_LOGIN_AUTH_CLIENT_SECRET}     # 仅非空时
scope={SCAN_LOGIN_AUTH_SCOPE}                     # 当前为 IM
grant_type=client_credentials
```

响应至少需要 `access_token`；如果有 `expires_in`，客户端按有效期分开缓存该 Token（缓存键为 `scan-login`），绝不覆盖用户的 access/refresh token 对。

### 6.2 待登录端用授权结果登录

```text
POST {AUTH_BASE_URL}{AUTH_TOKEN_PATH}

client_id={AUTH_CLIENT_ID}
client_secret={AUTH_CLIENT_SECRET}                # 仅非空时
scope={AUTH_SCOPE}
grant_type=scan-token
scan_token={ReceivedMessage.payload.scanToken}
```

成功响应是标准 OAuth 会话：

```json
{
  "access_token": "...",
  "refresh_token": "...",
  "expires_in": 3600,
  "token_type": "Bearer"
}
```

保存 access/refresh token 到统一 `TokenStorage` 后，按正常登录流程读取用户信息、进入首页；不要另外设计“扫码登录会话”。

## 7. API 请求与响应字段

### 7.1 统一扫码识别

```http
GET /api/chat/scan-code/scan?content=gotoim%3A%2F%2Fscan-login%3Fcode%3D...&type=QR_CODE
Authorization: Bearer <授权端用户 token>
```

客户端使用：

```json
{
  "content": "gotoim://scan-login?code=...",
  "scanHandlers": [
    {"action": "scan-login", "result": "gotoim://scan-login?code={code}"}
  ]
}
```

接收规则：找到第一个 `action == "scan-login"` 的 handler；以 `result` 为模板，若为空使用 `SCAN_LOGIN_TEMPLATE`；标准化后的 `content` 必须匹配模板且所有 `{placeholder}` 非空。模板的固定部分必须完全匹配，placeholder 不可跨越 URI 分隔符 `/ ? & #`。

### 7.2 检查扫码登录挑战

```http
GET /api/chat/scan-login/scan?scanText=gotoim%3A%2F%2Fscan-login%3Fcode%3D...
Authorization: Bearer <授权端用户 token>
```

当前实现读取的响应：

```json
{
  "connectionId": "signalr-connection-id",
  "scanUserId": "u-100",
  "scanUserName": "Alice",
  "state": "8451",
  "expiredTime": "2026-08-25T10:00:00.000Z",
  "connectionPool": {
    "appName": "Goto IM Desktop",
    "deviceInfo": "Windows 11",
    "clientId": "IM_Mobile"
  }
}
```

`connectionPool` 中的 `appName`、`deviceInfo`、`clientId` 是优先展示的目标设备信息。为兼容旧响应，客户端会依次回退到顶层 `scanAppName`/`appName`、`scanDeviceInfo`/`deviceInfo`、`scanClientId`/`clientId`。`scanUserId` 为空时禁止显示“同意登录”按钮。

### 7.3 同意、拒绝和取消

```http
GET /api/chat/scan-login/grant?scanText=...
GET /api/chat/scan-login/reject?scanText=...&reason=User%20rejected
GET /api/chat/scan-login/cancel?connectionId=...&reason=User%20cancelled
Authorization: Bearer <授权端用户 token>
```

这三个响应体目前不被 Flutter 业务逻辑读取；最终结果以 Hub 事件为准。授权端 API 调用不启用 401 自动刷新重试，避免在授权动作期间隐式重放请求。

## 8. 状态机、异常与安全要求

### 8.1 状态机

```text
待登录端：连接中 -> 已生成 -> 已扫码 -> 已授权 -> OAuth 登录成功
                         |          |          |
                         v          v          v
                       已过期      已拒绝     OAuth 失败
                         \          |          /
                          -------- 手动刷新 --------

授权端：扫码 -> 检查中 -> 等待确认 -> 同意/拒绝/取消/过期 -> 离开
```

### 8.2 必须遵守的行为

- 二维码、挑战、`state`、`connectionId`、`scanToken` 不是同一个标识；不要相互替代。
- `state` 只用于用户可见的四位核验，不能当作安全凭据或登录 Token。
- 手机端必须在扫描 API 返回目标设备信息后再允许用户确认，不能扫描后直接授权。
- 以服务端 `expiredTime` 为权威；客户端倒计时仅用于体验，后端仍必须拒绝过期请求。当前客户端把 `ApiException.code == "E104"` 或包含“过期/expired”的错误识别为已过期。
- 待登录端只处理包含非空 `scanToken` 的 `granted`，其余 `granted` 事件视为无效。
- 页面销毁时取消事件订阅、停止 Hub；移动确认页 `dispose` 也应进行一次未完成挑战的 best-effort cancel。
- 连接失败、生成失败、OAuth 兑换失败均应显示可恢复错误；不要因不支持的平台或未加载 Web SignalR 客户端而崩溃。
- 生产环境使用 HTTPS/WSS；不得在日志中输出 Authorization header、OAuth token、`scanToken`、二维码完整内容或完整私有设备数据。

## 9. 实现定位与验收清单

Flutter 的核心文件：

| 责任 | 文件 |
| --- | --- |
| Hub 协议与 Riverpod Provider | `lib/features/scan_login/application/scan_login_hub.dart` |
| IO / desktop / mobile Hub 客户端 | `lib/features/scan_login/application/scan_login_hub_io.dart` |
| Web Hub 客户端 | `lib/features/scan_login/application/scan_login_hub_web.dart` |
| 待登录端二维码 UI 与事件处理 | `lib/features/scan_login/presentation/login_qr_sign_in.dart` |
| 授权端扫描和确认流程 | `lib/features/scan_login/presentation/scan_login_scan_page.dart`、`scan_login_confirmation_page.dart` |
| 授权端 HTTP Repository | `lib/features/scan_login/data/http_scan_login_repository.dart` |
| OAuth `scan-token` / client-credentials 实现 | `lib/features/auth/data/openid_connect_auth_repository.dart` |
| 设备 query 参数 | `lib/core/device/client_device_context.dart` |
| 环境配置和 Hub URL 拼接 | `lib/core/config/app_environment.dart` |

交付前至少验证：

1. 待登录端可建立 Hub、调用 `Generate`，二维码和四位 `state` 显示正确。
2. 授权端识别非扫码登录二维码时不进入确认页；未登录用户不能授权。
3. `scan` 返回的目标设备、账号、四位码和过期时间正确展示。
4. `scanned`、`granted`、`rejected`、`cancelled` 都能驱动正确 UI 状态；`granted` 只兑换一次 Token。
5. 拒绝、返回、过期会取消未完成挑战；同意/拒绝操作不会重复提交。
6. `scan-token` 兑换后得到正常 access/refresh token 并进入已登录首页。
7. Token、`scanToken` 和 `client_secret` 不出现在控制台、网络日志、诊断复制内容或持久化存储中。

## 10. 已知边界

- 当前 Flutter 的扫描专用 Hub 是页面级短连接；它不替代应用级聊天 SignalR 连接。
- 当前 Web 实现依赖全局 `signalR` JavaScript 对象；未加载时应报“SignalR web client was not loaded”，而不是静默失效。
- Hub 的 `welcome`、`generated` 仍为兼容旧 UniApp 的已知事件，但当前 Flutter 登录 UI 只对 `scanned`、`granted`、`rejected`、`cancelled` 做业务处理。
- API 成功响应中更多字段、事件的确切全量 payload、Token 的实际 TTL 均需以后端契约或抓包结果补充；新增客户端字段前必须先确认后端返回，不可凭空扩展协议。
