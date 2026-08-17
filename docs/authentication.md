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

按环境运行：

```powershell
flutter run --dart-define=APP_ENV=development
```

`AUTH_CLIENT_SECRET` 已作为兼容既有服务端的可选字段接入；但根目录的
`.env.<flavor>` 会被打包到客户端，移动端/桌面端无法安全保存 secret。应优先让
服务端将该 `AUTH_CLIENT_ID` 配置为 public client，或改用 PKCE 授权码流程。不要
在 `.env` 中填写用户密码、access token、refresh token 或 MinIO 凭据。真实登录
前，需由后端完成生产环境地址及公开 `AUTH_CLIENT_ID` 的注册。

## Token 生命周期

- `SecureTokenStorage` 是唯一的 Token 持久化实现。UI 和 Repository 只依赖
  `TokenStorage` 抽象。
- 登录时同时保存 access token 和 refresh token。
- `/connect/token` 与 `/connect/userinfo` 均使用
  `application/x-www-form-urlencoded`；后者也会附加当前 Bearer Token。
- `DioApiClient` 自动附加 `Authorization: Bearer <access-token>`。
- 所有认证与业务 HTTP 请求均附加 `Accept`、`App-Device-Id`、
  `App-Device-Type`、`App-Id`、`App-Version`。设备 ID 首次启动时生成并稳定保存。
- 收到 401 时只会启动一个 `refresh_token` 请求。并发的 401 请求等待同一个
  Future，成功后使用新 Token 各自重试一次。
- 刷新失败时清除本地 Token，路由跳转到 `/login`。
- SignalR 在连接或重连前，都通过回调读取同一安全存储中的最新 access token。

当前 Token 适配器没有调用注销/撤销端点，因为既有 UniApp 项目里的撤销地址为
不完整的 `revocat`。确认后端契约后再补充该调用，不能猜测后端 API。

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

## 新增已认证接口

请提供应用 Repository 方法并注入 `ApiClient`，不要让 Widget 直接使用 Dio：

```dart
final result = await apiClient.get<Map<String, dynamic>>('/api/chat/sessions');
```

迁移真实 IM 接口前，请先补齐 DTO、Repository 和对应测试。
