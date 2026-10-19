# GotoIM Flutter Windows 修复与实机验证

日期：2026-10-18 至 2026-10-19（Asia/Shanghai）。项目：`F:\Dev\GotoIM\gotoim-flutter`。

本轮已修复并验证上一轮主要可复现窗口故障：自定义工具标题栏、冷启动白屏、最小化恢复、网页加载与宽屏布局、视频 Windows 后端、子窗关闭、托盘角标和主窗恢复。**仍未完成整个桌面产品的全部验收矩阵，不能据此声称达到微信的全部功能和资源占用水平。**

## 物理路径与证据

- 本文：`F:\Dev\GotoIM\gotoim-flutter\docs\WINDOWS-DESKTOP-FIX-VALIDATION-20261019.md`
- [截图画廊](../screenshots/windows-fix-validation-20261018/index.html)：`F:\Dev\GotoIM\gotoim-flutter\screenshots\windows-fix-validation-20261018\index.html`
- [截图清单](../screenshots/windows-fix-validation-20261018/captures.json)、[验证记录](../screenshots/windows-fix-validation-20261018/validation.json)、[源码哈希](../screenshots/windows-fix-validation-20261018/source-hashes.json)。
- 证据包：`F:\Dev\GotoIM\gotoim-flutter\screenshots\windows-fix-validation-20261018-evidence.zip`。仅包含报告、截图、哈希、ICO文件及筛除敏感行的验证日志，不打包原始运行日志或登录凭据。

共51张原始实机JPEG，含排查失败及过渡画面。01–36来自排查和中间构建，37–51来自最终构建；不能把全部51张都解释为最终版本通过。组件测试输出的模拟托盘/构造账号截图未计入实机证据。

## 环境和账号

Windows x64 Debug，Flutter 3.47.0，默认 Impeller。实际测试对象为 HEAD 加未提交工作区，466个源码文件记录SHA256并在结束时复核。原有用户修改保留，未提交或回滚其他改动。

复用真实登录态186****9806，当前身份林惠娟（ownerId13），查看同账号私人助理机器人及真实网址消息。未重新验证密码登录。本轮未新增发送、删除或撤回消息，上一轮4/5/6作为真实现有历史保留。未启动文件共享服务、修改权限、清缓存或注入未读Mock数据。

播放器使用Flutter官方公开bee.mp4，区分“直接网络播放”和“下载后本地播放”；它不是实际聊天视频附件。系统托盘菜单通过诊断入口调起同一套Windows原生菜单，未直接点击通知区图标；不伪称已取得系统通知区图标截图。

## 缺陷修复对照

| 缺陷 | 实现及实测 | 证据与边界 |
|---|---|---|
| R-D01 媒体/网页关闭影响主进程 | 每引擎绑定本窗口，取消前台HWND猜测和同步FFI关闭；关闭只走一条登记/隐藏路径，释放媒体内容 | 视频加载中关闭24，本地实播后关闭34，网页标签关闭26，最终网页/网络视频关闭44/48均保持其他窗口响应。未做各20轮压力验收 |
| R-D02 网页取消错误、黑屏及最大化不铺满 | 去除多余导航拦截，忽略取消/子资源错误，WebView铺满；修改Flexible标签分配，按钮靠右 | 真实消息中的内网CMS正常29，最终2560宽屏完整页面及右侧控制43 |
| R-D03 Windows视频未实现 | 接入video_player_win 3.3.1及生成注册；初始化20秒超时，错误页支持下载后本窗口播放；按钮监听真实播放器状态 | 本地缓存实播31，最终直接网络初始化/实播45/46，停止状态47，关闭48。音频输出、拖动进度未测；最终未强制构造网络超时回退场景 |
| R-D04 最小化无法业务恢复 | restore区分最小化和普通显示，业务入口恢复同一子窗 | 21为主窗入口恢复同一HWND，未调用自动化工具激活子窗充当业务恢复 |
| R-D05 工具窗缺少自定义控制 | 设置、诊断和文件工具复用标题栏，路由外壳补Overlay，修正悬浮提示异常 | 设置正常/最大化17/18，诊断22，最终文件工具49及关闭50；文件服务器未开启 |
| R-D06 冷启动持续白屏 | 创建时确定窗口样式，显示首帧后回平台消息循环投递重绘，保持主/子引擎一致线程策略 | 修改后多次冷启动13–16、19、30、36和最终51均未靠人工调整尺寸恢复；未清理GPU缓存或作概率保证 |
| R-D07 角标文件占用/更新挂起 | 更新排队及过期合并，PID独立不可变文件；修正生成Future清理回调自身等待；Windows使用平台线程Shell_NotifyIcon和ICO | 最终角标更新143ms返回成功37，实际ICO正常/闪烁文件可核对；未再观察errno32。并发生成专项通过 |
| 托盘数据与主窗口生命周期 | 主引擎唯一托盘，子窗IPC代理；真实快照原生浮窗，失焦隐藏；关闭主窗保留进程 | 真实27条未读浮窗27，Windows原生菜单38/39；主窗隐藏41，从同一菜单恢复原HWND42。通知区图标直接点击、显式退出未测 |
| 聊天富消息和首载滚动 | 保留完整类型/原始内容/身份/游标，复用现有渲染器；删除双层气泡，反向列表锚定最新消息；每页30条游标历史 | 首载最新6及单层气泡20，业务恢复21；所有富消息类型、翻完历史、最终版新消息互发未重新覆盖 |
| 桌面距离传感器异常 | 非Android/iOS不订阅移动端距离传感器 | 代码及静态分析通过；未把移动端传感器记为Windows支持 |

## 关键实现与影响范围

1. `windows/runner/window_controls.h/.cpp`注册每引擎的`gotoim/window`平台通道。命令在平台线程操作该引擎视图的根窗口；不再以GetForegroundWindow选择目标，不再从Dart同步SendMessage关闭。主窗关闭到托盘，子窗隐藏缓存，淘汰或退出登录时销毁。
2. `flutter_window.cpp`在Show之后投递重绘消息，`main.cpp`与desktop_multi_window保持相同独立UI线程策略。没有永久切换Skia，没有修改Pub缓存中的插件代码。
3. `DesktopToolWindowFrame`以Overlay.wrap包住工具路由与标题栏，修复“RawTooltip需要Overlay”运行错误。网页、媒体回调与原生关闭分支互斥。
4. `WindowService`继续负责子窗去重、最小化恢复、主引擎消息/历史/附件/语音代理。子引擎轻量启动，不重复创建完整bootstrap、设备注册、SignalR或数据库初始化。媒体跨引擎负载保留用户、会话、日期和文件名，延续已有缓存隔离路径。
5. `TrayService`在Windows经平台通道操作系统托盘和原生菜单，其他平台保留原实现。生成32px ICO内嵌PNG，图标切换后释放旧HICON。子窗向主引擎发命令，主托盘实例单向注册回调，避免Provider循环依赖。初始化前到达的未读数保留，联网检查更新不再阻塞托盘初始化，原隐私检查顺序保留。
6. `TrayBadgeGenerator`按数字/闪烁状态合并并发任务。清理回调只删除pending记录，不返回同一Future；文件名含PID且同一图标不重复覆写。相应回归会实际生成文件、校验ICO头及并发完成，测试目录真实IO位于runAsync中。
7. 视频复用现有`MediaDownloader`和缓存；控制器异步回调校验实例身份，失败或超时可重试/下载后播放，关闭卸载媒体/WebView内容。

修改属于Flutter客户端平台层、窗口视图及现有Service适配，不涉及ABP业务模块、服务器API、数据库、Redis、后台任务或Migration。没有降低认证校验。

## 验证

工作目录均为`F:\Dev\GotoIM\gotoim-flutter`，Flutter路径为`E:\sdk\flutter-3.47.0-active\bin\flutter.bat`。

- `flutter build windows --debug --no-pub`：最终构建成功，153.4秒；已有WebView CMake CMP0175警告保留。[日志](../screenshots/windows-fix-validation-20261018/verified-logs/build-final-verified.log)。
- `flutter analyze --no-pub <受影响文件>`：完整19目标分析及最后4目标补查均No issues found。[完整分析](../screenshots/windows-fix-validation-20261018/verified-logs/analyze-complete-delivery.log)、[最终补查](../screenshots/windows-fix-validation-20261018/verified-logs/analyze-final-verified.log)。
- 相关9个测试文件一轮52项通过；新增并发角标完成与ICO生成后，专项8项通过。[52项](../screenshots/windows-fix-validation-20261018/verified-logs/tests-native-tray.log)、[8项专项](../screenshots/windows-fix-validation-20261018/verified-logs/tests-badge-verified.log)。最终相同9个文件完整复跑 **53项全部通过、0失败**。[最终53项日志](../screenshots/windows-fix-validation-20261018/verified-logs/tests-final-complete.log)。
- `git diff --check`：退出码0，仅已有行尾提示。
- 最终源码哈希复核：466个文件无变化。保留可执行文件和kernel_blob.bin的SHA256。

测试文件：`windows_repair_regression_test.dart`、`window_service_test.dart`、`window_messenger_test.dart`、`storage_path_service_test.dart`、`attachment_cache_classified_test.dart`、`desktop_clipboard_paste_test.dart`、`desktop_tray_grouping_test.dart`、`desktop_comprehensive_suite_test.dart`、`desktop_real_account_suite_test.dart`。后两者包含构造数据与组件截图，不能代替真实客户端测试。

## 修改文件

主要文件：Windows runner的window_controls、flutter_window、main、win32_window、CMakeLists；WindowsWindowAdapter；native_sub_window_app、desktop_window_title_bar、desktop_sub_window_chat_view、native_window_payload；window_service及tray_service/生成器/未读模型；浏览器、媒体、设置和桌面诊断页面；bootstrap、ApplicationShell、DesktopStartupScene、传感器、ChatMessage窗口负载；pubspec及自动生成插件注册；新增Windows修复回归测试。

## 剩余风险与未覆盖项

- 仅当前Windows Debug机器实测；未测Release、macOS/Linux、多显示器跨DPI、重连压力和各类窗口20轮关闭。
- 隐藏复用最多缓存10个子引擎。累计打开聊天/网页/视频/工具后一次Debug工作集约2.0GiB，清理后仅主窗约511MiB。这不是稳定基线，也不足以认定泄漏；仍需Release及长时资源回收验证，不能称达到微信资源水平。
- 独立UI线程策略有Flutter未来移除的警告。直接取消曾导致创建子窗异常退出，升级Flutter/多窗口插件前需重新验证，不能直接移除现有策略。
- 运行捕获过Flutter辅助功能AXTree更新错误；主要截图和坐标操作正常。编辑框自动化输入及完整键盘可访问性未完成验收。
- 网络视频最终实播通过，但未覆盖所有编码格式、私有鉴权视频、音频输出和拖动进度，也未强制验证超时后下载回退的整条实机路径。
- 通知区图标本身没有系统区域截图。已提供真实原生菜单、真实未读浮窗和实际生成ICO文件；没有用模拟菜单图片冒充系统托盘。

交付时已重启本轮测试进程清理子引擎并恢复真实27条未读，仅主窗口保持运行；未修改真实未读数据或退出登录。
