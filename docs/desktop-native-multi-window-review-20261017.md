# 原生多窗口改造代码审查

审查日期：2026-10-17  
审查对象：`a188c693744badfccfb1a3c5484cc3b9d9eab178` 上的当前工作区，包含 8 个未提交修改文件  
对照：[原生多窗口改进方案](desktop-native-multi-window-improvement-plan.md)

## 结论

**尚未完成方案要求。当前完成的是部分应用内页面/弹窗修复，真正的原生多窗口宿主、跨窗口通信和真实托盘浮窗仍未实现。不能按“微信式原生多窗口已完成”验收。**

本次只审查代码并运行相关自动化检查，没有修改业务代码，没有重新启动应用或采集这一版的 Windows 系统窗口截图。下面有关原生窗口的结论来自现有调用链与 runner 检查，不将前一轮截图冒充为本轮实机验证。

## 需要修复或补齐的问题

### 1. [P1] 新增外部播放入口直接把 URL 交给 cmd，存在命令注入

位置：[desktop_media_viewer_window.dart:148](../lib/features/media/presentation/desktop_media_viewer_window.dart#L148)，方法 `_openWithDefaultPlayer()`。

新增代码 `Process.run('cmd', ['/c', 'start', '', source])` 中，`source` 来自当前媒体。只检查 `http://` / `https://` 前缀不足以保证安全：Windows cmd 还会解释 URL 中的 `&` 等命令字符。普通带多个查询参数的 URL 也可能被截断或误执行后续片段。

本次使用相同的 Dart `Process.run → cmd /c` 参数传递方式执行无害 echo 探针，URL 后的 echo 标记被作为独立命令执行。探针没有启动浏览器、访问网络或读写用户文件；它验证的是 shell 参数解释行为，没有在真实消息里执行攻击载荷。

证据：[探针源文件](../screenshots/windows-review-20261017/command-argument-probe.dart)、[实际输出](../screenshots/windows-review-20261017/command-argument-probe.log)。

建议：通过现有平台/媒体服务使用不经过 shell 的系统 URL 打开能力，校验允许的 scheme；本地文件使用既有文件打开能力。UI 不直接拼接 shell 调用。对于同类旧入口也应检查，但本次新增问题首先修复。增加含多查询参数、Unicode、空格及 shell 字符的输入验证。

### 2. [P1] 核心“独立窗口”仍然是当前窗口内路由或 Dialog

位置：[window_service.dart:219](../lib/core/services/window_service.dart#L219)、[desktop_settings_window.dart:34](../lib/features/settings/presentation/desktop_settings_window.dart#L34)、[desktop_browser_window.dart:43](../lib/core/browser/desktop_browser_window.dart#L43)、[desktop_media_viewer_window.dart:53](../lib/features/media/presentation/desktop_media_viewer_window.dart#L53)。

`openChat()` 继续调用 `SafeChatNavigator.pushChat()`；设置、浏览器和媒体仍调用 `showDialog()`。没有找到创建额外 Flutter 顶层窗口的 Dart 或 runner 实现。Windows runner 仍只创建初始 `FlutterWindow`，没有子引擎创建/注册流程；主 Dart 入口仍直接运行完整 `bootstrap()`。

结果是这些入口仍不能实现独立拖出主窗口、跨屏、独立最小化和系统级窗口切换。增加 ownerId 到注册键、等待路由关闭、去掉 Widget 边框均不会创建新的 HWND。

建议：先完成方案 P0 的真实双窗口 POC，验证插件和安装包，再接入 WindowService 的 native 控制器。第一批完成主窗+聊天+设置，同时保留移动端路由回退。

### 3. [P1] 激活/关闭和托盘恢复主窗仍无实际窗口操作

位置：[window_service.dart:166](../lib/core/services/window_service.dart#L166)、[window_service.dart:176](../lib/core/services/window_service.dart#L176)、[tray_service.dart:218](../lib/core/services/tray_service.dart#L218)、[windows/runner/main.cpp:39](../windows/runner/main.cpp#L39)。

`bringToFront()` 只查询注册表并打印日志；`closeWindow()` 只删除注册记录，没有对 UI 或系统窗口执行关闭。主窗口 `main` 没有实际注册对象，托盘“打开 Goto IM”调用 `bringToFront('main')` 会直接返回。因此重复打开不能真正恢复/聚焦，托盘恢复路径也没有完成。

runner 仍使用 `SetQuitOnClose(true)`，没有找到隐藏到托盘的 native 关闭拦截。托盘“退出”仍 `dispose(); exit(0);`，既不等待托盘释放，也没有有序关闭数据库、任务和其他窗口。

建议：窗口登记关联真实控制器；激活执行 show/restore/focus；关闭由原生销毁事件确认清理。主窗关闭与退出采用不同策略，显式注册主窗并统一退出流程。

### 4. [P1] WindowMessenger 仍是占位实现，方案中的数据与身份协议未落地

位置：[window_messenger.dart:141](../lib/core/services/window_messenger.dart#L141)、[window_messenger.dart:154](../lib/core/services/window_messenger.dart#L154)、[window_service.dart:202](../lib/core/services/window_service.dart#L202)。

向其他窗口发送只输出日志，`sendToMain()` 没有远端请求/响应实现并返回 null。全项目搜索没有找到业务端实际使用 `windowMessengerProvider` 和 `WindowEvents` 连接消息、身份、主题等同步链路。当前 Provider 仍默认所有窗口都是主窗。

因此接入真实子窗后，不能依靠现在的代码完成数据查询、发送意图、消息增量或设置同步。方案要求的请求 ID、身份作用域、accountEpoch、快照/增量水位与权限校验均未落地。聊天 key 只有 ownerId+SessionUnit，没有账号/服务器/租户边界，ownerId 仍允许默认 0。共享 WAL 就会自动更新独立 Drift Stream 的旧注释也还在。

建议：在现有通信抽象下接入真实传输和有限命令，主引擎统一持有业务 Repository/认证/SignalR，子窗轻量启动。补充来源授权、账号代次与固定身份检查，不能只靠窗口标题或请求中的 ownerId。

### 5. [P1] 托盘由“默认示例数据”改成了“默认空”，真实未读尚未接通

位置：[tray_grouped_unread_provider.dart:9](../lib/core/services/tray_grouped_unread_provider.dart#L9)、[application_shell.dart:127](../lib/app/shell/application_shell.dart#L127)、[desktop_tray_message_box.dart:23](../lib/core/widgets/desktop_tray_message_box.dart#L23)。

初始状态改为空是正确的示例数据隔离，但尚未订阅真实会话/身份/未读数据。`setGroups()` 虽存在，搜索生产代码未找到调用；新增/模拟列表的调用仍只来自诊断页。主 Shell 更新的是 TrayService 的数值，不是浮窗分组。因此会出现真实角标有未读、聚合列表却为空的不同步情况。

浮窗仍使用 `showGeneralDialog()`，没有独立系统宿主；“全部已读/单会话已读”仍只是删除内存分组并更新托盘数值，没有接入已有业务已读流程。

建议：从现有 Repository/状态层投影真实可访问身份的未读列表，统一角标与浮窗数据源；操作走原有已读业务。窗口部分改为独立工具窗口，验证主窗隐藏后的使用与任务栏位置。

### 6. [P1] 视频错误提示已补，但 Windows 内嵌播放能力仍未修复

位置：[desktop_media_viewer_window.dart:100](../lib/features/media/presentation/desktop_media_viewer_window.dart#L100)、[pubspec.yaml:65](../pubspec.yaml#L65)、`pubspec.lock` 与 Windows 插件注册。

新增 catch 与错误卡片能替代先前部分无限加载场景，这是有效改进。但依赖仍是现有 `video_player`，没有找到 Windows 平台后端或相关替代实现；初始化调用与先前失败的播放器路径相同。错误提示不能作为真实视频播放成功的验收依据。

另外初始化没有超时；如果 Future 一直不完成，仍会持续加载。切换媒体/重试时旧控制器异步回调只检查 mounted，没有核对控制器实例或加载代次，旧视频的迟到错误可以覆盖当前视频的错误状态。

建议：先验证 Windows 播放后端并通过现有 MediaService 接入；加有界加载、当前加载代次判断和资源释放。外部播放只能作为明确的回退入口，并先修复第 1 项。

### 7. [P2] 注册先于有效窗口创建，失败路径仍可能留下假记录

位置：[window_service.dart:398](../lib/core/services/window_service.dart#L398) 及其他 open 方法的相同模式。

当前先 `_registerWindow()`，再检查 `rootNavigatorKey.currentContext`。没有有效 context 时，函数直接完成，但没有进入 finally 清理登记。之后即使 UI 已就绪，再次打开仍进入只有日志的 `bringToFront()`，导致该工具无法打开。

本轮单元测试没有挂载根 Navigator，却把留下的记录断言为成功。这恰好验证了“登记成功”，没有验证“窗口创建成功”。

建议：明确 Opening/Ready/Failed 状态，有效宿主/原生句柄/握手成功后再视作可用；无 context、创建失败和超时都要回滚并返回明确失败。测试覆盖首次失败后可重试。

## 局部改进的审查结果

| 修改 | 当前判断 | 仍欠缺的验证/实现 |
| --- | --- | --- |
| open 方法 await 路由/Dialog 并 finally 清理 | 有效改善正常弹窗关闭后的登记残留 | 没有 context 的失败清理；native 生命周期；关闭重开 Widget/实机测试 |
| 聊天 key 增加 ownerId | 部分完成身份区分 | 账号作用域、禁止无效 owner、原生来源授权和账号切换清理 |
| 分栏保存 `_activeOwnerId` 并清空旧选择 | 比旧的可变 controller 比较更可靠 | 本轮没有真实身份切换复测；无旧响应覆盖/权限失效的测试 |
| 输入区工具栏水平滚动、提示可省略 | 部分缓解局部溢出 | 分栏仍固定约 290 宽，未实现方案的主窗响应式分档与独立聊天布局 |
| 视频错误卡片、重试、外部播放入口 | 错误可见性改善 | Windows 后端、超时、加载代次和安全外部打开 |
| 默认托盘为空，诊断页显式加载 Mock | 示例数据不再默认冒充真实数据 | 真正的数据投影、已读业务和 native 浮窗 |
| 增加诊断操作 | 可手动注入示例状态 | HWND/插件 ID/握手/引擎/订阅诊断仍缺失 |

## 方案阶段完成度

| 阶段 | 本轮结论 |
| --- | --- |
| P0 原生双窗与插件/Release POC | 未找到实现及对应验证证据 |
| P1 真聊天/设置窗口与 native 生命周期 | 未完成；只完成部分应用内弹窗登记清理 |
| P2 跨窗消息与账号身份协议 | 未完成；分栏切换有局部修复 |
| P3 原生浏览器/媒体、真实 Windows 视频播放 | 未完成；视频失败展示有局部修复 |
| P4 原生托盘、真实未读、响应式/DPI/安装包 | 未完成；示例数据隔离与局部布局有改进 |

## 本次实际验证

1. 六个相关业务文件执行 `dart analyze`：**No issues found**。
2. 执行以下测试：**15 通过，0 失败**。

   ```powershell
   flutter test --no-pub --no-enable-impeller `
     test/core/services/window_service_test.dart `
     test/core/services/window_messenger_test.dart `
     test/desktop/desktop_tray_grouping_test.dart
   ```

3. 无害命令参数探针：确认 cmd 将媒体 URL 内的 `&` 解释为分隔符。
4. `git diff --check`：没有输出空白错误。

日志：[静态分析](../screenshots/windows-review-20261017/analyze.log)、[15 个测试](../screenshots/windows-review-20261017/targeted-tests.log)、[主要源码核对哈希](../screenshots/windows-review-20261017/source-hashes.json)。

这些测试的能力边界必须明确：窗口服务测试只检查 Map 登记；messenger 测试只断言主实例自身收到本地事件，没有断言子实例收到广播；Widget 测试把“无边框”定义为 `BoxDecoration.border == null`，没有创建或枚举系统窗口。因此测试通过与核心需求未完成并不矛盾。

本轮未执行完整构建、全量测试、真实账号收发、多显示器/DPI、原生托盘截图和干净环境 Release 包验证。不能据此宣称上述项目已通过。

## 建议交给修改 AI 的下一步

先修复新增的 shell URL 打开入口。然后按原方案顺序完成真正的双窗口 POC，不再以 Widget 外观或注册表数量代替窗口能力。POC 通过后，在现有 WindowService/WindowMessenger 内接入真实生命周期和通信，完成主窗+聊天+设置，再接真实未读和媒体浏览器。

下一轮交付应给出：冻结提交号、主窗与子窗同屏的系统截图、不同顶层 HWND、关闭重开与重复激活结果、实际子窗请求/事件收发记录、两个身份隔离结果，以及 Release 安装包验证。未交付这些证据前，保留“方案未完成”的结论。
