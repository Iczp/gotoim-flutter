#  Flutter CodeX 开发规范

## 1. 项目范围

### 项目路径

原 UniApp 项目仅供参考，禁止修改：

```text
F:\Dev\GotoIM\gotoim-mobile\gotoim-uniapp-ts
```

实际开发项目：

```text
F:\Dev\GotoIM\gotoim-flutter
```

### 项目目标

将现有 UniApp IM 客户端迁移到 Flutter，并保持现有业务逻辑、接口协议和消息同步语义。

目标平台：

```text
Android
iOS
Android Tablet
iPad
Windows
macOS
Linux
Web
```

优先级：

```text
手机 / 平板 > Windows / macOS / Linux > Web
```

不要求所有平台强行使用同一个插件。

#### 功能原则

	- 移动端能用，那么Andorid/ios/平板 就要能都能用（如果不支持要特别说明）
	- 桌面端能用，那么macOS/Windows就是一定要能用，Linux优先级靠后。
	- 最后才是WEB

某个平台有更合适的实现时，可以使用平台专用方案，并通过统一 Service / Facade 对外提供能力。

#### 依赖包原则：

- 优先使用较新的稳定版本。
- 不为了兼容所有平台而长期降低版本。
- 当前平台不支持时，寻找替代实现。
- 无法支持时明确标记，不允许直接崩溃。

---

## 2. 核心架构

统一使用：

```text
UI
 ↓
Riverpod
 ↓
Repository
 ↓
 ┌────────────┬────────────┬────────────┐
 │            │            │
Drift        Dio        SignalR
 │            │            │
 └────────────┴────────────┴────────────┘
                  ↓
               Backend
```

核心原则：

```text
UI 不关心数据来源。
Repository 负责业务数据访问。
Drift 是本地数据源。
Dio 是 HTTP 通道。
SignalR 是实时事件通道。
Riverpod 是状态层。
PlatformFacade 隔离平台差异。
JSBridge 隔离 H5 与 Flutter。
```

UI 禁止直接访问：

```text
Dio
Drift
SignalR
SharedPreferences
文件系统
平台插件
Native API
```

---

## 3. 技术栈

默认使用：

```text
Flutter
Dart
Riverpod
Dio
go_router
Drift
SignalR
freezed
json_serializable
cached_network_image
video_player
permission_handler
file_picker
image_picker / wechat_assets_picker
flutter_svg
```

未经明确要求，不引入：

```text
GetX
Bloc
Provider
MobX
```

---

## 4. 目录原则

推荐结构：

```text
lib/
├── app/
├── core/
│   ├── network/
│   ├── database/
│   ├── signalr/
│   ├── jsbridge/
│   ├── platform/
│   └── utils/
├── data/
│   ├── models/
│   ├── repositories/
│   └── datasources/
├── services/
├── features/
│   ├── auth/
│   ├── contact/
│   ├── user/
│   ├── media/
│   └── setting/
└── main.dart
```

规则：

- 业务代码优先放在对应 `features`。
- 公共基础设施放 `core`。
- 跨业务服务放 `services`。
- 新建 Repository / Service / Client 前必须先搜索现有实现。
- 禁止因为现有代码不好用就创建 `ApiClient2`、`RepositoryNew` 等重复设施。

---

## 5. HTTP / Dio

### Dio Client

全局统一维护两个 Dio Client，禁止业务代码自行创建 `Dio()`。

1. **Auth Dio**
   - 用于认证、授权、Token 相关请求。
   - 主要请求路径为 `/connect/**`。
   - 例如：
     - `/connect/token`
     - `/connect/userinfo`
     - `/connect/introspect`
     - `/connect/revocation`
   - 认证服务的 BaseUrl、Header、拦截器独立维护。

2. **API Dio**
   - 用于普通业务 API 请求。
   - 主要请求路径为 `/api/**`。
   - 例如：
     - `/api/chat/**`
     - `/api/account/**`
     - `/api/app/**`
   - 统一处理 AccessToken、错误、日志、刷新 Token 等公共逻辑。

### 使用原则

- 优先复用现有两个 Dio Client，不要在 Repository、Service、页面中直接 `Dio()`。
- 根据请求所属服务选择 Dio Client，不要仅根据 URL 字符串临时创建 Client。
- BaseUrl、超时、Header、代理、证书等统一在 HTTP 模块配置。
- Token 刷新、401 重试等逻辑集中处理，业务代码不要重复实现。
- 如后续确实出现独立微服务且配置差异明显，再按实际需要增加新的 Dio Client，不提前过度设计。


必须支持：

```text
BaseUrl
AccessToken
RefreshToken
401 自动刷新
并发刷新保护
统一错误处理
请求取消
文件上传 / 下载
上传 / 下载进度
开发环境日志
```

多个请求同时出现 401：

```text
只允许 1 个 RefreshToken 请求
其他请求等待
刷新成功后统一重试
刷新失败后退出登录
```

禁止并发执行多个 Token Refresh。

Token 必须通过统一 `TokenStorage` 管理：

```text
accessToken
refreshToken
save()
clear()
hasToken()
```

SignalR 也必须读取同一套 TokenProvider。

### 命名规则

- 后端是AbpVnext，方法名、请求参，反回参可以做参考
- 请求Api命名xxxxApi 如：  AuthApi，  SessionUnitApi,  MessageApi
- 请求参数 getTokenInput或是GetTokenInput ,messageGetListInput,FriendsGetListInput
- 返回结果  PagedResultDto<T> MessageDto

---

## 6. Drift / SQLite

Drift 是 IM 本地核心数据源，不只是临时缓存。

建议包含：

```text
Messages
Sessions
SessionUnits
Users
Attachments
```

数据库访问统一通过 DAO。

业务层禁止直接写 Drift 查询。

典型数据流：

```text
HTTP / SignalR
      ↓
 Repository
      ↓
    Drift
      ↓
  Riverpod
      ↓
     UI
```

离线优先：

```text
UI 先展示 Drift 数据
网络后台同步
同步结果写回 Drift
UI 自动更新
```

不要让已有本地数据的页面等待 HTTP 才显示。

---

## 7. 消息模型

消息至少区分：

```text
localId
serverId
clientMessageId
sessionId
sessionMessageId
```

含义：

- `localId`：SQLite 本地主键。
- `serverId`：服务器消息 ID，本地待发送消息可为空。
- `clientMessageId`：客户端唯一 ID，用于发送匹配和去重。
- `sessionId`：会话 ID。
- `sessionMessageId`：会话内消息序号。

禁止仅使用 `serverId` 作为本地主键。

消息状态需要能够表达：

```text
Pending
Sending
Sent
Failed
Delivered
Read
Recalled
Deleted
```

发送失败的消息不得自动删除。



消息这一页，其实是加载好友，加载逻辑是：

分页加载本地好友，到页未了再加载线上的，  loadFriends



刷新只加载线上变更的：  loadChanges

参考：

F:\Dev\GotoIM\gotoim-mobile\gotoim-uniapp-ts\src\pages\im\services\friendService.ts

F:\Dev\GotoIM\gotoim-mobile\gotoim-uniapp-ts\src\pages\im\messages\MessageTab.vue

分组的时间也要参数原来的实现

1. 消息的左上角是 当前的聊天对象，点开显示左侧的抽屉，内容也要参考原来的设计，内容 有其他的聊天对象，点了是可以切换为当前聊天对象，好友列表重新获取，

2. 标题栏下是  Signalr的连接状态，连接成功后消失，显示的当前登录的设备，点进去是登录的设备列表。
3. 分页加载完，底部是有 总 好友数的。

3. 头像是否有存在本地文件夹，存哪个位置，是否配置了在Env里。

4. 

5. 

6. 

7.  tab 加   探索，Tab页，工作台放中心，  切换Tab，要有胶囊移动效果


   目前还没有达到效果：

   1. 好友是首先加载本地的，有默认currentOwnerId, 显示的是加载网络失败，列表暂无好友。流程是加载网络时，要upsert本地，所以要有加载成功过，本地是有好友数据的。
   2. 抽屉打开，没有网络时候，聊天身份就没有，说明这个也是没有缓存下来，

   

---

## 8. 消息发送与同步

发送流程：

```text
UI
 ↓
生成 clientMessageId
 ↓
写入本地 Pending 消息
 ↓
UI 立即显示
 ↓
HTTP 发送
 ↓
服务器返回
 ↓
更新 Drift
```

SignalR 主要负责实时通知，不作为离线消息存储，也不要作为唯一消息发送通道。

收到 SignalR 消息：

```text
SignalR
 ↓
MessageRepository
 ↓
Upsert Drift
 ↓
Riverpod
 ↓
UI
```

禁止 SignalR 直接修改页面状态。

断线重连后，根据需要执行 HTTP 增量同步。

---

## 9. 已读机制

继续兼容现有：

```text
ReadMessageId
PeerReadMessageId
```

不要擅自改成每条消息一条已读记录。

---

## 10. 聊天列表

不要照搬 UniApp 虚拟列表实现。

Flutter 优先使用：

```text
CustomScrollView
SliverList
```

消息高度允许不同。

支持：

```text
文本
图片
视频
语音
文件
系统消息
撤回
删除
时间分隔
新消息分隔
```

建议 UI Model：

```text
ChatItem
├── TimeDivider
├── MessageItem
├── NewMessageDivider
├── SystemMessage
└── OtherSpecialItem
```

除非实际性能测试证明有必要，否则不要自己维护：

```text
height
offset
translateY
visibleItems
```

---

## 11. 消息分页

禁止一次加载大量历史消息。

流程：

```text
Drift 读取最近 N 条
 ↓
向上滚动
 ↓
Drift 加载更早消息
 ↓
本地不足
 ↓
HTTP 获取
 ↓
写入 Drift
 ↓
UI 更新
```

追加历史消息时必须保持当前滚动位置，不能跳动。

---

## 12. SignalR

原则上使用应用级单连接。

禁止每个聊天页面创建一个 SignalR Connection。

统一负责：

```text
连接
断开
自动重连
状态管理
事件注册
Invoke
事件分发
```

事件例如：

```text
ReceiveMessage
ReceiveRecall
ReceiveDelete
ReceiveRead
ReceiveTyping
ReceiveOnline
ReceiveOffline
ReceiveSessionUpdate
ReceiveBadgeUpdate
```

---

## 13. 媒体和附件

附件统一建模，例如：

```text
id
messageId
type
url
localPath
fileName
size
mimeType
downloadState
uploadState
```

大文件禁止直接存 SQLite Blob。

实际文件存：

```text
应用文件目录
+
MinIO
```

MinIO 为私有存储。

客户端通过后端获取授权地址 / Presigned URL。

禁止把 MinIO AccessKey / SecretKey 放到客户端。

---

## 14. 平台抽象

业务代码禁止大量出现：

```dart
Platform.isWindows
Platform.isAndroid
```

统一通过：

```text
PlatformFacade
```

以及：

```text
WindowService
NotificationService
ShareService
ScanService
ClipboardService
FilePickerService
```

需要导入平台专用库时使用 Conditional Imports：

```text
xxx.dart
xxx_mobile.dart
xxx_desktop.dart
xxx_web.dart
xxx_stub.dart
```

共享业务代码禁止直接 import `dart:html` 或桌面专用库。

不要过度设计，不必每个都抽象，必要时才抽象

```
- 避免过度设计，不要求所有实现都增加抽象层。
- 只有在存在多平台差异、第三方实现可替换、需要隔离平台 API，或已有明确多实现需求时才进行抽象。
- 单一、简单、稳定的实现直接使用即可，不要为了“未来可能扩展”提前创建接口、基类、Factory、Adapter 等。
- 优先保持代码简单、清晰、易维护；出现实际扩展需求后再重构抽象。
```



---

## 15. 桌面端

Windows / macOS / Linux 可以支持：

```text
多窗口
窗口尺寸调整
系统托盘
桌面通知
置顶
最小化 / 最大化
```

这些能力统一放在 Service 后面。

例如：

```text
WindowService.openChat(sessionId)
```

Desktop：

```text
打开独立聊天窗口
```

Mobile：

```text
在当前 App 内导航
```

业务调用方式保持一致。

多窗口需要维护：

```text
sessionId -> windowId
```

同一 Session 已打开时激活已有窗口，不重复创建。

---

## 16. 响应式布局

必须适配：

```text
Phone
Tablet
Desktop
```

使用：

```text
LayoutBuilder
MediaQuery
统一 Breakpoints
```

不要简单放大手机版 UI。

推荐：

```text
Phone:
Chat

Tablet:
SessionList | Chat

Desktop:
Navigation | SessionList | Chat
```

---

## 17. 路由

统一使用 `go_router`。

支持：

```text
login
main
session
chat
user
settings
deep link
```

登录鉴权和 Redirect 集中处理。

禁止每个页面自己检查 Token。

---

### Native 能力

统一在 `Native`（或现有设备能力模块）中维护系统/设备能力，业务页面不要直接调用 MethodChannel 或平台原生 API。

需要支持：

- `onUserCaptureScreen`：监听用户主动截屏。
- `vibrate`：设备振动 / 触觉反馈。
- `onThemeChange`：监听系统 Light/Dark Theme 变化。
- `onMemoryWarning`：监听系统内存不足。
- `onAccelerometerChange` / `offAccelerometer`：加速度计，默认约 5 次/秒。
- `onGyroscopeChange` / `offGyroscope`：陀螺仪。
- `makePhoneCall`：拨打电话。
- `setScreenBrightness` / `getScreenBrightness`：屏幕亮度。
- `getBatteryInfo`：电量、充电状态等。
- `onResize`：监听窗口尺寸/方向变化。
- `onProximityChange` / `offProximity`：距离传感器。

实现原则：

- Flutter 自带能力优先直接使用。
- 有成熟稳定插件时优先使用插件。
- Flutter/插件无法满足时，再通过 MethodChannel / EventChannel 实现 Android、iOS 原生能力。
- 不要求每个能力都创建 interface / service / adapter，保持最小必要封装。
- 事件监听必须提供取消监听能力，避免重复订阅和内存泄漏。
- 注意 Android/iOS 权限、生命周期及平台差异，不支持的平台明确返回 unsupported。
- 所有 Native 能力在“开发诊断中心”提供独立测试入口，显示输入、返回值、事件数据及异常。

但底层不需要做成一个几千行的 `Native.dart`。可以按职责简单拆：

```
native/
├── native.dart
├── sensor.dart
├── device.dart
└── system.dart
```

## 18. WebView / JSBridge



现有 UniApp H5 应尽量保持原 JS API。

架构：

```text
UniApp H5
 ↓
goto.xxx()
 ↓
JsBridge
 ↓
JsApiDispatcher
 ↓
PlatformFacade / Service
 ↓
Native API
```

统一请求协议：

```json
{
  "id": "request-id",
  "action": "chooseImage",
  "data": {}
}
```

统一返回：

```json
{
  "id": "request-id",
  "success": true,
  "data": {}
}
```

错误：

```json
{
  "id": "request-id",
  "success": false,
  "error": {
    "code": "USER_CANCEL",
    "message": "User cancelled"
  }
}
```

异步 JSAPI 使用 Promise。

实现 JSAPI 前必须扫描原 UniApp 项目，确认真实使用情况。

不要凭空增加 API。

---

## 19. 后端兼容

现有 ABP vNext API 属于外部契约。

未经明确要求，不修改后端接口。

DTO / Model 修改前：

```text
1. 查看 UniApp 原实现
2. 查看后端 DTO
3. 查看实际 JSON
4. 实现 Flutter Model
5. 增加序列化测试
```

---

## 20. 错误与日志

统一应用异常，例如：

```text
ApiException
AuthException
NetworkException
DatabaseException
PlatformException
JsApiException
```

不要把 Dio / SQLite / Native 原始异常直接抛给 UI。

统一 Logger。

开发环境可记录：

```text
HTTP
SignalR
数据库同步
JSBridge
平台服务
```

禁止记录：

```text
密码
RefreshToken
AccessToken
私有密钥
完整敏感 Presigned URL
不必要的私人聊天内容
```

---

## 21. 性能要求

这是 IM 应用，重点关注：

```text
聊天列表 rebuild
数据库查询
Riverpod rebuild
SignalR 高频事件
图片解码
视频内存
大型群聊
大量历史消息
```

禁止：

```text
单条消息变化
 ↓
整个 1000 条消息列表全部 rebuild
```

图片、视频必须懒加载。

不要一次预加载全部媒体。

---

## 22. 测试

主要基础设施必须有测试：

```text
ApiClient
Token Refresh
MessageRepository
MessageDao
SessionDao
SignalR
JSBridge
Platform Service
```

必须覆盖：

```text
多个 HTTP 请求同时 401
 ↓
只产生一次 RefreshToken 请求
 ↓
其余请求等待
 ↓
刷新成功后全部重试
```

使用：

```text
freezed
json_serializable
drift
```

修改相关 Model / Table 后执行对应 `build_runner`。

禁止手动修改生成文件。

---

## 23. Codex 开发流程

每个任务：

```text
1. 阅读现有代码
2. 搜索是否已有相关实现
3. 确认架构位置
4. 以最小改动实现
5. format
6. flutter analyze
7. 执行相关测试
8. 修复问题
9. 总结修改内容
```

禁止顺手进行无关的大规模重构。

复杂任务开始编码前，简要说明：

```text
修改哪些文件
架构影响
实现方式
主要风险
```

普通明确任务直接执行，不需要反复询问确认。

---

## 24. UniApp 迁移原则

禁止机械地把 Vue / UniApp 翻译成 Dart。

例如：

```text
Pinia
→
Riverpod
```

```text
UniApp virtual-list
→
Flutter SliverList
```

优先按照 Flutter 自身架构重新实现。

迁移建议顺序：

```text
基础架构
→ 平台抽象
→ Dio / Token
→ Drift
→ Repository
→ SignalR
→ JSBridge
→ 登录
→ 首页 / 会话
→ 联系人
→ 聊天
→ 媒体
→ 桌面能力
→ 平板适配
→ H5
→ 测试与性能优化
```

---

## 25. 开发诊断中心

项目中的：

```text
开发诊断中心
Development Diagnostics Center
```

属于正式开发工具，不是临时 Demo。

以后每个可以独立验证的重要功能，都必须同步提供诊断入口。

也就是说：

```text
业务功能
+
诊断 Demo
```

视为同一个开发任务。

### 每个诊断功能至少包含

```text
功能说明
支持平台
输入参数
执行按钮
执行状态
返回结果
实际效果
异常信息
复制功能
恢复默认
```

主要输入必须允许人工修改，不能全部写死。

同时提供默认测试数据，打开即可执行。

执行状态至少：

```text
未执行
执行中
成功
失败
```

异步任务建议显示：

```text
耗时：128 ms
```

返回值尽量结构化显示：

```text
输入
 ↓
实际执行
 ↓
返回结果
 ↓
最终渲染效果
```

不能只显示：

```text
测试成功
```

### 异常

失败时至少显示：

```text
异常类型
异常消息
必要的 StackTrace
```

StackTrace 可以折叠。

### 复制

以下内容尽量支持复制：

```text
输入
输出
异常
日志
```

方便直接发给 Codex 或粘贴到 Issue。

### 平台信息

诊断中心应显示当前运行环境，至少：

```text
Platform
Flutter Version
App Version
Build Mode
```

项目已有能力时再增加：

```text
OS Version
Device
Architecture
Screen Size
Pixel Ratio
Locale
```

不要为了诊断信息引入大量额外依赖。

### 平台验证

所有诊断功能必须明确标记平台支持情况：

```text
Android   ✓
iOS       ✓
iPad      ✓
Windows   ✓
macOS     ✓
Linux     ✓
Web       ✓
```

不支持的平台显示：

```text
暂不支持
```

禁止调用后直接崩溃。

### 禁止伪造结果

所有：

```text
成功
失败
返回值
耗时
```

必须来自实际执行。

禁止静态写：

```dart
Text('测试成功')
```

冒充真实测试结果。

---

## 26. 最终原则

遇到现有代码与本规范冲突时：

1. 优先保持现有业务行为。
2. 不擅自修改后端契约。
3. 新代码优先遵循本规范架构。
4. 大规模架构调整前说明冲突。
5. 保持修改范围小、可测试、可回滚。
6. 所有可独立验证的重要能力同步加入开发诊断中心。
