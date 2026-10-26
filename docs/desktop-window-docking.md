# 桌面窗口吸附

当前接入 Windows 浏览器和媒体查看器。资料卡保留原来的悬停预览行为，暂不接入。
其他平台和未接入的窗口类型明确返回 unsupported。

## 接入和职责

沿用 `WindowService` 打开内容，再改变窗口展示方式：

```dart
await windowService.openMediaViewer(mediaUrl: source, items: items);
await windowService.dock(targetId: 'tool:media', slotId: 'chat:right');
await windowService.undock(targetId: 'tool:media');
```

主窗口为区域布局尺寸，并放置占位组件：

```dart
SizedBox(
  width: paneWidth,
  child: const DesktopDockSlot(slotId: DesktopWindowDockNotifier.chatRight),
)
```

- `DesktopDockSlot` 上报物理像素坐标、DPI 和区域可见性。
- `desktopWindowDockProvider` 按 slotId 保存 targetId、尺寸、切换状态、错误。
- `WindowService` 根据 targetId 找到现有窗口，握手后转发原生命令。
- `NativeSubWindowApp` 统一处理 `window_ping`、`window_dock`、`window_dock_bounds`、
  `window_undock`、`window_native_diagnostics` 和 `window_content_diagnostics`。
- Windows Runner 只修改现有 HWND 的样式、Owner 和位置；不执行 SetParent、挖洞或重建引擎。
- 浏览器兼容入口只负责打开内容，随后委托通用控制器；通用状态不保存 URL 或媒体数据。

当前宿主为主窗口。其他 slotId 需要由宿主提供布局并通过
`onWindowDockLayoutRequested(slotId)` 激活；未注册区域会失败，不会使用过期矩形。

## 生命周期与区域竞争

每个区域最多一个窗口，同一窗口不能同时占用两个区域。新窗口吸附到已占用区域时，
原窗口先弹出保留内容；新窗口失败时尝试恢复原占用者，恢复失败则清空区域并记录错误。
切换请求串行执行，关闭事件带代次校验，防止迟到的异步回调复活窗口。

吸附、弹出、隐藏不调用 `update_payload`、清空标签或卸载媒体组件。
真正关闭时先解除吸附，再释放相应内容；隐藏整个主窗口或区域只隐藏 HWND。
媒体窗口保持原有播放/暂停策略，吸附本身不启动或重置播放。

新增窗口接入时，应复用通用按钮/协议，保留 Widget Key 和内容控制器，处理吸附时的
标题栏、置顶、拖拽与最大化行为，再加入 `ensureDockWindowReady` 的支持类型列表。
模态窗口、托盘和截图工具不能直接按普通工具窗口处理。

## 主窗口边缘

Owned Window 会优先接收其覆盖区域的鼠标输入，因此原生定位时将目标矩形裁到主窗口
客户区的安全范围内，四边和四角均保留缩放边缘。保留宽度取 DPI 缩放值与系统边框指标
的较大者；主窗口最大化时不保留缩放边缘。

诊断输出提供窗口矩形、主窗口客户区矩形和四边 `WM_NCHITTEST` 返回值。
正常可缩放窗口预期为 `[10, 11, 12, 15]`，即左、右、上、下。

## 网页缩略图

`captureBrowserThumbnail` 为桌面标签和移动端网页浮窗共享截图与压缩逻辑，图片只放内存。
桌面在加载完成、切换标签和悬停时保存/更新预览；后台标签优先使用已保存图片。
移动端缩为浮窗前截图，浮窗支持预览按钮、长按以及外接鼠标悬停。
预览通过 OverlayPortal 显示，适配浮窗独立 Overlay，不依赖其上方有 Navigator。
平台截图失败时回退图标，恢复/关闭和拖拽保持可用。

## 验证入口

开发诊断中心 → 桌面窗口：选择浏览器或媒体查看器，打开后执行吸附、弹出、实例与边缘检查。

自动化测试：

```powershell
flutter test --no-pub test/core/native_window/desktop_window_dock_test.dart test/core/browser/desktop_browser_dock_test.dart test/core/browser/desktop_browser_session_test.dart test/core/browser/floating_web_bubble_test.dart test/core/browser/app_webview_page_test.dart test/core/floating_window/floating_window_manager_test.dart test/core/services/window_service_test.dart test/core/security/url_security_test.dart test/desktop/windows_repair_regression_test.dart
```

原生冒烟入口沿用 `test/desktop/browser_dock_smoke.dart`，必须在独立构建副本运行。
可传 `--video=<本地 MP4 路径>` 验证真实播放器身份和播放进度；不传则测试本地图片。
它检查浏览器 HTTP 次数/JS 标记、媒体组件身份、区域竞争及四边缩放命中。
原生验证需要可渲染的测试窗口，入口会显示独立测试副本；隐藏窗口可能不产生布局帧。
就绪握手以组件完成注册为准，不等待隐藏窗口的下一帧。测试退出阶段有超时兜底，
报告中的 `cleanupNote` 会记录未收到原生清理回复的情况，最终由测试进程退出释放引擎。
实际移动端截图、跨屏 DPI、输入法和全屏视频仍需要设备交互验收。

2026-10-24 验证：51 项相关自动化测试通过，静态分析无问题。
真实 Windows 测试中，浏览器往返 4 轮、与媒体切换占用同一区域后，两个页面仍各加载
1 次；媒体往返 2 轮后组件/播放器实例不变，播放进度持续前进。
144 DPI 下四边保留 12 物理像素，四边命中结果为 `[10, 11, 12, 15]`。
# 统一首帧与加载状态

`DesktopWindowLoading` 提供窗口加载、吸附等待、安全核验和截图准备的统一外观。`prepareDesktopWindowFrame` 主动调度隐藏引擎的 warm-up frame，再通过原生 `prepareFrame` 等待 `SetNextFrameCallback` 确认绘制完成；不能只等待隐藏窗口下一次常规 vsync。

`WindowService` 创建窗口时保持 `hiddenAtLaunch`，收到子窗口 `window_prepare_show` 确认后才显示；缓存窗口、吸附、资料卡定位、托盘和截图唤醒复用同一首帧门槛。失败时保持隐藏、保留引擎供重试，不用固定延时掩盖白屏。原生诊断的 `preparedFrameCount` 用于验证显示前确实执行了准备流程。

## 2026-10-26：拖动与可见弹出回归修复

Windows 自绘标题栏保留 WS_SYSMENU 等系统命令样式，只移除 WS_CAPTION；拖动经专用 WM_APP 消息在 MethodChannel 回复后，确认左键仍按下、读取当前屏幕物理坐标，再直接通过 DefWindowProc 的 WM_NCLBUTTONDOWN/HTCAPTION 进入原生标题栏拖动，避免普通鼠标消息再次经过 Flutter/plugin 分发。

脱离吸附先从原生吸附注册表移除 HWND，再恢复样式、owner 和 WINDOWPLACEMENT，防止同步消息重入时按旧槽位重新定位。失败回滚会重新登记原快照。恢复后显式同步 Flutter 子视图客户区尺寸，调用 ForceRedraw，并使子窗口内容失效重绘；不销毁 WebView，也不重新导航。

原生冒烟测试改为 showWindow:true 的实际可见弹出，检查 HWND、JS 标记和 Tab 实例连续性。原有隐藏弹出验证无法覆盖本次显示回归。

本轮验证：`flutter build windows --debug --no-pub` 完整构建成功；吸附控制器、浏览器吸附及 Windows 交互回归共 24 项全部通过；原生冒烟入口静态分析通过，`git diff --check` 通过。独立原生测试副本启动后停留在首次显示握手（进度到 runApp called），未完成可视化及鼠标拖动验收，已结束该测试进程；不能把本轮单元测试当作画面验收。使用新程序时需要完整退出并重启，热重载不能加载修改后的 C++。


### 独立窗口拖动锚点修正

不再使用排队前的鼠标坐标，也不直接发送 SC_MOVE。原生执行点重新读取当前物理坐标并建立鼠标捕获，移动事件合并执行并保留鼠标抓取位置；左键已经松开则丢弃过期请求；移动循环期间拒绝嵌套请求。ReleaseCapture 只在真正开始移动前执行，避免提前取消 Flutter 手势。此修复共用于主窗口及浏览器、媒体等独立工具窗口，不修改吸附、WebView 实例或页面状态。

人工验收：分离后分别从标题栏不同位置快速/缓慢拖动，鼠标与抓取点保持相对位置；快速拖动后立即松手，窗口立即停止；拖动最大化窗口还原；跨显示器不同 DPI、负坐标屏幕复测。需完整重启原生程序。

验证：本轮 C++ 编译及独立输出目录的原生链接均成功，`git diff --check` 通过。默认 Debug exe 因当前应用运行而无法覆盖，未结束用户进程；另将修复版放在同一运行目录的 `gotoim_flutter-drag-fix.exe`，可在完整退出旧程序后运行。尚未完成真实鼠标拖动和跨 DPI 界面验收。


## 启动页、浏览器首页与非阻塞拖动

后续修复改为非阻塞的 Win32 鼠标捕获，替代前述系统模态移动循环。只在开始拖动时经过一次 Dart 通道；鼠标移动由原生处理，通过一个待处理消息合并高频事件，读取最新物理坐标，跳过未改变的位置。左键释放使用该事件的准确坐标；捕获丢失、取消、Esc 时结束拖动；跨 DPI 更新后重设锚点。吸附窗口也跳过相同矩形的重复 SetWindowPos，避免无效布局与提交。诊断返回 nativeDragActive/nativeDragUpdatePending，沿用现有窗口诊断入口。

Windows 系统“拖到屏幕边缘自动贴靠/摇动窗口”等依赖系统移动循环的交互不会由普通坐标移动自动触发，本轮没有模拟这些行为；跨屏 DPI 和实际高刷新率鼠标仍需真机验收。普通最大化/还原、边缘调整尺寸仍由原来的原生逻辑负责。

启动流程现在先绘制原生不透明品牌画面，再在 Flutter 首帧到达后移除原生覆盖层。Flutter 启动页显示真实的设备信息、本地消息等初始化阶段；通知初始化和数据库准备并行，统计初始化移到主应用挂载后，不阻塞首页。鉴权检查页在桌面上使用同一套界面与可拖动标题栏，关闭重复动画和按定时器伪造的加载阶段，保留诊断/登录入口。没有修改鉴权校验或后端协议。

浏览器新标签页使用本地 Flutter 搜索/网址入口，不创建 WebView、不请求远程首页，也不绕过外链安全核验。输入网址或搜索后仍走原来的 addTab 和安全检查。远程页面首次打开时展示加载反馈，网页提交首个可见画面后撤下；旧页面切换与吸附仍保留实例。进度变化小于 5% 时不反复重建整个浏览器窗口。

相关测试新增于 test/desktop/startup_browser_home_test.dart，并在原生页面模拟器中补齐提交首帧的真实生命周期事件。测试覆盖启动阶段文案、桌面鉴权窗口控制、本地首页免 WebView、网址/搜索提交、首次绘制反馈和页面实例连续性。


本轮验证：37 项相关测试全部通过；Dart 入口与 Windows 资源 bundle 编译成功；受影响 C++ 源码和独立输出目录的原生链接成功。完整预览目录位于 build/startup-browser-preview（包含匹配的原生程序和新 Flutter 界面资源，不复制用户 WebView 缓存）。默认 Debug 目录的旧程序及此前仅替换 exe 的拖动修复版不包含本轮全部界面资源，请完整退出旧程序后运行新的预览目录。真实拖动帧率、冷启动耗时和混合 DPI 未作本轮实机计时，不宣称“零卡顿”或启动时长指标。
