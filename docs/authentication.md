# 认证与网络层

## 范围

Flutter 客户端遵循现有 UniApp 的认证契约：通过 OpenIddict
`POST /connect/token`，以 `password` 授权类型登录、以 `refresh_token`
授权类型续期。本阶段仅实现认证基础设施，不包含用户资料或 IM 业务页面。

```text
LoginPage -> AuthController -> OpenIdConnectAuthRepository
                                  |             |
                                  |             +-> TokenStorage（安全存储）
                                  v
                           OpenIddict /connect/token

Repository -> ApiClient (Dio) -> 401 -> 单一刷新任务 -> 重试一次
SignalR -------------------------------> TokenStorage.readAccessToken()
```

## 环境配置

在项目根目录的 `.env.<flavor>` 中设置可公开、非敏感的配置：

| 配置项 | 含义 |
| --- | --- |
| `APP_ID` / `APP_NAME` / `APP_VERSION` | 现有后端使用的 App 标识及版本，请按已注册客户端填写 |
| `API_BASE_URL` | 共享 Dio 客户端使用的 API 主机地址 |
| `AUTH_BASE_URL` | OpenIddict 服务地址 |
| `AUTH_TOKEN_PATH` | Token 端点，通常为 `/connect/token` |
| `AUTH_CLIENT_ID` | 服务端注册的公开移动端 client id |
| `AUTH_CLIENT_SECRET` | 可选的兼容字段；会随 Token 请求提交 |
| `AUTH_SCOPE` | 空格分隔的 OAuth scope，通常包含 `offline_access` |
| `AUTH_LOGIN_GRANT_TYPE` | 当前服务端使用的登录授权类型，现为 `password` |
| `AUTH_USER_INFO_PATH` | 登录后验证 API 的用户信息端点，通常为 `/connect/userinfo` |
| `AUTH_INTROSPECTION_PATH` | Token 检查端点，现为 `/connect/introspect` |
| `AUTH_REVOCATION_PATH` | Token 撤销端点；既有后端当前使用 `/connect/revocat` |

按环境运行：

```powershell
flutter run --dart-define=APP_ENV=development
```

`AUTH_CLIENT_SECRET` 已作为兼容既有服务端的可选字段接入；但根目录的
`.env.<flavor>` 会被打包到客户端，移动端/桌面端无法安全保存 secret。应优先让
服务端将该 `AUTH_CLIENT_ID` 配置为 public client，或改用 PKCE 授权码流程。不要
在 `.env` 中填写用户密码、access token、refresh token 或 MinIO 凭据。真实登录
前，需由后端完成生产环境地址及公开 `AUTH_CLIENT_ID` 的注册。

## Token 生命周期与刷新保护

- `SecureTokenStorage` 是唯一的 Token 持久化实现。UI 和 Repository 只依赖
  `TokenStorage` 抽象。
- 登录时同时保存 access token 和 refresh token。
- `/connect/token` 与 `/connect/userinfo` 均使用
  `application/x-www-form-urlencoded`；后者也会附加当前 Bearer Token。
- `DioApiClient` 自动附加 `Authorization: Bearer <access-token>`。
- 所有认证与业务 HTTP 请求均附加 `Accept`、`App-Device-Id`、
  `App-Device-Type`、`App-Id`、`App-Version`。设备 ID 首次启动时生成并稳定保存。
- **预判性提前续期**：通过 `shouldRefreshJwt(token)` 在 Token 到期前 5 分钟提前触发续期，减少刚好在边界过期带来的 401 抖动。
- **全局单飞刷新（Single In-Flight）**：
  - 无论是业务 HTTP 遇到 401，还是 SignalR 连接/重连前的预判刷新，全部收敛到 `OpenIdConnectAuthRepository.refreshSession()` 的单一 `_globalRefreshInFlight` Future。
  - 所有并发请求等待同一刷新结果，成功后使用新 Token 重试，禁止并发向 `/connect/token` 发起多个刷新请求。
- **OAuth 刷新令牌轮换（Refresh Token Rotation）防御**：
  - OpenIddict 默认启用了 Refresh Token 轮换机制：每个 Refresh Token 仅允许兑换一次（One-time use）。兑换成功后会下发新 Refresh Token 并废弃旧 Token。
  - 若旧 Token 被二次提交，服务端将视为令牌重放/窃听攻击，返回 `invalid_grant: The specified refresh token has already been redeemed` 并吊销该会话下的所有 Token。
  - 客户端通过内存单飞锁与写入落盘原子保护，防止并发请求拿旧 Token 触发已被兑换异常；一旦收到此类致命拒绝异常（`TokenRefreshRejectedException`），将判定为会话不可逆失效并立即断路退出。
- 刷新失败时清除本地 Token，断开长连接，路由平滑跳转到 `/login`。
- SignalR 在连接或重连前，都通过回调读取同一安全存储中的最新 access token。

当前 Token 适配器没有调用注销/撤销端点，因为既有 UniApp 项目里的撤销地址为
`/connect/revocat`。Flutter 已按该既有契约实现：退出登录时依次撤销 access 和
refresh token；无论撤销结果如何都会断开 SignalR 并清除本地凭据。若后端迁移到
标准 OAuth `/connect/revocation`，只需修改 `AUTH_REVOCATION_PATH`。

## 会话失效解耦架构（SessionInvalidator）

为了彻底避免底层传输层反向依赖上层状态导致的 Riverpod 循环依赖（`CircularDependencyError`），系统引入了独立的事件总线对象 `SessionInvalidator`：

```text
       UI / Page
           │ (watch)
           ▼
    AuthController ──(watch)──> SignalRGateway / ApiClient
           │                               │
       (register)                     (invalidate)
           │                               │
           ▼                               ▼
    SessionInvalidator ◄───────────────────┘ (通过 sessionInvalidatorProvider 解耦)
```

1. **单向依赖原则**：
   - `authControllerProvider` 依赖并监听 `signalRGatewayProvider`、`apiClientProvider`。
   - `SignalRGateway` 与 `ApiClient` 等传输层**严禁**直接通过 `ref.read(authControllerProvider)` 调用登出逻辑。
2. **总线解耦注册**：
   - `AuthController` 初始化时将其 `sessionInvalidated` 回调注册到 `SessionInvalidator` 中，并在销毁时注销。
   - 无论是 `DioApiClient`（401 重试失败）还是 `SignalRNetcoreGateway`（主动刷新/重连鉴权被拒），统一只调用 `sessionInvalidator.invalidate(reason: ...)`。
3. **并发与清理闭环**：
   - `SessionInvalidator` 与 `AuthController` 内部带有防重叠锁（`_invalidating`），即使 HTTP 与 WebSocket 同时判定 401，也仅会执行一次清理。
   - 清理步骤：清除本地 SecureTokenStorage -> 断开 SignalR 连接 -> 清除本地 ABP 配置缓存 -> 执行 `_onAccountChanged`（通知并 invalidate 所有账号级状态 Provider） -> 将 `_status` 置为 `unauthenticated` -> GoRouter 检测到未认证并平滑重定向至 `/login`。

## 界面与路由

`/splash` 用于恢复本地会话；没有会话时跳转 `/login`；`/` 是当前的已登录
应用壳。认证跳转逻辑集中在 `app_router.dart`，业务页面无需各自判断登录态。

登录后，可通过应用壳右上角的“连接测试”进入
`/diagnostics/connection`。页面会调用 `AUTH_USER_INFO_PATH` 验证当前 Token，
并展示 SignalR 的连接状态和最近一条命令名称；不会展示 Token、secret 或消息
正文。

连接测试页还提供 refresh token、好友列表和消息列表验证。好友测试调用
`/api/chat/session-unit-cache/friends?ownerId=<值>&maxResultCount=100`；消息
测试调用 `/api/chat/message/fast`，必须手动输入已有的 `sessionUnitId`。业务 API
仅返回数量或字段摘要，以免诊断页泄露联系人资料或消息正文。

## 原 UniApp 认证能力对照

| 能力 | 当前 Flutter 状态 | 说明 |
| --- | --- | --- |
| 密码登录 | 已实现 | `/connect/token`，`password` grant |
| 刷新 Token | 已实现 | 单飞刷新与诊断页手动刷新 |
| 用户信息 | 已实现 | `/connect/userinfo`，表单编码 |
| Token 检查 | 已实现 | `/connect/introspect` |
| Token 撤销与退出 | 已实现 | 保留现有 `/connect/revocat` 路径 |
| `client_credentials` | 待确认 | 旧项目用于独立服务凭据；移动端不应默认持有 secret |
| ERP Header 登录 | 待确认 | 需后端提供确切 Header 与安全策略 |
| 用户缓存 | 待 Drift | 旧项目以 `uni.storage` 缓存，Flutter 应迁入 Drift |
| 设备注册 | 待平台服务 | 旧项目调用 `/api/chat/device/register`；需先接入推送 Token 与设备详情 |

## 新增已认证接口

请提供应用 Repository 方法并注入 `ApiClient`，不要让 Widget 直接使用 Dio：

```dart
final result = await apiClient.get<Map<String, dynamic>>('/api/chat/sessions');
```

迁移真实 IM 接口前，请先补齐 DTO、Repository 和对应测试。
