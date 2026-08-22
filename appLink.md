# GotoIM Flutter Deep Link / app_links 实现任务

请在现有 Flutter 项目中实现统一 Deep Link 能力。

## 一、总体要求

使用 `app_links` 实现 Deep Link。

当前开发阶段 **还没有配置 gotoim.com DNS 和 HTTPS**，因此：

- 开发阶段主要使用自定义 Scheme：
  - `gotoim-dev://`
- 正式环境未来使用：
  - `gotoim://`
  - `https://gotoim.com/...`

本次任务：

- 必须完成 `gotoim-dev://` 的真实平台唤醒和接收。
- `https://gotoim.com/...` 暂时只完成 URI 解析和自动测试。
- 暂时不要配置：
  - `assetlinks.json`
  - `apple-app-site-association`
  - Android HTTPS App Links
  - iOS Universal Links
- 后续 HTTPS 上线时应该可以直接复用现有 Deep Link 解析和处理代码。

不要过度设计。

要使用环境变量Env，并做好注释

不要因为这个功能引入新的 Router 框架。

先检查项目当前 Router、登录状态管理、依赖注入、日志、开发诊断中心的实现方式，并复用现有方案。

------

# 二、依赖

检查当前 Flutter / Dart SDK 与 `app_links` 版本兼容性。

如果兼容，使用当前稳定版本：

```yaml
app_links: ^7.2.1
```

不要为了安装 `app_links` 随意升级 Flutter SDK 或其他无关依赖。

------

# 三、目录设计

建议：

```text
lib/
  core/
    deep_link/
      deep_link_target.dart
      deep_link_parser.dart
      deep_link_service.dart
      deep_link_handler.dart
```

保持简单，不需要为每一种 DeepLink 建一个 Handler 类。

职责：

```text
DeepLinkService
    ↓
监听 app_links
    ↓
DeepLinkParser
    ↓
DeepLinkTarget
    ↓
DeepLinkHandler
    ↓
现有 Flutter Router
```

------

# 四、DeepLinkTarget

定义统一的 Deep Link 解析结果。

推荐使用 Dart sealed class。

例如：

```dart
sealed class DeepLinkTarget {
  const DeepLinkTarget();
}
```

至少支持：

```text
ChatDeepLink
UserDeepLink
GroupDeepLink
GroupInviteDeepLink
ScanLoginDeepLink
WorkbenchDeepLink
OAuthCallbackDeepLink
```

字段根据下面协议设计。

------

# 五、URI 协议

## 1. 聊天

```text
gotoim-dev://chat/{sessionId}
```

例如：

```text
gotoim-dev://chat/123
```

未来：

```text
https://gotoim.com/chat/123
```

解析：

```text
ChatDeepLink
sessionId = 123
messageId = null
```

------

## 2. 定位聊天消息

```text
gotoim-dev://chat/{sessionId}/message/{messageId}
```

例如：

```text
gotoim-dev://chat/123/message/5588575
```

未来：

```text
https://gotoim.com/chat/123/message/5588575
```

解析：

```text
ChatDeepLink
sessionId = 123
messageId = 5588575
```

`messageId` 使用 Dart `int`。

------

## 3. 用户

```text
gotoim-dev://user/{userId}
```

例如：

```text
gotoim-dev://user/10086
```

------

## 4. 群

```text
gotoim-dev://group/{groupId}
```

例如：

```text
gotoim-dev://group/888
```

------

## 5. 群邀请

```text
gotoim-dev://invite/group/{token}
```

例如：

```text
gotoim-dev://invite/group/abcdef123
```

注意：

Deep Link 只能打开确认页面。

不能因为打开 URI 就自动加入群。

------

## 6. 扫码登录

```text
gotoim-dev://scan-login/{qrCode}
```

例如：

```text
gotoim-dev://scan-login/abc123
```

后续可兼容现有扫码登录 URI。

------

## 7. 工作台应用

```text
gotoim-dev://workbench/{appId}
```

例如：

```text
gotoim-dev://workbench/mail
```

------

## 8. OAuth Callback

```text
gotoim-dev://oauth/callback?code=xxx&state=yyy
```

解析：

```text
OAuthCallbackDeepLink
code
state
```

注意：

禁止通过 Deep Link URL 传递：

```text
access_token
refresh_token
password
```

------

# 六、URI Normalize

必须解决自定义 Scheme 和 HTTPS URI 结构不一致的问题。

例如：

```text
gotoim-dev://chat/123/message/456
```

Dart 中：

```text
scheme = gotoim-dev
host = chat
pathSegments = [123, message, 456]
```

而：

```text
https://gotoim.com/chat/123/message/456
```

则：

```text
scheme = https
host = gotoim.com
pathSegments = [chat, 123, message, 456]
```

需要统一 Normalize。

两种 URI 最终都转换为：

```text
[
  chat,
  123,
  message,
  456
]
```

然后再进行业务解析。

允许：

```text
gotoim-dev://
gotoim://
https://gotoim.com/
```

除此之外的域名和 Scheme 默认拒绝。

例如：

```text
https://evil.com/chat/123
```

必须返回 unsupported，不允许进入业务 Router。

------

# 七、DeepLinkParser

Parser 必须是纯 Dart 逻辑：

```dart
DeepLinkParseResult parse(Uri uri)
```

不要依赖：

- BuildContext
- Router
- app_links
- 网络
- 数据库

这样方便单元测试。

不要因为 URI 错误直接抛出未捕获异常。

建议区分：

```text
success
unsupported
invalid
```

能够返回错误原因。

例如：

```text
gotoim-dev://chat
```

应该：

```text
invalid
reason = missing sessionId
```

而：

```text
gotoim-dev://xxxx/123
```

应该：

```text
unsupported
```

------

# 八、DeepLinkService

负责封装 `app_links`。

职责：

```text
AppLinks
    ↓
监听 uriLinkStream
    ↓
记录日志
    ↓
DeepLinkParser
    ↓
DeepLinkHandler
```

要求：

1. AppLinks 尽可能早初始化。
2. 能处理 App 冷启动。
3. 能处理 App 已经启动时收到 URI。
4. 正确保存和释放 StreamSubscription。
5. URI 解析失败不能导致 App 崩溃。
6. 未知 URI 只记录日志。
7. 日志必须方便开发诊断中心查看。

不要在：

```dart
uriLinkStream.listen(...)
```

里面直接堆大量页面跳转 if/else。

------

# 九、Flutter 自带 Deep Link

项目使用 `app_links` 以后，Android / iOS 不要同时让 Flutter 默认 Deep Link Handler 抢占事件。

Android 根据当前 Flutter 官方要求配置：

```xml
<meta-data
    android:name="flutter_deeplinking_enabled"
    android:value="false" />
```

iOS：

```xml
<key>FlutterDeepLinkingEnabled</key>
<false/>
```

注意检查项目当前 Flutter SDK 和现有配置，不要重复添加冲突配置。

------

# 十、Android 开发 Scheme

Android 注册：

```text
gotoim-dev://
```

在正确的 Activity 中增加 intent-filter。

要求：

```text
VIEW
DEFAULT
BROWSABLE
scheme = gotoim-dev
```

不要现在配置 `https://gotoim.com` 的 `autoVerify`。

不要配置不存在的 assetlinks.json。

------

# 十一、iOS 开发 Scheme

iOS 注册：

```text
gotoim-dev://
```

通过正确的 URL Types / Info.plist 配置。

同时关闭 Flutter 默认 Deep Link Handler。

本阶段：

不要配置 Associated Domains。

不要配置 Universal Links。

------

# 十二、macOS

如果 `app_links` 当前版本支持项目现有 macOS 配置，则注册：

```text
gotoim-dev://
```

按照插件官方当前版本的 macOS 配置方式实现。

不要自行发明平台实现。

------

# 十三、Windows

Windows 也需要支持：

```text
gotoim-dev://
```

按照项目安装的 `app_links` 当前版本官方 Windows 实现方式注册协议。

需要考虑：

```text
GotoIM 已经启动
```

和：

```text
GotoIM 尚未启动
```

两种情况。

不要为了这个功能引入另一套 Deep Link 插件。

------

# 十四、路由处理

DeepLinkHandler 负责：

```text
DeepLinkTarget
       ↓
检查是否可以处理
       ↓
必要时检查登录
       ↓
调用项目现有 Router
```

不要直接依赖具体 Widget BuildContext，如果项目已有全局 Router / NavigationService，请复用。

不要引入 go_router、auto_route 等新的 Router，除非项目原本就在使用。

------

# 十五、登录状态

这些页面默认认为需要登录：

```text
chat
user
group
group invite
workbench
```

如果收到：

```text
gotoim-dev://chat/123
```

但是当前未登录：

```text
DeepLink
 ↓
保存 PendingDeepLink
 ↓
进入现有登录流程
 ↓
登录成功
 ↓
继续执行 PendingDeepLink
 ↓
进入 chat/123
```

如果项目当前登录模块还不适合接入：

不要破坏登录逻辑。

可以先实现：

```text
PendingDeepLink
```

接口和日志，并明确 TODO。

但是 Parser、Service、诊断功能必须可以独立运行。

OAuth 和 scan-login 是否要求登录，根据现有业务逻辑判断，不要擅自修改现有扫码登录协议。

------

# 十六、不要伪造不存在的页面

先搜索项目。

如果项目中已经存在：

```text
聊天页面
用户页面
群页面
工作台
扫码登录
```

则连接到真实 Router。

如果某个页面尚未实现：

DeepLinkParser 仍然支持解析。

Handler 返回：

```text
notImplemented
```

并在开发诊断中心明确显示：

```text
解析成功
业务页面暂未实现
```

不要为了完成 Deep Link 创建假的业务页面。

------

# 十七、安全要求

Deep Link 是不可信外部输入。

必须：

- 验证 scheme
- 验证 host
- 验证 path
- 验证参数格式
- 验证 messageId
- 对字符串长度做合理限制
- 错误 URI 不崩溃

禁止：

```text
Deep Link 自动删除数据
Deep Link 自动加好友
Deep Link 自动加入群
Deep Link 自动付款
Deep Link 自动修改账户
URL 携带 AccessToken
URL 携带 RefreshToken
```

对于邀请：

```text
打开确认页面
      ↓
用户主动确认
      ↓
调用服务器 API
```

------

# 十八、开发诊断中心

这是本任务的重要验收部分。

在现有“开发诊断中心”增加：

```text
Deep Link / App Links
```

测试页面。

不要单独做另一套 Debug App。

## 页面至少包含

### URI 输入

例如：

```text
gotoim-dev://chat/123/message/456
```

### 预设案例

提供快捷按钮：

```text
聊天
消息定位
用户
群
群邀请
扫码登录
工作台
OAuth
错误 URI
未知 URI
HTTPS 模拟
```

例如 HTTPS 模拟：

```text
https://gotoim.com/chat/123/message/456
```

------

# 十九、诊断页面提供两个按钮

## 解析

```text
[解析]
```

只调用：

```text
DeepLinkParser
```

不跳页面。

显示：

```text
Raw URI
Scheme
Host
Path
Query
NormalizedSegments
ParseStatus
TargetType
所有解析字段
错误信息
```

例如：

```text
ParseStatus: success
TargetType: ChatDeepLink
sessionId: 123
messageId: 456
```

------

## 执行

```text
[执行]
```

执行真实：

```text
DeepLinkHandler
```

显示：

```text
执行状态
是否需要登录
是否成功导航
失败原因
执行时间
```

------

# 二十、真实 App Link 事件日志

开发诊断中心必须能够看到通过 `app_links` 真正收到的 URI。

例如 Android 执行：

```text
adb shell ...
```

之后进入开发诊断中心，可以看到：

```text
14:03:22
source: app_links
uri: gotoim-dev://chat/123
status: success
target: ChatDeepLink
```

至少保留本次 App 生命周期最近若干条记录，例如 20 条。

不需要数据库持久化。

提供：

```text
清空日志
```

功能。

这样可以区分：

```text
只是 Parser 能工作
```

和：

```text
操作系统 → app_links → Flutter
真正能够工作
```

------

# 二十一、自动化测试

必须写测试，不允许只人工测试。

至少包括以下测试。

## DeepLinkParser

### 合法链接

```text
gotoim-dev://chat/123
gotoim-dev://chat/123/message/456
gotoim-dev://user/10086
gotoim-dev://group/888
gotoim-dev://invite/group/abc
gotoim-dev://scan-login/abc
gotoim-dev://workbench/mail
gotoim-dev://oauth/callback?code=123&state=456
```

### HTTPS

```text
https://gotoim.com/chat/123
https://gotoim.com/chat/123/message/456
```

必须与对应 `gotoim-dev://` 得到相同业务 Target。

### Production Scheme

测试：

```text
gotoim://chat/123
```

虽然当前开发 App 不一定注册该 Scheme，但 Parser 必须支持。

### 非法输入

测试：

```text
gotoim-dev://chat
gotoim-dev://chat/
gotoim-dev://chat/123/message
gotoim-dev://chat/123/message/abc
https://evil.com/chat/123
ftp://gotoim.com/chat/123
gotoim-dev://unknown/123
```

保证：

```text
不会 crash
```

并正确区分：

```text
invalid
unsupported
```

------

# 二十二、Normalize 单元测试

重点验证：

```text
gotoim-dev://chat/123/message/456
```

和：

```text
https://gotoim.com/chat/123/message/456
```

Normalize 后一致：

```text
chat
123
message
456
```

这是必须单独测试的逻辑。

------

# 二十三、Service 测试

不要让 DeepLinkService 强依赖真实 `AppLinks`，需要留一个最小的可测试入口。

可以通过：

```text
handleUri(Uri uri)
```

或者简单接口注入测试。

验证：

```text
收到 URI
 ↓
Parser
 ↓
Handler
```

以及：

```text
非法 URI
```

不会抛出未处理异常。

不要为了测试创建复杂抽象体系。

------

# 二十四、运行现有测试

完成后执行：

```bash
flutter analyze
```

以及：

```bash
flutter test
```

修复本次修改导致的问题。

不要为了让测试通过而删除已有测试。

不要修改与 Deep Link 无关的大量代码。

------

# 二十五、Android 人工测试

我会人工测试，所以必须提供明确的命令。

开发完成后，在文档和开发诊断中心显示测试命令。

## A. App 完全关闭

先确保 App 没有运行。

执行：

```powershell
adb shell am start -a android.intent.action.VIEW -d "gotoim-dev://chat/123"
```

预期：

```text
启动 GotoIM
收到 Deep Link
Parser 成功
进入对应页面，或者明确显示页面尚未实现
诊断日志存在该事件
```

------

## B. App 已运行

GotoIM 保持前台或后台：

```powershell
adb shell am start -a android.intent.action.VIEW -d "gotoim-dev://chat/123/message/456"
```

预期：

```text
现有 App 收到 URI
不启动错误的 App 实例
解析 ChatDeepLink
messageId = 456
执行页面跳转
```

------

## C. 用户

```powershell
adb shell am start -a android.intent.action.VIEW -d "gotoim-dev://user/10086"
```

------

## D. 群邀请

```powershell
adb shell am start -a android.intent.action.VIEW -d "gotoim-dev://invite/group/abcdef"
```

------

## E. 非法 URI

```powershell
adb shell am start -a android.intent.action.VIEW -d "gotoim-dev://chat/123/message/abc"
```

预期：

```text
App 不崩溃
诊断日志记录 invalid
不进行错误导航
```

------

# 二十六、iOS 人工测试

iOS Simulator：

```bash
xcrun simctl openurl booted "gotoim-dev://chat/123"
```

消息：

```bash
xcrun simctl openurl booted "gotoim-dev://chat/123/message/456"
```

分别测试：

```text
Cold Start
Warm Start
```

预期和 Android 相同。

------

# 二十七、Windows 人工测试

Windows 注册成功后，可以测试：

```powershell
Start-Process "gotoim-dev://chat/123"
```

以及：

```powershell
Start-Process "gotoim-dev://chat/123/message/456"
```

分别测试：

```text
GotoIM 未运行
GotoIM 已运行
```

必须确认：

```text
URI 确实到达 app_links
```

而不是仅仅 Parser 测试成功。

诊断中心必须能够看到真实接收日志。

------

# 二十八、macOS 人工测试

macOS 可使用：

```bash
open "gotoim-dev://chat/123"
```

或者根据当前 `app_links` 官方 macOS 配置和测试方式执行。

分别验证 Cold Start / Warm Start。

------

# 二十九、HTTPS 当前如何测试

当前不要尝试通过操作系统唤醒：

```text
https://gotoim.com/chat/123
```

因为 gotoim.com 尚未配置 DNS / HTTPS / App Links / Universal Links。

但是必须在：

```text
DeepLinkParser 单元测试
```

以及：

```text
开发诊断中心
```

验证：

```text
https://gotoim.com/chat/123/message/456
```

能够正确解析成：

```text
ChatDeepLink
sessionId = 123
messageId = 456
```

以后配置 HTTPS 后，不修改业务 Parser。

------

# 三十、开发文档

增加开发文档，例如：

```text
docs/development/deep-link.md
```

如果项目已有文档目录，使用现有目录。

写清：

```text
支持的平台
URI 协议
开发 Scheme
生产 Scheme
Android 测试命令
iOS 测试命令
Windows 测试命令
macOS 测试命令
Cold Start 测试方法
Warm Start 测试方法
诊断中心入口
当前 HTTPS 尚未启用
未来 gotoim.com 配置步骤
```

不要只写“参考官方文档”。

必须提供本项目可以直接复制执行的命令。

------

# 三十一、人工验收清单

开发完成后，请输出下面形式的验收表。

```text
[ ] flutter analyze 通过
[ ] flutter test 通过

Android
[ ] gotoim-dev://chat/123 冷启动
[ ] gotoim-dev://chat/123 热启动
[ ] message/456 正确解析
[ ] 非法 messageId 不崩溃

iOS
[ ] Scheme 已配置
[ ] Simulator 测试命令已提供
[ ] Cold Start
[ ] Warm Start

Windows
[ ] Scheme 注册
[ ] 未启动 App 时测试
[ ] App 已启动时测试

macOS
[ ] Scheme 配置
[ ] 测试命令已提供

Parser
[ ] gotoim-dev:// 正常
[ ] gotoim:// 正常
[ ] https://gotoim.com 正常
[ ] evil.com 被拒绝

开发诊断中心
[ ] URI 手工输入
[ ] 预设 URI
[ ] 解析
[ ] 执行
[ ] app_links 真实事件日志
[ ] 清空日志
```

其中：

自动化测试可以由 Codex 完成并标记。

真机 / 模拟器人工测试不要擅自标记通过，留给我自己确认。

------

# 三十二、Codex 完成后的回复格式

全部完成后不要只回复“已完成”。

请输出：

## 修改内容

说明增加和修改了哪些文件。

## 架构

简单说明：

```text
OS
 ↓
app_links
 ↓
DeepLinkService
 ↓
DeepLinkParser
 ↓
DeepLinkHandler
 ↓
Router
```

## 自动测试结果

输出实际执行：

```text
flutter analyze
flutter test
```

结果。

## Android 人工测试

给我可以直接复制执行的 PowerShell 命令。

## Windows 人工测试

给我可以直接复制执行的 PowerShell 命令。

## iOS / macOS

给出以后在 Mac 上人工验证的命令。

## 未完成事项

明确告诉我：

```text
哪些业务页面因为项目当前不存在而没有接入
哪些功能需要我人工测试
HTTPS App Links / Universal Links 尚未配置
```

不要隐藏未完成项。

------

# 三十三、限制

本任务不要：

- 重构整个 Router。
- 引入新的状态管理框架。
- 引入新的 Router 框架。
- 修改无关业务。
- 搭建 HTTPS 服务。
- 修改 gotoim.com DNS。
- 实现 assetlinks.json。
- 实现 apple-app-site-association。
- 创建假的业务页面。
- 为每个 DeepLink 创建大量抽象接口。
- 为简单 Parser 引入 code generator。

优先：

```text
简单
可测试
可诊断
可以人工验证
方便以后增加 HTTPS
```

现在开始：

1. 先检查项目现有目录、Router、登录状态和开发诊断中心。
2. 根据现有架构调整上述目录，不要机械照搬。
3. 实现功能。
4. 写自动测试。
5. 运行 analyze/test。
6. 补开发诊断中心。
7. 输出我可以人工执行的验证命令。