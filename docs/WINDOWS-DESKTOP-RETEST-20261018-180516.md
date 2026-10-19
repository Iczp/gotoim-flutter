# GotoIM Flutter Windows 修复后复测报告
测试日期：2026-10-18（Asia/Shanghai）
测试批次：windows-retest-20261018-180516
项目：F:\Dev\GotoIM\gotoim-flutter

## 1. 验收结论

**本轮复测不通过完整桌面端验收。** 修复确实改善了自定义标题栏、文本消息同步、历史排序、主题、媒体/网页原生窗口入口、文件/诊断路由和窄窗布局。但关闭媒体或浏览器子窗会影响主进程响应及生命周期，属于当前最优先处理的问题。

- Windows Debug 构建成功，受影响的11个分析目标无问题，8个测试文件共45项自动化测试通过。
- 使用真实账号完成界面操作，共保存49张本轮原始JPEG；没有复用旧截图，也没有把组件测试生成图当作实机截图。
- 新增3条真实文本：林惠娟独立窗→私人助理 `4`；林惠娟主窗→私人助理 `5`；私人助理→林惠娟 `6`。3次发送均HTTP200，消息保留。
- 默认系统标题栏在已测窗口中已隐藏。**这次已经使用自定义顶栏；但诊断/文件窗缺少完整窗口按钮，不能据此判定所有自定义窗口交互完成。**
- 托盘实际图标、右键菜单、真实未读浮窗未取得截图，仍未验收。

[本轮截图画廊](../screenshots/windows-retest-20261018-180516/index.html) · [截图清单](../screenshots/windows-retest-20261018-180516/captures.json) · [验证记录](../screenshots/windows-retest-20261018-180516/validation.json) · [筛除敏感行的运行日志](../screenshots/windows-retest-20261018-180516/runtime-sanitized.log)

## 2. 测试基线与环境

| 项目 | 本轮记录 |
|---|---|
| 基础提交 | `106c8f55f8a0db793bf2ee830931ad8dbb8f7c57` |
| 实际被测版本 | **该提交加当前未提交修复**，不是单纯HEAD；见source-status.txt、worktree.patch和source-hashes.json |
| 源码核验 | 对lib、windows及pubspec配置共460个文件记录SHA256，测试结束未发现变化 |
| 系统 | Windows 11 家庭版中文版，10.0.26300，64位 |
| Flutter命令 | E:\sdk\flutter-3.47.0-active\bin\flutter.bat |
| 构建模式 | Windows x64 Debug |
| 渲染 | 默认Impeller；本轮未切软件渲染或关闭Impeller运行客户端 |
| 账号 | 复用真实登录态，选择器显示186****9806；未重新测试密码登录 |
| 身份/对象 | 林惠娟（ownerId13）及同账号拥有的私人助理机器人 |
| 物理设备范围 | 当前一台Windows；机器人另一身份不是另一物理设备 |
| 其他配置 | 显示DPI及跨显示器场景未验证 |

测试包含3次独立客户端启动。首次测试进程31884关闭媒体后无响应，由测试人员结束并重启；第二次进程44544关闭浏览器后无响应，随后进程结束；第三次进程63476已恢复并保持响应。窗口句柄仅是本次观察值，禁止写死到代码。

测试人员未修改业务源码，未提交或回滚用户修复。未删除/撤回消息、清缓存、迁移附件、强制下线设备、退出登录、启动文件共享或注入托盘Mock数据。

## 3. 构建、静态分析与自动化测试

工作目录：`F:\Dev\GotoIM\gotoim-flutter`。

```powershell
flutter build windows --debug --no-pub
```

结果：成功，用时174.4秒。存在已有的WebView CMake CMP0175开发警告。见[build.log](../screenshots/windows-retest-20261018-180516/build.log)。

受影响的窗口适配、子窗、WindowService、托盘投影、ApplicationShell、网页、媒体、布局和设置文件执行了 `flutter analyze --no-pub`，结果 `No issues found! (ran in 13.6s)`。见[analyze.log](../screenshots/windows-retest-20261018-180516/analyze.log)。

```powershell
flutter test --no-pub --no-enable-impeller test/core/services/window_service_test.dart test/core/services/window_messenger_test.dart test/core/services/storage_path_service_test.dart test/core/attachment_cache_classified_test.dart test/desktop/desktop_clipboard_paste_test.dart test/desktop/desktop_tray_grouping_test.dart test/desktop/desktop_comprehensive_suite_test.dart test/desktop/desktop_real_account_suite_test.dart
```

结果：45项通过、0项失败。见[targeted-tests.log](../screenshots/windows-retest-20261018-180516/targeted-tests.log)。

文件名中的“real_account_suite”不代表本轮真实客户端端到端测试：这些测试使用组件环境、假平台或构造数据。其渲染图片未计入本轮49张实机截图。自动化通过与以下运行失败分别报告。

客户端均使用新构建二进制：
```powershell
flutter run -d windows --debug --no-pub --no-hot --use-application-binary=F:/Dev/GotoIM/gotoim-flutter/build/windows/x64/runner/Debug/gotoim_flutter.exe
```

## 4. 上一轮缺陷逐项对照

| 上轮问题 | 本轮实测 | 结论与证据 |
|---|---|---|
| 默认系统标题栏/聊天双标题栏 | 主窗、聊天、设置、媒体、网页、诊断、文件窗均已隐藏默认标题栏 | 样式改善；完整操作部分通过：[03](../screenshots/windows-retest-20261018-180516/03-main-custom-titlebar-restored.jpg)、[05](../screenshots/windows-retest-20261018-180516/05-chat-native-custom-titlebar-history.jpg)、[19](../screenshots/windows-retest-20261018-180516/19-settings-initial-light-custom-titlebar.jpg) |
| 自绘最大化只改图标 | 主窗、聊天、媒体实际改变窗口尺寸；聊天可还原；主窗顶栏双击也能最大化 | 已修复已测场景：[06](../screenshots/windows-retest-20261018-180516/06-chat-custom-maximize-working.jpg)、[34](../screenshots/windows-retest-20261018-180516/34-media-custom-maximized.jpg)、[49](../screenshots/windows-retest-20261018-180516/49-main-titlebar-doubleclick-final.jpg) |
| 置顶不接系统 | 聊天开启置顶后激活主窗，子窗仍在上方；已取消置顶 | 已通过该场景：[11](../screenshots/windows-retest-20261018-180516/11-chat-pinned-over-main.jpg) |
| 主窗→聊天子窗不同步 | 主窗发送5，原子窗实时出现5 | 已通过：[09](../screenshots/windows-retest-20261018-180516/09-main-send-5.jpg)、[10](../screenshots/windows-retest-20261018-180516/10-child-received-main-5.jpg) |
| 另一身份入站未到子窗 | 机器人发6，原林惠娟子窗实时收到，方向正确 | 已通过：[16](../screenshots/windows-retest-20261018-180516/16-bot-send-6.jpg)、[17](../screenshots/windows-retest-20261018-180516/17-child-received-incoming-6.jpg) |
| 历史倒序、缺少最新内容 | 子窗旧→新排列，含test/2/3及本轮4/5/6，关闭重开后仍存在 | 首载/重开通过；完整分页未验收：[05](../screenshots/windows-retest-20261018-180516/05-chat-native-custom-titlebar-history.jpg)、[18](../screenshots/windows-retest-20261018-180516/18-chat-close-reopen-current-history.jpg) |
| 视频/网页真实入口仍是Dialog | 从真实消息点击后新增独立系统窗口 | 入口已修复：[media-window-audit.json](../screenshots/windows-retest-20261018-180516/media-window-audit.json)、[browser-window-audit.json](../screenshots/windows-retest-20261018-180516/browser-window-audit.json) |
| Windows视频初始化未实现 | 仍报init未实现，新增正常错误页和系统播放器入口 | **未修复播放能力**：[33](../screenshots/windows-retest-20261018-180516/33-native-video-window-playback-unavailable.jpg) |
| 文件资源管理器路由失败 | 进入真实资源列表，可返回 | 已修复：[30](../screenshots/windows-retest-20261018-180516/30-file-resource-manager-navigation-working.jpg) |
| 桌面诊断进入占位页 | 可进入实际桌面窗口测试工具 | 已修复：[26](../screenshots/windows-retest-20261018-180516/26-diagnostics-desktop-route-working.jpg) |
| 诊断浅底浅字 | 深色分组可读 | 已修复已测首屏：[25](../screenshots/windows-retest-20261018-180516/25-diagnostics-dark-readable.jpg) |
| 设置首开主题不继承 | 主窗浅色时设置首开浅色；切深/浅继续同步 | 已修复：[19](../screenshots/windows-retest-20261018-180516/19-settings-initial-light-custom-titlebar.jpg)、[20](../screenshots/windows-retest-20261018-180516/20-settings-dark-theme.jpg)、[21](../screenshots/windows-retest-20261018-180516/21-main-dark-theme-synced.jpg)、[28](../screenshots/windows-retest-20261018-180516/28-settings-restored-light.jpg) |
| 窄窗聊天区受挤压 | 695px时左侧栏缩小，聊天区约365px，发送和工具按钮可见 | 基本布局改善；长文本/跨DPI未覆盖：[41](../screenshots/windows-retest-20261018-180516/41-main-narrow-695-improved.jpg) |
| 托盘真实数据未接入 | 新增真实会话投影的代码；实际托盘未拍到 | 不能判定端到端通过；见第7节 |

## 5. 本轮新发现和仍失败的问题

### R-D01 / P0：媒体、浏览器子窗关闭影响整个客户端

复现A（默认配置第一进程）：

1. 从真实聊天视频打开媒体独立窗，出现播放器不支持错误页。
2. 点击自绘最大化，媒体窗口实际最大化：[34](../screenshots/windows-retest-20261018-180516/34-media-custom-maximized.jpg)。
3. 点击自绘关闭。
4. 回到主窗后选择会话，连续两次点击操作超时；进程31884的 `Responding=False`。
5. 保留证据后结束该测试进程，重启才能继续。

复现B（重启后的第二进程）：

1. 从真实URL消息打开浏览器独立窗。
2. 网页重试后黑屏，窗口最大化。
3. 在子窗仍打开时激活主窗并切通讯录，主窗可正常操作：[46](../screenshots/windows-retest-20261018-180516/46-main-usable-with-browser-open.jpg)。
4. 再激活浏览器，点击自绘关闭。
5. 进程44544立即出现 `Responding=False`；恢复检查时该进程已经结束，flutter run返回退出码0。不能仅凭退出码0判定正常业务关闭。

证据：[hang-after-media-close.json](../screenshots/windows-retest-20261018-180516/hang-after-media-close.json)、[hang-after-browser-close.json](../screenshots/windows-retest-20261018-180516/hang-after-browser-close.json)、[47](../screenshots/windows-retest-20261018-180516/47-browser-close-hang-main-occluded.jpg)。

当前证据支持“关闭子窗导致主客户端无响应/结束”，**尚未证明是崩溃、死锁、关闭错窗口还是插件销毁顺序问题**；没有采集线程转储，不把推断写成已定位根因。

代码线索：

- `desktop_media_viewer_window.dart:714`、`desktop_browser_window.dart:544`：先调用未等待的 `onClose`，随后又执行 `WindowsWindowAdapter.close()`。
- `native_sub_window_app.dart:292`：onClose同时执行IPC登记和hide。
- `windows_window_adapter.dart:182`：关闭使用同步 `SendMessage(WM_CLOSE)`；:24/30通过GetActiveWindow/GetForegroundWindow寻找目标。
- 当前存在“异步登记/隐藏”与“同步原生关闭”两条并行路径，目标窗口也没有固定绑定到具体子窗。需要验证所属线程、HWND归属和插件生命周期。

改进要求：统一单一关闭策略，明确隐藏复用还是销毁；串行完成登记与资源释放，绑定具体子窗句柄，不依赖异步时刻的前台窗口。不要仅替换一个Win32函数就声称修复。

验收：真实网页、图片、视频子窗反复开关至少20轮；每次关闭后主窗仍响应、真实消息可收发、其他子窗可操作；主进程不结束，注册表/引擎资源无残留。

### R-D02 / P1：真实网页仍未正确显示内容

真实URL `http://10.0.5.20:3000` 已进入独立窗口，但初始显示 `Indicates that the connection was stopped.`：[43](../screenshots/windows-retest-20261018-180516/43-native-browser-url-error.jpg)。

点击“手动加载”后内容区变黑，没有得到可读页面：[44](../screenshots/windows-retest-20261018-180516/44-browser-manual-reload-black.jpg)。同机对该地址的独立HTTP HEAD请求返回200、Content-Type为text/html，记录见[url-reachability.json](../screenshots/windows-retest-20261018-180516/url-reachability.json)。

HEAD成功只证明该HTTP请求可达，不能证明网页脚本、资源和应用内WebView正常。当前不足以归咎目标站点；需检查WebView初始化、导航事件、加载中止原因、错误重试及子引擎插件运行状态。

浏览器系统窗最大化后，自绘顶栏只占约1680px，未铺满2560px客户区：[45](../screenshots/windows-retest-20261018-180516/45-browser-maximized-black-content.jpg)。应同时去掉Dialog时代遗留的宽高限制，验证窗口内容随原生客户区缩放。

### R-D03 / P1：Windows应用内视频仍不可播放

错误页提示“当前平台视频播放组件未能成功加载”，底层仍为 `UnimplementedError: init() has not been implemented.`：[33](../screenshots/windows-retest-20261018-180516/33-native-video-window-playback-unavailable.jpg)。

本轮只核对已有真实1.6KB/00:01视频，未把系统播放器按钮未实测的能力算作通过。应核对现有播放器Windows实现与插件注册，使用已知有效本地/远程视频完成播放、音频、暂停、进度和关闭释放验收。

### R-D04 / P1：最小化后业务入口无法恢复聊天子窗

1. 子窗自绘最小化后从主窗前消失：[12](../screenshots/windows-retest-20261018-180516/12-chat-minimized-main-visible.jpg)。
2. 从主窗再次点击“在独立窗口打开”，两次观察仍未恢复，窗口枚举还存在原ID：[13](../screenshots/windows-retest-20261018-180516/13-chat-reopen-after-minimize-failed.jpg)。
3. 使用自动化工具直接激活窗口才恢复。该恢复不能算业务入口通过。

需在现有WindowService及具体子窗控制通道中区分show、restore和focus，验证任务栏/主窗入口均能恢复最小化窗口。

### R-D05 / P1：部分无边框工具窗没有完整窗口控制

诊断窗和文件窗移除了默认标题栏，但顶部仅为页面AppBar，没有窗口最小化、最大化或关闭按钮：[25](../screenshots/windows-retest-20261018-180516/25-diagnostics-dark-readable.jpg)、[29](../screenshots/windows-retest-20261018-180516/29-file-server-light-no-window-controls.jpg)。

文件资源管理器导航已修复，但最终需要Alt+F4关闭文件窗。不能把移除默认标题栏视为自定义窗口交互完整。应复用既有窗口能力统一外壳，明确拖拽区、按钮、状态同步和关闭策略；设置窗也仅提供部分窗口按钮。

### R-D06 / P1：首次默认启动存在持续白屏现象

第一次默认运行时，日志显示真实账号与SignalR已连接，可访问性树能读到界面，但窗口激活后数次捕获仍全白：[01](../screenshots/windows-retest-20261018-180516/01-default-renderer-white-window.jpg)。

通过系统菜单最大化后绘制恢复：[02](../screenshots/windows-retest-20261018-180516/02-main-custom-titlebar-maximized.jpg)。之后两次默认配置重启未再出现持续白屏，因此登记为**本轮出现一次、可经尺寸变化恢复的启动渲染问题**，不声称每次必现。需检查原生样式修改与Flutter首帧/尺寸变更时序。

### R-D07 / P2：托盘角标临时图片存在文件占用错误

真实消息测试期间日志出现 `PathAccessException`，写入 `gotoim_tray_badge_29_normal.png` 时提示另一个程序正在使用文件、errno32。

这表明角标更新链路存在失败；不能由初始化日志成功推导所有更新成功。建议核对同一路径并发写入、图标读取占用和重复触发，复用现有服务串行化/合并更新并确保文件生命周期安全。证据见[runtime-sanitized.log](../screenshots/windows-retest-20261018-180516/runtime-sanitized.log)。

## 6. 其他实测记录与限制

| 项目 | 本轮结果 | 证据 |
|---|---|---|
| 子窗发送4→主窗 | 成功，无可见重复气泡 | [07](../screenshots/windows-retest-20261018-180516/07-child-send-4.jpg)、[08](../screenshots/windows-retest-20261018-180516/08-main-after-child-4.jpg) |
| 切换机器人身份 | 主窗清除旧聊天，加载机器人自己的会话 | [14](../screenshots/windows-retest-20261018-180516/14-real-account-identity-selector.jpg)、[15](../screenshots/windows-retest-20261018-180516/15-bot-received-4-and-5.jpg) |
| 切回原身份 | 主窗显示最新6，方向正确 | [31](../screenshots/windows-retest-20261018-180516/31-main-received-6-restored-owner.jpg) |
| 设置快捷键/通知/关于 | 首屏可读；通知开关未改动 | [22](../screenshots/windows-retest-20261018-180516/22-settings-shortcuts.jpg)、[23](../screenshots/windows-retest-20261018-180516/23-settings-notifications.jpg)、[24](../screenshots/windows-retest-20261018-180516/24-settings-about.jpg) |
| 通讯录/工作台/探索 | 首屏正常；未覆盖所有业务子模块 | [35](../screenshots/windows-retest-20261018-180516/35-contacts-after-restart.jpg)、[36](../screenshots/windows-retest-20261018-180516/36-workbench.jpg)、[37](../screenshots/windows-retest-20261018-180516/37-explore.jpg) |
| 设备管理 | 真实35条设备，当前Windows，仅查看 | [38](../screenshots/windows-retest-20261018-180516/38-devices-real-list.jpg) |
| 主窗尺寸 | 1269×715、935×715、695×715、2560×1440 | [03](../screenshots/windows-retest-20261018-180516/03-main-custom-titlebar-restored.jpg)、[40](../screenshots/windows-retest-20261018-180516/40-main-medium-935.jpg)、[41](../screenshots/windows-retest-20261018-180516/41-main-narrow-695-improved.jpg)、[42](../screenshots/windows-retest-20261018-180516/42-main-maximized-custom.jpg) |
| 自定义标题栏双击 | 最大化成功 | [49](../screenshots/windows-retest-20261018-180516/49-main-titlebar-doubleclick-final.jpg) |
| 自定义标题栏拖动 | 两次自动化拖动未观察到位置变化，需人工复核，不记通过 | [titlebar-drag-audit.json](../screenshots/windows-retest-20261018-180516/titlebar-drag-audit.json) |
| 富消息在聊天子窗 | 文件等非文本消息出现空白气泡，未复用主窗完整渲染 | [05](../screenshots/windows-retest-20261018-180516/05-chat-native-custom-titlebar-history.jpg)、[06](../screenshots/windows-retest-20261018-180516/06-chat-custom-maximize-working.jpg) |

聊天子窗首载排序通过不代表完整历史分页通过；当前仍是最多20条本地快照路径。未完成断网重连、历史连续分页/滚动锚点、发送失败重试、外部第二设备入站、图片真实入口、上传下载、通话、多显示器/DPI、Release安装包和长期稳定性验收。

首次运行和后续恢复均为默认渲染；工具截图/激活动作可能影响窗口焦点和还原状态，结果以实际观察的时点为准。未将一次未成功输入、未完成尺寸调整或未完成拖动写成业务成功。

日志仍有桌面proximity事件订阅的MissingPluginException，需要按能力支持状态避免无效订阅；本轮未因该错误停止基础收发。

## 7. 托盘专项结论

- 主流程已增加真实SessionList向托盘分组状态的投影，较上一轮只有示例入口有进展；但尚未在实际系统托盘完成端到端核验。
- 诊断页“弹出托盘未读浮窗”可以执行，实际是在诊断子窗内打开Dialog，显示“暂无新未读消息”：[27](../screenshots/windows-retest-20261018-180516/27-diagnostic-tray-dialog-empty.jpg)。这是该子引擎的状态，**不是当前真实账号完整未读状态，也不是系统托盘实拍**。
- 浮窗实现仍使用showGeneralDialog、相对页面右下角定位；未验证主窗隐藏时是否实际可见、是否锚定托盘所在显示器。
- 自动化工具未暴露任务栏入口，已请求手动打开实际托盘，但本轮未收到可截图的打开状态。
- 未点击加载Mock、模拟入站、一键已读或更新测试角标，避免把示例状态混进真实验证。

以下均保留“未执行/未验收”：真实图标/角标、右键菜单、隐藏主窗后的点击恢复、真实多身份未读分组和会话跳转、失焦关闭、多显示器/DPI以及托盘退出清理。

## 8. 建议修复与回归顺序

1. **先修R-D01关闭生命周期**：固定目标子窗、统一单一关闭路径；采集线程/句柄证据，区分隐藏复用和销毁。没有关闭稳定性，不进入“全面通过”。
2. 修R-D02网页加载及最大化布局；用已知可用网页加真实消息入口双重验收。
3. 修R-D03视频Windows实现；不要只保留兜底错误页。
4. 修R-D04最小化恢复、R-D05工具窗完整控制，人工复核标题栏拖动与系统贴靠。
5. 查R-D06启动首帧白屏、R-D07角标并发文件占用。
6. 补齐托盘实际入口、富消息渲染、历史分页、断线重连及跨DPI回归。

沿用现有WindowService、窗口适配层、Repository和应用级认证/SignalR，不创建第二套会话状态或每子窗独立SignalR；本轮桌面问题不需要修改后端API、数据库结构或生成Migration。

## 9. 交付与最终状态

本轮原图、窗口枚举、源码快照、构建/分析/测试记录和两次异常记录均保存在同一证据目录。ZIP排除3份原始运行日志，保留合并筛除敏感行的运行记录；截图保留真实聊天/设备内容，仅作为本地交付。

结束时已第三次启动客户端，恢复林惠娟身份和浅色主题，主窗最大化且响应正常。没有把重启后的正常状态当作R-D01已修复。

后续修复必须以新的源码快照和实机证据复测；45项自动化通过不能覆盖当前已确认的运行失败。
