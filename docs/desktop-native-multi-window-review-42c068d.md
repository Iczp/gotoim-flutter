# 原生多窗口第三轮代码审查：42c068d

日期：2026-10-17  
被审提交：`42c068d`，审查开始时工作区干净。  
本轮仅审查、运行验证并生成审查产物，没有修改业务代码。  
对照：[改进方案](desktop-native-multi-window-improvement-plan.md)、[上一轮报告](desktop-native-multi-window-review-89e5e75.md)

## 结论

本次修复有实质进展：上轮新增的身份键、并发创建、媒体类型/本地路径 3 项回归已全部通过；主引擎也确实增加了发送、历史查询与退出登录代理。不能继续描述为“没有发送 handler”或“并发占位未实现”。

**目前仍不能验收完成。** 新接入的历史映射把对方消息当成自己发送，聊天子窗没有持续接收消息的链路，账号退出后的窗口缓存未清理，快传与诊断子窗的依赖/导航也未接通。浏览器外部打开仍经依赖间接执行 cmd。

本轮新增 3 项验收回归，分别验证消息方向、诊断路由与快传依赖，均实际失败。没有使用真实账号发送测试消息，也没有进行本提交的系统窗口、托盘和多显示器截图验收。

## 一、需要继续修复的问题

### 1. [P1] 历史消息按缓存 ownerId 判断发送人，对方消息会显示成自己发送

位置：[window_service.dart:936](../lib/core/services/window_service.dart#L936)。

historyLoader 使用 `'isMe': m.ownerId == ownerId`。`ChatMessage.ownerId` 是当前本地消息分区所属身份；同一分区中自己与对方的消息都会保存这个 ownerId，它不是消息发送人的身份。

本轮构造 senderSessionUnitId 为 peer-unit、当前会话为 self-unit 的真实模型输入，调用实际 WindowService Provider 的 historyLoader：**期望 isMe=false，实际 true**。这会把对方消息放到右侧自己的气泡中，影响会话理解。

建议复用已有 `ChatMessage.isMine` 或项目已有的准确发送人规则。补充自己、对方、群成员、Pending/Failed 和撤回消息的投影用例，保留必要的发送人/消息类型元数据。

### 2. [P1] 聊天子窗仍只有一次本地快照，没有实时接收、历史补齐和分页

位置：[desktop_sub_window_chat_view.dart:47](../lib/core/native_window/desktop_sub_window_chat_view.dart#L47)、[window_service.dart:924](../lib/core/services/window_service.dart#L924)。

`_loadHistory()` 只在 initState 调用一次，主引擎也只执行 `loadInitialLocal(limit:20)`。子窗没有数据订阅、消息事件处理或向上分页，主引擎没有为它发送消息变更；WindowMessenger 的跨窗实现仍为日志占位。

因此新消息即使已经写入主引擎数据库，也不会出现在已打开的子窗；本地没有历史时没有远端补齐，超过首批 20 条的历史无法继续查看。窗口缓存复用时也不会重新执行 initState，重新打开仍可能显示旧快照。

建议从主引擎现有消息/会话变更链路建立作用域订阅，完成首屏快照与增量衔接、补偿和游标分页；将相关业务请求纳入现有 WindowMessenger。不能仅证明文字发送能调用 Repository 就宣称独立聊天业务已经完整。

### 3. [P1] 退出账号后仍缓存旧子引擎，新账号可能重新看到旧账号数据

位置：[window_service.dart:254](../lib/core/services/window_service.dart#L254)、[window_service.dart:369](../lib/core/services/window_service.dart#L369)、[window_service.dart:437](../lib/core/services/window_service.dart#L437)。

app_logout 调用 closeAllSubWindows，但“关闭”只是把控制器转入 `_reusableControllers`。没有清除其中的聊天消息、草稿、网页状态和账号信息，也没有销毁缓存引擎。主界面的其他登出/账号切换路径没有找到对应窗口清理钩子。

窗口键仍不含账号/服务器/租户作用域，重新打开同键窗口直接 show 缓存控制器。新 payload 只写进主引擎 WindowRecord，没有发给旧子引擎；子引擎的 payload 和 Widget 状态保持原样。最直接的情况是账号 A 打开并关闭设置，换账号 B 后再次打开设置，仍复用带 A 信息的窗口。旧聊天内容也可能继续可见。

主 IPC handler 还仅相信请求自带的 ownerId/SessionUnit，没有账号代次或已授权窗口来源映射。不能因此断言后端已经允许跨账号发送，但客户端旧展示、旧请求与新凭据混用的边界尚未解决。

建议为账号切换统一增加 epoch，先拒绝旧请求并清除敏感展示，再销毁或安全重置所有活跃及缓存子窗。所有登录入口/退出入口共用这一流程；重新使用缓存必须同步新的作用域和初始化状态，不能仅修改注册表。

### 4. [P1] 快传子窗缺少 bootstrap 依赖，诊断子窗缺少 GoRouter

位置：[native_sub_window_app.dart:72](../lib/core/native_window/native_sub_window_app.dart#L72)、[native_sub_window_app.dart:250](../lib/core/native_window/native_sub_window_app.dart#L250)、[local_file_server_controller.dart:9](../lib/features/local_file_server/local_file_server_controller.dart#L9)。

轻量子窗只覆写 Environment 和 PlatformFacade，却直接挂载原 LocalFileServerPage。该页面需要 LocalNotificationService、ClientDeviceContext 和 ClientCapabilityService 等原 bootstrap 提供的对象。本轮 Widget 回归实际抛出：`UnimplementedError: LocalNotificationService must be provided at bootstrap.`

诊断入口现在选择了正确的 diagnostics 类型，但 DiagnosticsHomePage 内仍调用 context.push/go，而 NativeSubWindowApp 使用普通 MaterialApp，未提供 GoRouter。本轮点击“API 接口测试”实际抛出：`No GoRouter found in context`。

建议为工具子窗提供所需的轻量、受控依赖代理及局部导航宿主，或让诊断入口明确通过 IPC 在主窗口打开。不要为了避免缺依赖而在每个子窗重新执行完整 bootstrap，重复初始化全局业务与服务。

### 5. [P1] 浏览器外部打开的 cmd 风险仍藏在 OpenFilex 内部

位置：[desktop_browser_window.dart:104](../lib/core/browser/desktop_browser_window.dart#L104)。

调用改成了 `OpenFilex.open(_currentUrl)`，但本机锁定的 open_filex 4.7.0 在 `lib/src/platform/open_filex.dart:23` 的 Windows 分支实际执行：

```dart
Process.start('cmd', ['/c', 'start', '', filePath]);
```

因此只把直接 cmd 调用换成这个 wrapper 并没有消除命令解释，URL 中的 & 等仍会经过 cmd。该结论来自当前依赖源码核对；没有在浏览器或真实消息中执行攻击载荷。

依赖物理路径：`C:\Users\ZP\AppData\Local\Pub\Cache\hosted\pub.flutter-io.cn\open_filex-4.7.0\lib\src\platform\open_filex.dart`。

建议通过已有平台边界选用经验证不经过 shell 的系统打开能力，限制允许的 scheme，并检查最终实现与返回结果。媒体本地文件的 OpenFilex 回退也应一并核对；“业务文件里没有 cmd”不能作为修复完成的判据。

### 6. [P2] 窗口缓存上限只限制 Map，淘汰没有释放原生资源

位置：[window_service.dart:381](../lib/core/services/window_service.dart#L381)。

超过 `_maxReusableControllers=10` 时只 remove 最早的控制器，没有销毁对应 native 窗口/engine。此前的无限重开重复创建已有改善，但连续打开关闭 11 个不同会话，仍会留下被淘汰的隐藏窗口。Map 的长度不是实际引擎数。

事件清理循环也只遍历 `_nativeControllers`，已缓存窗口的销毁不能可靠同步到缓存。建议在淘汰时执行真正的原生销毁，等待确认后解除订阅，并用实际系统窗口/引擎数量做压力验收。

### 7. [P2] 主题请求能更新主窗，但当前子窗和其他子窗收不到变更

位置：[window_service.dart:260](../lib/core/services/window_service.dart#L260)、[native_sub_window_app.dart:113](../lib/core/native_window/native_sub_window_app.dart#L113)。

主 handler 调用 onThemeChanged 后直接返回，没有向子窗发送 theme_changed。子窗虽已增加接收 handler，自己的 MaterialApp 仍依赖 `_themeMode`，初始固定 dark；设置页修改的独立 Provider 不会直接改变该字段。因此存在“主窗口换了主题，设置/聊天窗口仍保持原主题”的情况。

建议主引擎提交设置后，向全部活跃/缓存子窗同步权威主题；新窗握手获取当前主题，字体与其他应用级设置采用同一机制。没有持久化完成的错误应有明确反馈。

## 二、上轮项目复核

| 上轮问题 | 本轮结果 |
| --- | --- |
| 子窗发送没有 handler | 已增加 handler，并调用主引擎现有 repo.sendText，传递同一 clientMessageId；不再按原问题重复报错。真实网络收发尚未执行验收 |
| 历史只显示欢迎文本 | 已增加一次本地历史查询，但方向判断错误，且缺少实时/补齐/分页 |
| 并发创建重复 | 原回归已通过：同键 pending 占位生效 |
| 完整身份键后缀误匹配 | 原回归已通过：完整键精确匹配；账号作用域与授权仍欠缺 |
| 媒体类型和 localPath 丢失 | 原回归已通过：这两项已保留；其他媒体元数据仍未完整传递 |
| 关闭后立即失去所有控制器 | 已增加隐藏窗口复用；账号隔离、缓存淘汰和真正销毁仍有问题 |
| 设置退出仅关窗 | 已增加 app_logout 主引擎代理；但退出不应保留旧账号缓存状态，异步失败也不应被忽略 |
| macOS 子引擎插件注册缺失 | 已补充 callback；Linux 也增加对应 callback。本机为 Windows，未执行两平台构建/实机验证 |
| 诊断类型/快传固定 URL 错误 | 类型、页面和 fallback 路径已调整；但新子窗依赖/路由实际失败 |
| 浏览器 cmd 风险 | 直接调用被移除，但依赖内部仍是 cmd，修复不完整 |

## 三、仍未完成的验收项

托盘真实未读分组、独立 native 浮窗、主窗登记与托盘恢复仍未见本轮实现；主窗关闭仍 SetQuitOnClose(true)，退出仍直接 exit(0)。自绘置顶/最大化、真实最小化、无边框拖动/DPI 等仍未完整接入 native 控制。Windows 视频后端、初始化超时和加载代次保护也未补齐。

本轮不把这些已有未完成项逐条重复包装成新增缺陷，但它们仍是原计划的验收缺口，不能因为部分测试通过而视为已完成。

## 四、本轮实际验证

- 静态分析：WindowService、native_window、浏览器、设置与媒体文件，**No issues found**。
- 原有 16 项测试加上上一轮 3 项回归：**19 通过，0 失败**。
- 本轮新增回归：**3 失败**，对应历史发送方错误、诊断子窗无路由、快传子窗依赖缺失。
- Windows Debug 构建：**成功**，约 178.4 秒；存在既有 WebView 插件 CMake CMP0175 开发警告。构建成功不等于上述运行时业务问题已解决。
- 未执行真实账号消息收发、登出换账号实机操作、native 窗口资源压力测试、托盘/多屏截图、Release 安装包及 macOS/Linux 构建。

复现命令：

```powershell
flutter test --no-pub --no-enable-impeller `
  test/core/services/window_service_test.dart `
  test/core/services/window_messenger_test.dart `
  test/desktop/desktop_tray_grouping_test.dart `
  screenshots/windows-review-89e5e75/regressions_test.dart

flutter test --no-pub --no-enable-impeller `
  screenshots/windows-review-42c068d/regressions_test.dart

flutter build windows --debug --no-pub
```

证据：[19 项测试日志](../screenshots/windows-review-42c068d/targeted-tests.log)、[新增回归源码](../screenshots/windows-review-42c068d/regressions_test.dart)、[3 项失败日志](../screenshots/windows-review-42c068d/regressions.log)、[静态分析](../screenshots/windows-review-42c068d/analyze.log)、[Windows 构建](../screenshots/windows-review-42c068d/build-windows.log)、[源码哈希](../screenshots/windows-review-42c068d/source-hashes.json)。

下一轮应先让本轮 3 项回归通过，并补充真实子窗接收新消息、账号 A→B 缓存失效和第 11 个缓存窗口释放的验证；然后在冻结提交上完成真实系统窗口与账号业务验收。
