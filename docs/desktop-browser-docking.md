# Windows 浏览器吸附与保活

浏览器已接入通用窗口吸附封装，接口、区域竞争、媒体接入与边缘处理见
[桌面窗口吸附](desktop-window-docking.md)。资料卡暂不接入。

浏览器始终由同一个 `desktop_multi_window` 原生窗口、Flutter Engine 和标签列表承载。
聊天右侧只提供占位矩形。吸附时，Windows Runner 把浏览器改为主窗口的无边框 owned window；
弹出时恢复原来的样式、owner、位置和最大化状态。整个过程不导航、不清空标签、不卸载 WebView。

不使用 `SetParent`、`WS_CHILD` 或主 Flutter View 挖洞。Dart UI isolate 的线程策略不能用于判断
HWND 所属线程；原生层检查真实平台线程，诊断界面也返回这些线程 ID。

## 生命周期

- `requestDock(url: ...)`：打开/激活标签，并吸附现有宿主。
- `requestDock()`：仅吸附现有宿主，不传递 URL 快照。
- `requestUndock()`：仅改变宿主窗口展示方式，保留所有标签。
- 关闭窗口/最后一个标签：清空本次浏览器会话；再次打开只创建新标签。
- 切换请求串行执行。目标操作成功后提交状态；失败恢复原展示状态。
- 主窗口移动由 Runner 同步位置；布局、分隔条和 DPI 变化重新上报占位矩形。
- 窗口不足以容纳三栏时，已有浏览器弹出保留实例；首次吸附显示窗口过窄的错误。
- 主窗口隐藏、最小化、切换主栏目或被其他路由/弹窗覆盖时，隐藏吸附窗口而不释放网页。

窗口模式和尺寸命令不允许调用 `closeWindow` 或 `update_payload`。这两者用于结束/重开会话，
不能用于展示模式切换。`browser_ping` 是宿主就绪握手，不用网页加载完成事件代替插件就绪。

## 标签与风控

标签内容使用直接带稳定 Key 的 `Stack` / `Offstage`，避免删除前面的标签重建后面的网页。
选中项按标签身份保持，异步截图不允许覆盖后来发生的标签选择。

首次打开和页面内顶层导航都先校验 URL。未知新域名需用户确认，Blocked 导航取消；
每个标签的导航序号阻止过期检查结果影响新页面。拦截页隐藏原 WebView，不销毁它。
举报/申诉只有后端请求成功才显示提交成功，当前没有离线待提交队列。

## 验证

```powershell
flutter test --no-pub test/core/browser/desktop_browser_dock_test.dart test/core/browser/desktop_browser_session_test.dart test/core/security/url_security_test.dart test/core/services/window_service_test.dart test/desktop/windows_repair_regression_test.dart
```

开发诊断中心的桌面窗口页提供“读取保活标记、实例次数和窗口线程”。
在切换前后读取，比较 windowId、HWND、标签 ID、WebView 创建次数和网页内存标记。
探针只使用专用 JS 内存标记，不读取网页表单或认证信息。

`test/desktop/browser_dock_smoke.dart` 是独立的原生冒烟入口，不启动登录、消息同步或数据库。
它使用本机 HTTP 服务打开两个真实 WebView，反复吸附/脱离并检查 HTTP 加载次数、
HWND、标签身份、实例创建次数和 JS 内存标记，结果写入 `--result=` 指定的 JSON 文件。
运行时必须使用独立构建和资产目录，不能替换正在运行的开发实例资产。

```powershell
flutter assemble '--output=build/browser-smoke-assets' '--define=TargetFile=test/desktop/browser_dock_smoke.dart' '--define=TargetPlatform=windows-x64' '--define=BuildMode=debug' '--define=TrackWidgetCreation=true' debug_bundle_windows-x64_assets
```

将独立 Windows 构建复制到另一个测试目录，再把上面生成的 `flutter_assets` 放入测试目录的
`data/flutter_assets`，以 `--result=<绝对文件路径>` 启动该测试副本。

当前原生吸附实现仅适用于 Windows。其他桌面平台沿用独立窗口，不展示吸附入口。
自动化保活验证不替代跨显示器 DPI、输入法、网页全屏视频和实际鼠标交互的人工验收。

2026-10-23 本机验证：33 项相关回归测试通过。真实 WebView2 测试在 144 DPI 下完成
4 次弹出/重新吸附及主窗口尺寸调整，两个页面各请求 1 次；浏览器 HWND、标签 ID、
WebView 创建次数和加载完成后的 JS 标记均保持不变。测试使用独立程序副本。
# 链接点击反馈

消息链接打开浏览器期间，吸附占位区显示加载指示和“正在打开浏览器”。同一链接在打开完成前的连续点击复用同一个请求；不同链接仍按顺序处理。浏览器窗口就绪后，标签页单独显示安全核验状态；安全核验最长等待 5 秒，超时显示“重新加载”重试入口，迟到的结果不会放行此前超时的导航。风控通过前不加载目标网页。
