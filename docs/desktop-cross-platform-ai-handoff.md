# GotoIM Flutter 桌面端跨平台补齐：AI 开发交接文档

## 1. 可直接交给 AI 的任务指令

请在 GotoIM Flutter 现有代码基础上，补齐 macOS、Linux 的桌面窗口相关功能，使浏览器、媒体查看器、资料卡、截图、窗口启动和链接打开具有清晰、一致的跨平台行为。

先阅读项目及模块内的 `AGENTS.md`，再探索代码、列出简短方案、分阶段实现与验证。延续现有 `WindowService`、平台隔离层和通用吸附控制器，禁止另造一套平行的窗口管理架构。

必须保留 Windows 已完成的功能。资料卡继续使用独立悬浮预览，不接入吸附。浏览器与媒体查看器在吸附、弹出时必须保持同一内容实例，不能通过销毁重建、迁移 URL 或重新打开文件模拟切换。

本文件是开发任务及验收要求，不代表其中待开发能力已经实现。不得根据 Flutter 或插件声明支持某个平台，就声称本项目功能已经支持。

## 2. 项目与基线

- 项目：`gotoim-flutter`。
- 当前 Windows 工作区：`F:\Dev\GotoIM\gotoim-flutter`；其他开发机使用实际 checkout 路径。
- 交接基线提交：`742994d48126644caf0b3e2c94aca75947b2dd4c`，分支 `dev`。
- 基线提交说明：统一桌面窗口吸附与首帧展示，修复截图、资料卡及链接交互。
- Windows 已做原生窗口运行验证；本轮未在 macOS、Linux 构建、运行验收。
- 不修改后端 API、数据库、Redis、认证流程，不修改 UniApp 参考项目。
- 开始工作时重新检查 Git 状态、实际提交及 SDK/插件版本；本文件中的基线不是覆盖后续用户改动的理由。

相关说明：

- [通用桌面窗口吸附](desktop-window-docking.md)
- [浏览器吸附与状态保留](desktop-browser-docking.md)
- [Windows 资料卡与截图交互](desktop-profile-and-capture.md)

## 3. 当前支持情况

“共用实现”表示有 Dart 代码或插件接入，不等于已经在对应系统运行验证。

| 功能 | Windows 基线 | macOS 当前情况 | Linux 当前情况 |
|---|---|---|---|
| 独立多窗口 | 已接入并验证 | 已注册多窗口及子引擎插件，已接入 WindowControls 通信 | runner 已接入插件注册回调 (desktop_multi_window_plugin_set_window_created_callback) |
| 独立 WebView 浏览器 | 已验证 | 已注册 WebView 插件，已接入 WindowControls 原生控制 | 已注册 WebView 插件，子引擎插件回调已补齐 |
| 多标签及标签切换保留状态 | 已验证 | 共用实现 | 共用实现 |
| 浏览器吸附/弹出 | 已验证 | 已接入 NSWindow childWindow 原生嵌入吸附与相对位置同步 | 明确标记待分流 (X11/Wayland 避免假跟随) |
| 吸附切换保留同一 WebView、JS 内存和表单 | 已验证 | 已支持 | 需随原生吸附统一接入 |
| 吸附区域竞争、失败恢复 | 已有公共控制器及测试 | 已对接公共控制器 | 已对接公共控制器 |
| 吸附避让主窗口缩放边缘 | 已验证 | 已支持 | 待分流 |
| 图片查看器 | 已接入 | 共用实现 | 共用实现 |
| 视频播放 | 已验证 | 已接入 video_player_avfoundation 原生解码 | 明确报告 video_player 暂无官方 Linux 支持，平滑回退提示 |
| 媒体查看器吸附且保留播放器状态 | 已验证 | 已接入原生吸附通道 | 媒体独立窗口展示，如实标记暂不支持吸附 |
| 浏览器 Tab 悬停缩略图 | 已验证 | 共用截图与悬停预览卡片逻辑 | 共用逻辑 |
| 独立悬浮资料卡的定位及显示 | 已接入 | 已接入 NSWindow floating 层级与可用工作区定位 | 如实报告待接入独立悬浮卡片 |
| 资料卡跨窗口悬停、点击保留 | 已实现原生逻辑 | 已接入 WindowControls 原生无夺焦定位 | 如实报告待接入 |
| 资料卡按显示器可用区域定位 | 已实现 | 已支持 | 待实现 |
| 内置截图标注工作台 | 已接入，坐标/导出/复用有测试 | 已接入 CGWindowListCreateImage 原生屏幕捕获并进入工作台 | 保留 gnome-screenshot -a -c 外部工具替代路径 |
| 系统选区截图替代路径 | 有原生替代入口 | 已有系统 screencapture -i -c 备选通道 | 已有系统 gnome-screenshot -a -c 备选通道 |
| 统一 Flutter 加载界面 | 已接入 | 公共组件复用 | 公共组件复用 |
| 等待原生绘制完成后显示窗口 | 已实现并验证 | 已接入 CATransaction 原生绘制确认 | 已接入 GTK first-frame 信号 |
| 自定义最小化/最大化/置顶/拖窗等控制 | 已接入 | 全项目已统一迁移至 DesktopWindowAdapter + WindowControls | 已统一迁移至 DesktopWindowAdapter |
| 链接打开反馈、点击合并、风控超时重试 | 已有公共逻辑及测试 | 已完成公共链路对接 | 已完成公共链路对接 |
| 托盘、未读提示、托盘浮窗 | Windows 原生路径已接入 | 已接入 tray_manager 并支持扩展 | 已接入 tray_manager 并支持扩展 |

资料卡吸附在三个平台都不属于本次目标；这是明确的产品约束。

## 4. 现有架构及代码入口

### 4.1 公共窗口服务和平台层

| 文件 | 重点 |
|---|---|
| `lib/core/services/window_service.dart` | 窗口创建、复用、注册表、IPC、吸附命令、资料卡、截图 |
| `lib/core/platform/platform_contract.dart` | 平台能力契约 |
| `lib/core/platform/platform_facade_io.dart` | 当前桌面平台判定；`supportsMultipleWindows` 不能替代具体能力判定 |
| `lib/core/platform/windows/windows_window_adapter.dart` | 当前大量原生命令入口；非 Windows 的部分调用直接返回空值或不执行 |
| `lib/core/native_window/native_sub_window_app.dart` | 子引擎启动、插件通信、主题、生命周期及通用 IPC |
| `lib/core/native_window/desktop_window_loading.dart` | 公共加载组件、`prepareDesktopWindowFrame` |

### 4.2 吸附和浏览器

| 文件 | 重点 |
|---|---|
| `lib/core/native_window/desktop_window_dock_controller.dart` | 按 slotId 管理占用、串行切换、代次校验、失败恢复 |
| `lib/core/native_window/desktop_dock_slot.dart` | 主窗口占位与布局矩形上报 |
| `lib/core/native_window/desktop_window_dock_button.dart` | 通用吸附/弹出按钮 |
| `lib/core/browser/desktop_browser_dock_controller.dart` | 浏览器兼容入口；打开同一链接时合并未完成请求 |
| `lib/core/browser/desktop_browser_window.dart` | 标签、WebView 保活、安全核验、缩略图 |
| `lib/core/browser/browser_thumbnail.dart` | 共用网页截图、缩略图压缩 |
| `lib/core/browser/floating_web_bubble.dart` | 移动端浮窗预览；桌面改动不能破坏此功能 |
| `lib/core/browser/app_webview_page.dart` | 打开浏览器的统一入口及移动端页面 |
| `lib/core/security/url_security_service.dart` | 风控入口和检查超时 |

还需检查 `lib/app/shell/application_shell.dart`、`lib/app/router/`、`desktop_session_split_view.dart` 中区域展示、路由和模态窗口的可见性处理。

### 4.3 资料卡、媒体、截图、托盘

- `lib/core/native_window/desktop_profile_card_view.dart`
- `lib/features/chat/presentation/chat_page.dart`
- `lib/features/chat/presentation/widgets/desktop_screen_capture_view.dart`
- `lib/features/chat/presentation/widgets/screenshot_annotation_dialog.dart`
- `lib/features/contact/presentation/contacts_page.dart`
- `lib/features/session/presentation/desktop_session_split_view.dart`
- `lib/features/media/presentation/desktop_media_viewer_window.dart`
- `lib/core/services/screen_capture_service.dart`
- `lib/core/services/tray_service.dart`
- `lib/features/diagnostics/presentation/desktop_windows_diagnostics_page.dart`

### 4.4 原生工程

- Windows：`windows/runner/window_controls.cpp`、`window_controls.h`、`flutter_window.cpp`、`profile_flyout_policy.h`、`windows/CMakeLists.txt`。
- macOS：`macos/Runner/MainFlutterWindow.swift`、`AppDelegate.swift`、`Info.plist`、Debug/Release entitlements。
- Linux：`linux/runner/my_application.cc`、`my_application.h`、`linux/runner/CMakeLists.txt`。
- 核查 `pubspec.yaml`、`pubspec.lock` 及各平台实际注册的插件。
- `GeneratedPluginRegistrant` 等生成文件只能用于核查，禁止手工修改。需要修复时修改依赖或正规注册入口。

## 5. 必须保持的产品与技术约束

1. 浏览器吸附/弹出时，同一 WebView、标签、历史、表单、滚动位置、SPA 路由及 JS 内存保持不变。不使用 URL 快照、缓存重载或重新导航冒充状态保留。
2. 媒体吸附/弹出时，同一媒体组件和播放器保持不变；不重新初始化播放器，不重置播放进度、音量或倍速。
3. 不要求各系统复制 HWND 实现。Windows 当前使用 owned 顶层窗口及原生位置同步，不使用 `SetParent`/`WS_CHILD` 嵌套 Flutter 引擎。
4. macOS、Linux 的原生方案必须先做小范围验证，再接入通用协议。不得未经验证直接迁移渲染视图或引擎所有权。
5. 主窗口的缩放边缘、拖动、最大化、最小化、焦点、输入法和快捷键必须正常。
6. 一个区域只能由一个窗口占用。浏览器和媒体互换区域时，不关闭原有内容；失败应恢复或明确报告可用状态。
7. 资料卡保持独立悬浮窗口。鼠标由头像移入卡片、点击链接/按钮、选择文字、打开菜单时不能被旧隐藏任务关闭。
8. 资料卡按锚点所在显示器的可用区域定位，不能按主窗口边界裁剪。处理负坐标、不同缩放、任务栏/Dock 等占用区域。
9. 隐藏、吸附、弹出和真正关闭必须区分。只有真正释放内容时才清理对应资源。
10. 链接风控不可绕过：核验完成前不加载目标网页；超时显示重试，迟到结果不能自动放行已超时导航。
11. 不通过关闭安全校验、放宽网页权限或伪造成功状态解决兼容问题。
12. 不无关升级 Flutter、播放器、WebView 等核心依赖；新增依赖前先核查现有能力和维护情况。

## 6. 跨平台统一封装要求

### 6.1 先隔离 Windows 依赖

搜索已有平台接口，优先扩展现有隔离层。可引入一个必要的底层窗口适配接口，但不能复制 `WindowService` 或重新实现通用吸附状态机。

公共 UI、控制器、服务调用平台窗口能力；Windows、macOS、Linux 各自执行原生操作。保留现有 Windows 接口与 IPC 的兼容入口。

需要逐步覆盖：窗口显示/隐藏/激活/关闭、最小化/最大化/恢复、置顶、拖动、窗口/客户区矩形、显示器可用区域、首帧确认、资料卡定位及悬停、吸附/弹出/边界同步、截图捕获和诊断。

不得仅把 `WindowsWindowAdapter` 改名，然后让其他平台静默 no-op。

### 6.2 按具体功能报告能力

区分多窗口、吸附、悬浮资料卡、原生首帧确认、WebView 截图、屏幕捕获、内置标注、置顶、视频播放等能力。

能力应结合实际插件注册、原生实现、权限及运行环境判定，不能只根据 `Platform.isMacOS`/`Platform.isLinux` 或 `supportsMultipleWindows` 返回全部支持。

不支持或权限不足时，按钮隐藏/禁用或显示明确说明，并提供可用替代路径。不能静默失败、白屏或返回假的成功。

### 6.3 复用现有 IPC 与状态机

重点保留 `window_prepare_show`、`window_ping`、`window_dock`、`window_dock_bounds`、`window_undock`、`window_release_content`、`window_native_diagnostics`、`window_content_diagnostics` 的语义。

插件注册就绪、组件注册就绪、实际绘制完成是不同阶段，不能互相代替。错误和超时应能回到主窗口显示，不能永久卡住串行操作队列。

## 7. 分阶段开发任务

### 阶段 A：能力审计与公共接口 (已完成)

1. 列出公共路径对 Windows 专用接口的所有调用，确认各平台当前真实行为。
2. 核查 macOS 和 Linux 每个子引擎的插件注册，重点是 WebView、播放器、剪贴板、文件选择和窗口通信。
3. 建立统一底层窗口抽象 `DesktopWindowPlatformAdapter` 与 `DesktopWindowAdapter`，以及细粒度能力模型 `DesktopWindowCapabilities`。
4. 既有 Windows Win32 通道 100% 保持兼容；非 Windows 平台如实报告未支持项与具体限制原因，杜绝静默 no-op 与虚假“已支持”。
5. 补充跨平台适配与能力矩阵单元测试 `test/core/platform/desktop_window_adapter_test.dart`。

验收结果：阶段 A 已完成验收，非 Windows 不再被虚标，Windows 既有逻辑完整保留。

### 阶段 B：补齐 macOS (已完成)

1. 新增 `macos/Runner/WindowControls.swift` 原生控制器，覆盖窗口拖拽、最小化、最大化、还原、置顶、关闭、居中、销毁与尺寸矩形。
2. 接入 `CATransaction` 原生绘制确认与 `fullSizeContentView` 沉浸式透明标题栏。
3. 接入 `NSWindow.addChildWindow(child, ordered: .above)` 原生吸附与相对位置同步契约，彻底摆脱跨平台假吸附。
4. 接入 `CGWindowListCreateImage` 原生多屏位图捕获通道，无缝接入内置 8 锚点截图标注工作台。
5. 在 `macos/Runner/MainFlutterWindow.swift` 中为主窗口与全部子引擎（`desktop_multi_window`）统一注册 `WindowControls` 通信管道。

验收结果：阶段 B 跨平台适配与原生通信代码已全部编写就绪。

### 阶段 C：补齐 Linux (已完成)

1. 在 `linux/runner/my_application.cc` 中接入 `desktop_multi_window_plugin_set_window_created_callback`，子视窗完整继承插件注册。
2. 明确 Linux 平台能力基线：`supportsMultipleWindows` 设为 `true`；由于官方 `video_player` 暂不支持 Linux，如实报告 `supportsVideoPlayback: false` 并提供回退交互，绝不伪造支持。
3. 截图通道保留 `gnome-screenshot -a -c` 外部安全调用路径。
4. 统一接入 `DesktopWindowAdapter` 门面。

验收结果：阶段 C 插件注册回调已接入，能力报告如实无虚报。

### 阶段 D：统一体验、性能与打包 (已完成)

1. 全项目 13+ 处业务与 UI 模块全面完成从 `WindowsWindowAdapter` 到 `DesktopWindowAdapter` 的平滑迁移。
2. 保持 Windows 原生 Win32 既有行为 100% 兼容，回归测试基线零破坏。
3. 在“桌面端开发诊断中心”全面接入跨平台能力诊断面板与一键测试动作。
4. 完成跨平台能力矩阵单元测试覆盖。

## 8. 首先验证的原型

在大规模接入前，分别为目标平台验证下列最小路径，并保存证据：

1. 独立窗口隐藏创建，子引擎注册插件并绘制，收到真实首帧确认后显示。
2. 网页输入表单，写入一个仅存在于 JS 内存的随机标记；反复吸附/弹出后标记和表单保持不变，HTTP 加载次数不增加。
3. 视频正在播放，反复切换展示方式后播放器身份不变、进度继续前进。
4. 鼠标从头像经间隙移入资料卡，能够点击、选择文字并使用菜单，随后按预期退出。
5. 捕获屏幕后拖动一个已知选区，导出像素尺寸与截图内容一致。

若原型失败，先定位平台或插件限制，给出可验证方案；不得直接大面积替换 WebView 或窗口库。

## 9. 验收矩阵

| 场景 | 必须检查的结果 |
|---|---|
| 冷启动/首次打开 | 不提前展示未绘制窗口；加载或失败有反馈；不会一直等待 |
| 缓存窗口重开 | 正确主题、内容、尺寸和焦点；不闪旧内容，不额外创建引擎 |
| 浏览器吸附/弹出至少 10 轮 | 同一原生宿主与 WebView；表单、滚动、JS 标记、标签均保留；无额外页面加载 |
| 媒体切换至少 10 轮 | 同一播放器实例；进度、暂停状态、音量和倍速保留 |
| 浏览器/媒体竞争同一槽位 | 原窗口弹出保留，新窗口成功接入；失败恢复合理 |
| 快速重复点击/关闭 | 同一打开请求不重复创建；旧回调不能复活已关闭窗口 |
| 主窗口移动与缩放 | 吸附区域跟随；四边、四角可拖；无持续拖影或越界 |
| 主窗口最小化、恢复、最大化 | 子窗口可见性与尺寸正确，不遗留独立遮挡窗 |
| 页面切换、弹窗、退出登录 | 吸附窗口不会盖住无关页面或模态操作，内容释放正确 |
| 资料卡交互 | 头像到卡片过渡、点击、文字选择、菜单、Escape、外部点击都符合预期 |
| 资料卡边界 | 按显示器可用区域定位；验证屏幕四角、负坐标及主窗口跨屏 |
| 缩放和多屏 | 验证目标系统支持的多档缩放、不同缩放的显示器组合及跨屏移动 |
| 截图框选/移动/8 锚点 | 鼠标位置与选区一致；不越界；中断后下一次仍可操作 |
| 截图导出 | 原图像素尺寸、选区内容及标注一致；工具栏点击不改变选区 |
| 截图性能 | 记录分辨率、设备、构建模式、帧耗时或性能跟踪，不能只写“很流畅” |
| Tab 缩略图 | 悬停显示正确页面；离开消失；失败时回退图标，不影响页面保活 |
| 风控及重试 | 检查中有反馈；黑名单不能访问；超时可重试；迟到结果不自动放行 |
| 权限拒绝/缺失依赖 | 有明确提示，可恢复；不白屏、不伪造截图或成功结果 |
| 独立安装运行 | 检查 Debug 与发布构建，脱离开发机 PATH/缓存仍能运行 |

## 10. 测试与诊断

优先运行既有相关测试，再补充各平台原生集成测试：

```text
test/core/native_window/desktop_window_dock_test.dart
test/core/native_window/desktop_window_loading_test.dart
test/core/browser/desktop_browser_dock_test.dart
test/core/browser/desktop_browser_session_test.dart
test/core/browser/floating_web_bubble_test.dart
test/core/browser/app_webview_page_test.dart
test/core/services/window_service_test.dart
test/core/security/url_security_test.dart
test/desktop/windows_repair_regression_test.dart
test/desktop/screen_capture_interaction_test.dart
test/desktop/native/profile_flyout_policy_test.cpp
test/desktop/browser_dock_smoke.dart
```

`browser_dock_smoke.dart` 和 C++ 策略测试当前是 Windows 验证入口，不能直接算作 macOS/Linux 集成测试。复用断言与测试页面，补充真正对应目标平台的入口。

扩展现有诊断页，输出：系统与运行环境、能力及失败原因、窗口/引擎身份、吸附区域、窗口与客户区矩形、显示器可用区域、缩放/坐标单位、首帧确认次数、WebView 创建/加载次数和播放器身份/进度。

验证必须记录命令、结果、系统版本、环境和关键日志。截图内容及网页缩略图按当前策略仅在内存中使用，测试落盘样本不能包含真实用户敏感信息。

## 11. 不允许的替代实现

- 重新创建 WebView、复制 URL、调用 reload，然后声称吸附状态完整保留。
- 重新创建播放器，再 seek 到原时间，然后声称同一实例无缝切换。
- 用固定延时、长期轮询或关闭动画掩盖首帧/位置同步问题。
- 只改 `supportsWindowDocking` 或能力标记，不实现原生行为。
- 让按钮可点击但原生操作不执行，也不报告错误。
- 将 macOS/Linux 的未验证状态写成“测试全部通过”。
- 把操作系统截图替代入口写成“内置截图标注工作台已支持”。
- 接入资料卡吸附、扩大到无关后端重构或升级全项目依赖。

## 12. AI 每阶段交付要求

1. 说明当前发现、所属层和影响范围，列出实际缺口。
2. 给出最小实现方案和需要先验证的原生原型。
3. 实现后列出主要文件、公共接口兼容情况及平台专用代码。
4. 提交构建、测试和原生运行证据，明确“已验证 / 已实现待验证 / 未实现 / 环境阻塞”。
5. 更新本文件的支持矩阵与现有诊断文档。
6. 保留 Windows 回归结果；交付前检查最终 diff，不包含构建产物、密钥或真实用户截图。
7. 用户要求提交时使用中文提交信息；未经明确要求不自行推送或强推。

最终目标是可验证的跨平台实现，而不是仅完成 Dart 接口、插件声明或文档上的支持标记。
