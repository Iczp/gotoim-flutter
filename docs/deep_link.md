# GotoIM Flutter Deep Link / App Links 接入与开发指南

GotoIM 客户端提供了跨平台的 Deep Link 与 Universal Link 深度链接统一接入架构：

- **统一链接分发**：基于 `app_links` 监听操作系统传入的 URI，兼容自定义 Scheme 与未来标准 HTTPS Universal Links；
- **纯 Dart 统一归一化（Normalize）**：将 `gotoim-dev://chat/123/message/456` 与 `https://gotoim.com/chat/123/message/456` 统一归一化为 `['chat', '123', 'message', '456']`；
- **强类型密封目标（Sealed Target）**：通过 Dart `sealed class DeepLinkTarget` 进行模式匹配，保证类型安全；
- **安全与权限保护**：敏感凭据（`access_token`、`refresh_token`、`password`）严禁通过 URL 传递；群邀请仅打开确认卡片，严禁自动入群；
- **冷启动与热启动支持**：支持 App 未启动时的冷启动捕获，以及后台运行时的实时 Stream 监听；
- **无缝路由与未登录挂起**：支持 `PendingDeepLink` 挂起机制，受保护页面在未登录时自动留存并在登录后继续；
- **开发诊断中心全链路观测**：内置实时事件日志、手工解析、直接执行与平台 CLI 调试命令。

---

## 1. 核心架构设计

```text
┌─────────────────────────────────────────────────────────────┐
│                    操作系统 (OS Deep Link)                   │
│  (Android Intent / iOS URL / Windows Protocol / macOS URL)  │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                          app_links                          │
│               (getInitialLink & uriLinkStream)              │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                       DeepLinkService                       │
│    (生命周期监听 / 事件日志追踪 / 异常安全防护 / Riverpod 暴露)   │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                       DeepLinkParser                        │
│            (纯 Dart 归一化 / 安全校验 / 语义解析)             │
│                              │                              │
│         ┌────────────────────┴────────────────────┐         │
│         ▼                                         ▼         │
│  [自定义 Scheme]                           [HTTPS 域名]      │
│  gotoim-dev://chat/123              https://gotoim.com/chat/123
│         └────────────────────┬────────────────────┘         │
│                              ▼                              │
│                    ['chat', '123', ...]                     │
│                              │                              │
│                              ▼                              │
│                       DeepLinkTarget                        │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                       DeepLinkHandler                       │
│    (登录状态校验 / PendingDeepLink 队列 / GoRouter 路由分发)   │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                     Flutter UI / GoRouter                   │
│   (/scan-login, /workbench, notImplemented 友好降级提示)    │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. 全平台支持矩阵

| 平台 | 开发 Scheme (`gotoim-dev://`) | 生产 Scheme (`gotoim://`) | HTTPS (`https://gotoim.com/`) | 备注 / 机制 |
| :--- | :---: | :---: | :---: | :--- |
| **Android (手机/平板)** | ✅ **完全支持** | ✅ (配置即用) | 🔄 (待域名 DNS 配置) | `AndroidManifest.xml` 注册 `VIEW` / `DEFAULT` / `BROWSABLE` Intent Filter；禁用 Flutter 默认处理器避免冲突 |
| **iOS (iPhone/iPad)** | ✅ **完全支持** | ✅ (配置即用) | 🔄 (待域名 DNS 配置) | `Info.plist` 配置 `CFBundleURLTypes`；`FlutterDeepLinkingEnabled` 置为 `false` |
| **macOS** | ✅ **完全支持** | ✅ (配置即用) | 🔄 (待域名 DNS 配置) | `Info.plist` 配置 `CFBundleURLTypes` |
| **Windows** | ✅ **完全支持** | ✅ (配置即用) | 🔄 (待域名 DNS 配置) | `main.cpp` 调用 `SendAppLinkToInstance()` 支持单实例复用转发 |
| **Linux** | ✅ **完全支持** | ✅ (配置即用) | 🔄 (待域名 DNS 配置) | `app_links_linux` 桌面协议支持 |
| **Web** | ✅ **完全支持** | ❌ (浏览器限制) | ✅ (URL 路由解析) | 浏览器环境通过 URL 解析或手动触发 |

---

## 3. URI 协议与解析规则

### 3.1 聊天与消息定位 (`ChatDeepLink`)

- **打开会话**：
  - 开发环境：`gotoim-dev://chat/{sessionId}`
  - 未来 HTTPS：`https://gotoim.com/chat/{sessionId}`
  - 生产 Scheme：`gotoim://chat/{sessionId}`
  - 解析结果：`ChatDeepLink(sessionId: '123', messageId: null)`
- **定位指定消息**：
  - 开发环境：`gotoim-dev://chat/{sessionId}/message/{messageId}`
  - 未来 HTTPS：`https://gotoim.com/chat/{sessionId}/message/{messageId}`
  - 解析结果：`ChatDeepLink(sessionId: '123', messageId: 5588575)`（`messageId` 为整数）

### 3.2 用户资料卡 (`UserDeepLink`)

- **URI**：`gotoim-dev://user/{userId}`
- **解析结果**：`UserDeepLink(userId: '10086')`

### 3.3 群组资料卡 (`GroupDeepLink`)

- **URI**：`gotoim-dev://group/{groupId}`
- **解析结果**：`GroupDeepLink(groupId: '888')`

### 3.4 群组邀请确认 (`GroupInviteDeepLink`)

- **URI**：`gotoim-dev://invite/group/{token}`
- **解析结果**：`GroupInviteDeepLink(token: 'abcdef123')`
- **安全约束**：**严禁直接自动加群**。Deep Link 仅能打开邀请确认界面，由用户手动点击“加入群组”并调用后端 API。

### 3.5 扫码登录 (`ScanLoginDeepLink`)

- **路径格式**：`gotoim-dev://scan-login/{qrCode}`
- **参数格式**：`gotoim-dev://scan-login?code={qrCode}`
- **解析结果**：`ScanLoginDeepLink(qrCode: 'abc123')`
- **路由分发**：自动推入 `/scan-login?scanText={qrCode}` 进行授权确认。

### 3.6 工作台应用 (`WorkbenchDeepLink`)

- **URI**：`gotoim-dev://workbench/{appId}`
- **解析结果**：`WorkbenchDeepLink(appId: 'mail')`
- **路由分发**：推入 `/workbench`。

### 3.7 OAuth 授权回调 (`OAuthCallbackDeepLink`)

- **URI**：`gotoim-dev://oauth/callback?code={code}&state={state}`
- **解析结果**：`OAuthCallbackDeepLink(code: '...', state: '...')`
- **安全约束**：严禁在 URL Query 中传递 `access_token`、`refresh_token` 或 `password`，一旦检测到立即判定为 `invalid` 并拦截。

---

## 4. 人工测试与终端唤醒命令

### 4.1 Android 端测试

#### A. App 完全关闭 (Cold Start)
```powershell
adb shell am start -a android.intent.action.VIEW -d "gotoim-dev://chat/123"
```

#### B. App 处于前台或后台 (Warm Start)
```powershell
adb shell am start -a android.intent.action.VIEW -d "gotoim-dev://chat/123/message/456"
```

#### C. 用户资料
```powershell
adb shell am start -a android.intent.action.VIEW -d "gotoim-dev://user/10086"
```

#### D. 群邀请卡片
```powershell
adb shell am start -a android.intent.action.VIEW -d "gotoim-dev://invite/group/abcdef123"
```

#### E. 非法参数防崩溃测试
```powershell
adb shell am start -a android.intent.action.VIEW -d "gotoim-dev://chat/123/message/abc"
```

---

### 4.2 Windows 端测试

#### A. 启动或唤醒
```powershell
Start-Process "gotoim-dev://chat/123"
```

#### B. 消息定位
```powershell
Start-Process "gotoim-dev://chat/123/message/456"
```

---

### 4.3 iOS 端测试 (Simulator / Device)

#### A. 聊天会话
```bash
xcrun simctl openurl booted "gotoim-dev://chat/123"
```

#### B. 消息定位
```bash
xcrun simctl openurl booted "gotoim-dev://chat/123/message/456"
```

---

### 4.4 macOS 端测试

```bash
open "gotoim-dev://chat/123"
open "gotoim-dev://chat/123/message/456"
```

---

## 5. 开发诊断中心

在 Debug 模式下通过 **“开发诊断中心 → Deep Link / App Links”**（`/diagnostics/deep-link`）进行全方位测试：

1. **预设案例快速填充**：提供聊天、消息定位、用户、群、群邀请、扫码登录、工作台、OAuth、HTTPS 模拟、非法格式等预设 Chip；
2. **[解析] 按钮**：只调用 `DeepLinkParser.parse(uri)` 纯解析，结构化显示 Scheme、Host、Path、Normalized Segments、TargetType、Target 详细字段与错误原因；
3. **[执行] 按钮**：调用 `DeepLinkHandler` 触发真实路由跳转与鉴权检查，显示执行状态（`success` / `needsAuth` / `notImplemented` / `failed`）及耗时；
4. **实时 App Links 事件日志**：展示最近 50 条来自系统冷启动、实时流或手动调用的真实链接接收记录，支持一键清空与复制；
5. **CLI 命令复制区**：提供一键复制 Android、Windows、iOS、macOS 平台唤醒命令。

---

## 6. 未来上线 HTTPS App Links / Universal Links 配置指引

当 `gotoim.com` 部署 DNS 与 HTTPS 证书后，无需改动任何 Dart 解析代码，仅需完成以下两步配置：

### 第一步：服务器端配置

1. **Android Digital Asset Links**：
   在 `https://gotoim.com/.well-known/assetlinks.json` 托管应用 SHA-256 指纹：
   ```json
   [{
     "relation": ["delegate_permission/common.handle_all_urls"],
     "target": {
       "namespace": "android_app",
       "package_name": "com.example.gotoim_flutter",
       "sha256_cert_fingerprints": ["<YOUR_RELEASE_KEY_SHA256>"]
     }
   }]
   ```

2. **iOS Apple App Site Association**：
   在 `https://gotoim.com/.well-known/apple-app-site-association` 托管：
   ```json
   {
     "applinks": {
       "apps": [],
       "details": [{
         "appID": "<TEAM_ID>.com.example.gotoimFlutter",
         "paths": ["/chat/*", "/user/*", "/group/*", "/invite/*", "/workbench/*"]
       }]
     }
   }
   ```

### 第二步：客户端 Manifest 开启 autoVerify 与 Associated Domains

1. **Android (`AndroidManifest.xml`)**：
   ```xml
   <intent-filter android:autoVerify="true">
       <action android:name="android.intent.action.VIEW" />
       <category android:name="android.intent.category.DEFAULT" />
       <category android:name="android.intent.category.BROWSABLE" />
       <data android:scheme="https" android:host="gotoim.com" />
   </intent-filter>
   ```

2. **iOS Xcode Capabilities**：
   在 Signing & Capabilities 中添加 Associated Domains：
   ```text
   applinks:gotoim.com
   ```
