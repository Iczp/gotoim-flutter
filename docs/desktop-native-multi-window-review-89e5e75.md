# 原生多窗口第二轮代码审查：89e5e75

审查日期：2026-10-17  
被审提交：`89e5e75a0cade0a5885ad1a4cc9c89fda2488cb0`  
审查开始时工作区干净；本轮没有修改业务代码。  
对照：[改进方案](desktop-native-multi-window-improvement-plan.md)、[上一轮审查](desktop-native-multi-window-review-20261017.md)

## 结论

本次确实增加了 `desktop_multi_window`、Windows 子引擎插件注册、主/子入口分流和 `WindowController.create()` 调用。不能再沿用上一轮“完全没有接入原生窗口创建”的结论。

**但目前仍不能验收为可用的微信式桌面多窗口。最严重的问题是新聊天子窗没有真实消息业务：点击发送只增加本地气泡，主引擎没有处理该发送请求。** 另外存在关闭后遗留隐藏引擎、并发重复创建、身份去重错误、设置操作失效和媒体序列化丢失等问题。

本轮完成源码审查、静态分析、现有相关测试和新增边界回归检查。原生多窗口的系统界面、跨屏、托盘与真实账号收发尚未在这一提交上执行实机截图验收；原来的 53 张截图不作为本次原生窗口已成功运行的证据。

## 一、优先修复的问题

### 1. [P1] 聊天子窗“发送”没有接入消息业务，会静默丢失消息

位置：[desktop_sub_window_chat_view.dart:68](../lib/core/native_window/desktop_sub_window_chat_view.dart#L68)、[desktop_sub_window_chat_view.dart:76](../lib/core/native_window/desktop_sub_window_chat_view.dart#L76)、[window_service.dart:169](../lib/core/services/window_service.dart#L169)。

子窗先把文字加入自己的 `_messages` 并清空输入，再调用 `chat_send_message`。主引擎的 `gotoim/ipc_to_main` handler 仅处理 `sub_window_closed`，其他方法直接返回 null。全项目搜索只有发送请求，没有对应接收分支。因此没有调用已有 MessageRepository、没有本地 Pending、没有 HTTP 发送，也没有服务端结果；子窗却一直显示自己刚输入的气泡。错误也被空 catch 吞掉。

初始消息只是本地欢迎文字，历史、实时接收、已读与撤回没有接入；图片、文件、截图等工具按钮仍为空回调。实际业务窗口不能用独立演示聊天列表替代现有聊天能力。

建议：复用现有 Repository/应用层发送与持久化流程，通过 WindowMessenger 完成有请求 ID、幂等标识和明确结果的代理；未确认时显示 Pending，失败保留可重试状态。补齐有界历史快照与增量订阅。真实收发未接通前应禁用发送或明确标注不可发送，避免误导用户。

### 2. [P1] 关闭只是 hide 后丢弃控制器，重复重开会遗留窗口和引擎

位置：[window_service.dart:254](../lib/core/services/window_service.dart#L254)、[native_sub_window_app.dart:109](../lib/core/native_window/native_sub_window_app.dart#L109)。

`closeWindow()` 从 `_nativeControllers` 移除控制器后只执行 `hide()`，随后删除注册记录；子窗关闭回调也只 hide。核对当前插件的 Windows 实现，`window_hide` 仅调用 `ShowWindow(hwnd, SW_HIDE)`，不会销毁 HWND、Flutter engine 或 WebView/媒体等资源。

因此点击自绘 X 后，旧引擎仍存在，业务注册表却不再知道它；下次打开会创建新引擎。`onWindowsChanged` 无法清理这些仍存活的隐藏窗口。用户反复打开/关闭设置或浏览器时会累积不可见窗口与资源。

建议：明确“隐藏”和“销毁”两种生命周期。普通子窗关闭应真正销毁，并在 native 确认后清理；如果产品选择缓存隐藏窗口，就必须保留控制器并在下次复用，设置受控上限。关闭协议同时核对窗口实例 ID，不能仅凭 targetId 清除重开后的新实例。

### 3. [P1] 并发创建没有原子占位，快速双击可创建两个同键窗口

位置：[window_service.dart:293](../lib/core/services/window_service.dart#L293)、[window_service.dart:300](../lib/core/services/window_service.dart#L300)。

在 `await WindowController.create()` 完成之前，既没有注册 Opening 记录，也没有保存同键 pending Future。两次 `openSettings()` 可以同时通过 `isWindowOpen()` 并各自创建 native 窗口；后完成的赋值覆盖前一个控制器，留下一个无法按 targetId 管理的窗口。

本轮新增回归使用延迟的 native 创建响应并发调用两次：**期望创建 1 次，实际创建 2 次**。现有“创建失败回滚”测试不能证明创建去重已经实现。

建议：按完整窗口键保存 pending Future，首次创建前同步占位；后续同键打开等待同一个结果。失败仅清理本次创建实例，成功握手后变为 Ready。

### 4. [P1] 身份去重仍按后缀匹配，完整窗口键中的 owner 被忽略

位置：[window_service.dart:218](../lib/core/services/window_service.dart#L218)。

`isWindowOpen()` 对所有 `chat:` 请求都提取最后一段 SessionUnitId，再检查任何 key 是否具有相同后缀。即使传入完整的 `chat:200:s1`，已有 `chat:100:s1` 也会被视为命中；接下来 `bringToFront('chat:200:s1')` 找不到对应控制器，静默不做操作。

本轮使用不同 owner、相同会话标识的边界输入复现：**期望两个完整 key 分别处理，实际只创建 1 次**。这是 API 对作用域处理错误的验证，不代表已经在真实账号中观察到同一 SessionUnit 跨 owner 合法复用；若后端禁止该组合，服务也应明确校验拒绝，不能误认为另一个身份窗口已存在。

同类后缀逻辑也出现在关闭路径。窗口键仍缺少账号/服务器/租户作用域，ownerId 仍允许默认为 0，且登出/账号切换没有关闭旧子窗的钩子。

建议：完整键只精确匹配。兼容旧无作用域 key 时应显式解析并拒绝歧义；窗口创建和命令校验明确绑定合法账号/owner/SessionUnit。接入账号代次、登出清理及迟到响应丢弃。

### 5. [P1] 设置子窗退出登录仅关闭窗口，主题设置也不同步

位置：[desktop_settings_window.dart:134](../lib/features/settings/presentation/desktop_settings_window.dart#L134)、[desktop_settings_window.dart:552](../lib/features/settings/presentation/desktop_settings_window.dart#L552)、[native_sub_window_app.dart:126](../lib/core/native_window/native_sub_window_app.dart#L126)。

原生子窗确认“退出登录”后仅调用 onClose 并 return，完全不调用主引擎退出业务。这是桌面端已改为默认新窗口路径后的功能退化：用户确认退出，原账号仍登录并连接。

主题和字体修改仍操作子引擎自己的 ProviderContainer；主引擎没有 IPC 通知，已加载的主题状态不更新。NativeSubWindowApp 又硬编码 `ThemeMode.dark`，甚至不会响应子引擎自身的主题选择。重新读取持久化配置不能代替正在运行的主窗/其他子窗同步。

设置“插件”页还会构造子引擎自己的 WindowService，尝试注册本应只由主引擎持有的同名单向 IPC handler；注册 Future 没有 await，错误不会被外层同步 try/catch 接住。该架构应一并修正。

建议：退出、主题、字体和存储等设置通过主引擎执行，再广播权威状态；子窗使用代理依赖，避免创建第二个全局 WindowService。无法支持的操作应明确禁用，而不是确认后只关窗。

### 6. [P1] 媒体跨窗传输丢失类型和本地路径，视频会被重建成图片

位置：[window_service.dart:523](../lib/core/services/window_service.dart#L523)、[native_sub_window_app.dart:166](../lib/core/native_window/native_sub_window_app.dart#L166)。

序列化每项仅保留 id、messageId、source，丢弃 `MediaPreviewType`、localPath、缩略图、文件名及保存目录所需的账号/会话信息。子窗再用 URL 是否以 `.mp4`/`.mov` 结尾推测类型。带查询参数的签名 URL、无扩展资源地址和其他视频格式都会被误判为图片；已下载的本地缓存路径也不再优先使用。

新增回归传入显式 video 类型、无扩展 URL 与本地缓存路径：**传输中 type 实际为 null**，且未保留 localPath。此测试未播放视频，而是验证错误发生在进入播放器之前。

建议：定义完整但有界的媒体传输协议，保留明确类型和受授权的资源/缓存引用，不重新猜测类型；二进制大对象不放入启动参数，内存图片可使用受控临时资源引用。初始 index 也应在接收端校验。

### 7. [P1] 主窗口恢复、账号退出与托盘真实数据仍未完成

位置：[tray_service.dart:218](../lib/core/services/tray_service.dart#L218)、[window_service.dart:231](../lib/core/services/window_service.dart#L231)、[windows/runner/main.cpp:39](../windows/runner/main.cpp#L39)、[tray_grouped_unread_provider.dart:9](../lib/core/services/tray_grouped_unread_provider.dart#L9)。

主窗 `main` 未加入控制器映射，托盘“打开”调用仍找不到对象。子窗 bringToFront 仅 show；当前插件 Windows 实现使用 SW_SHOW，没有实现还原最小化或焦点激活。主窗关闭仍 SetQuitOnClose(true)，没有隐藏到托盘的原生策略；退出仍直接 exit(0)。

真实未读分组依然初始化为空，生产链路没有 setGroups/真实订阅；浮窗还是主窗口内 showGeneralDialog，已读动作仍只改本地分组。上一轮这项没有完成。

建议：注册和控制主窗，落实关闭/退出区分，接入同一真实未读数据投影和原有已读业务，再将浮窗放入独立工具窗口。使用实际窗口状态和 HWND 验证恢复效果，不能只依赖 show 返回成功。

## 二、其他明确遗漏

| 优先级 | 问题与位置 | 影响与建议 |
| --- | --- | --- |
| P1 | [浏览器外部打开仍走 cmd](../lib/core/browser/desktop_browser_window.dart#L103) | 媒体入口移除 shell 的修复有效，但浏览器同类 URL 入口仍有命令解释风险；统一通过无 shell 的平台服务打开 |
| P1 | [macOS runner 未注册子引擎插件回调](../macos/Runner/MainFlutterWindow.swift#L11) | 仅改了 Windows callback；macOS 子窗中的 WebView、文件选择、SecureStorage 等未具备对应注册流程。按本地插件 README 补齐并实机验证 |
| P1 | [WindowMessenger 仍为占位](../lib/core/services/window_messenger.dart#L141) | 新增零散 WindowMethodChannel 未接入现有通信抽象，尚无消息快照/增量、权限、请求 ID、账号代次。共享 WAL 自动更新 Stream 的旧注释也未纠正 |
| P2 | [诊断入口错误使用 settings 类型](../lib/core/services/window_service.dart#L620) | “开发诊断中心”实际打开设置；使用 diagnostics 类型承载原诊断能力 |
| P2 | [快传入口硬编码 127.0.0.1:8080](../lib/core/services/window_service.dart#L665) | 原控制台被替换为访问可能未启动的固定网页，且 fallback 改成未定义的 /fileserver；恢复已有 /local-file-server 控制台与服务状态管理 |
| P2 | [自绘聊天标题栏](../lib/core/native_window/desktop_sub_window_chat_view.dart#L167) | 置顶/最大化只改布尔值，最小化用 hide；没有 native 拖动/命中测试/无边框样式。插件默认创建 WS_OVERLAPPEDWINDOW，Widget 外观不等于无边框宿主 |
| P2 | [浏览器最小化](../lib/core/browser/desktop_browser_window.dart#L478) / [媒体最小化](../lib/features/media/presentation/desktop_media_viewer_window.dart#L642) | 仍 Navigator.pop，在子窗根路由上不对应 native 最小化；页签关闭等相同入口需逐项改为实际窗口或页签操作 |
| P2 | [视频初始化](../lib/features/media/presentation/desktop_media_viewer_window.dart#L104) | 仍无 Windows 后端，未找到所述 8 秒 timeout 或加载 epoch，旧异步回调竞态未修复；错误卡片不能当作播放成功 |
| P2 | [IPC 注册初始化](../lib/core/services/window_service.dart#L169) | handler 注册未 await、监听订阅没有保存/释放、创建后没有 ready 握手且 hiddenAtLaunch=false；易出现异步注册失败、首屏未就绪或长期订阅残留 |

## 三、上轮问题的复核状态

| 上轮项目 | 本轮结果 |
| --- | --- |
| 媒体 cmd 注入 | 该入口已改为直接 explorer/OpenFilex，旧的 shell 路径移除；浏览器同类路径仍需修复 |
| 没有原生创建 | 已有实际创建调用、入口分流和 Windows 子引擎插件注册，取得进展；不是完整业务验收通过 |
| 激活/关闭/托盘恢复 | 子窗增加 show/hide，销毁、恢复焦点和主窗托盘路径仍有缺陷 |
| 通信/身份协议 | 仅接通关闭通知；聊天请求无处理，完整协议仍未完成 |
| 真实托盘未读 | 未完成 |
| 视频后端、超时、代次 | 未完成；错误提示保留 |
| 无 context 遗留假登记 | 回退路径已把登记移动到有效 context 内，现有失败回滚测试通过 |

## 四、实际验证与证据

- 静态分析：`main.dart`、native_window 目录、WindowService、浏览器、设置及媒体窗口，**No issues found**。
- 现有相关测试：窗口服务、WindowMessenger、托盘分组与窗口 Widget，**16 通过，0 失败**。
- 本轮新增的 3 个验收回归：**3 失败**，分别复现身份去重错误、并发重复创建和媒体元数据丢失。这些测试位于审查产物目录，没有改动正式 test 目录。
- Windows Debug 构建：**成功**，约 174.9 秒；存在既有 WebView CMake CMP0175 开发警告。构建成功不等于业务发送、窗口资源释放或实机交互已通过。
- 本轮没有执行真实账号收发和系统窗口 UI 操作，没有声称跨屏、DPI、托盘或 Release 安装包已通过。

复现命令：

```powershell
flutter test --no-pub --no-enable-impeller `
  test/core/services/window_service_test.dart `
  test/core/services/window_messenger_test.dart `
  test/desktop/desktop_tray_grouping_test.dart

flutter test --no-pub --no-enable-impeller `
  screenshots/windows-review-89e5e75/regressions_test.dart

flutter build windows --debug --no-pub
```

证据：[静态分析日志](../screenshots/windows-review-89e5e75/analyze.log)、[现有测试日志](../screenshots/windows-review-89e5e75/targeted-tests.log)、[新增回归源码](../screenshots/windows-review-89e5e75/regressions_test.dart)、[3 项失败结果](../screenshots/windows-review-89e5e75/regressions.log)、[Windows 构建日志](../screenshots/windows-review-89e5e75/build-windows.log)、[审查源码哈希](../screenshots/windows-review-89e5e75/source-hashes.json)。

## 五、下一轮应如何交付

优先把子窗发送、历史和订阅接回原有业务链，再处理窗口生命周期、并发和身份边界；设置、媒体和托盘沿用同一主引擎代理协议。复用现有能力，不增加第二套演示聊天、登录或消息缓存。

修复后先让上述 3 个回归通过，再补充真正断言子窗请求被主 Repository 执行、发送失败可重试、旧账号不能继续操作、关闭后引擎释放的测试。最后在冻结提交上给出主窗与聊天/设置同屏、不同顶层 HWND、关闭重开、主窗托盘恢复、两身份收发隔离和 Release 包的实机证据。
