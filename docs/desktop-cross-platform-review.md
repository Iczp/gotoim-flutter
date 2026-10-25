# 桌面跨平台实现审查与修复记录

日期：2026-10-24

范围：gotoim-flutter 当前工作区相对 742994d 的跨平台改动。属于 Flutter 平台隔离层、窗口服务和桌面 Runner，不涉及后端、数据库、Redis 或 Migration。保留原有 WindowService、窗口缓存及吸附控制器。

## 审查结论

本次提交不能视为已完成原交接文档。Windows 已有完整实现；新增 macOS/Linux 代码存在工程接入、原生窗口路由、通道缺失以及能力误报问题。修复基础控制，并关闭尚未满足协议的入口；关闭入口属于明确的临时降级，并不等于完成该平台功能。

## 已修复

| 问题 | 影响 | 修复 |
| --- | --- | --- |
| macOS 新 Swift 文件未加入 Xcode Sources | Runner 无法引用 WindowControls | 添加文件引用和编译项 |
| 子引擎过早读取 view.window，失败时回退 keyWindow/mainWindow | 可能操作其他子窗口或主窗口 | 每引擎保存自身控制器，调用时解析自身窗口；未挂载则返回错误 |
| macOS 返回的窗口矩形字段不符合 Dart 约定 | 定位消费者无法解析 | 返回 left/top/right/bottom/clientLeft/clientTop/clientWidth/clientHeight/dpi |
| Linux 未注册 gotoim/window | 最小化、关闭等静默无效 | 主引擎和子引擎均注册独立 GTK 原生通道 |
| 原生关闭销毁缓存引擎或未通知 Dart | 注册表与实际窗口状态不一致 | 转发 closeRequested，隐藏和缓存由 Dart 管理；显式 destroy 才释放；释放前先回复方法调用 |
| macOS/Linux 未安装 Dart 原生回调处理器 | 关闭事件丢失 | 安装当前引擎的 closeRequested/hotkey/trayEvent 处理器 |
| 原生调用吞错、最大化读取旧缓存 | 操作无效却显示成功、图标滞后一拍 | 传播错误及超时；等待原生回复再更新最大化状态 |
| 启动入口与截图页面替换适配器后遗漏导入 | 入口及截图页面编译失败 | 修正两个导入，并执行 Windows 目标 bundle 编译 |
| 新增 PlatformFacade 抽象成员破坏已有 implements | 现有测试和集成编译失败 | 使用兼容的扩展 getter 提供能力查询 |
| CATransaction.flush 被当作 Flutter 首帧确认 | 仍可能展示旧帧或白屏 | 移除假确认；仅支持真正 ACK 的平台调用 prepareFrame |
| 未完成的 Mac 吸附缺少快照恢复、物理坐标换算和可见性协议 | 状态、尺寸、层级不可靠 | 暂时禁用入口，保留独立窗口和同一引擎 |
| Mac 截图未接入截图服务，坐标/权限不完整；Linux 无内置标注协议 | 误报支持、无效窗口或错误裁剪 | 关闭内置截图能力和预热，保留已有系统截图路径 |
| 无完整资料卡悬停与定位协议仍创建原生窗口 | 无法按约定保留交互或正确定位 | 非 Windows 跳过预热和原生悬浮入口；普通点击资料详情不受影响 |
| 不支持的置顶、视频和托盘浮窗仍显示入口 | 点击无效或持续重试 | 按能力隐藏置顶；Linux 视频提供系统播放器；非 Windows 托盘消息使用主窗口内浮层 |
| 诊断预热固定声称所有工具成功 | 掩盖未实现能力 | 返回实际注册窗口和能力；资料卡测试明确提示不支持 |

## 修复后的支持边界

| 能力 | Windows | macOS | Linux |
| --- | --- | --- | --- |
| 独立窗口与基础控制 | 沿用原实现 | AppKit 通道已接入，待真机验证 | GTK 通道已接入，待 X11/Wayland 验证 |
| 吸附保活、脱离恢复及边缘留白 | 沿用原实现 | 暂关闭，待完整实现 | 暂关闭，待完整实现 |
| 独立悬浮资料卡 | 沿用原实现 | 暂关闭 | 暂关闭 |
| 每引擎原生首帧 ACK | 原生 ACK | 仅 Flutter warm-up，不承诺无白屏 | 仅 Flutter warm-up，不承诺无白屏 |
| 内置截图标注 | 原实现 | 系统截图降级，无内置标注 | 系统截图降级，无内置标注 |
| 置顶 | 原实现 | AppKit 实现待验证 | 隐藏入口 |
| 视频 | 原实现 | 沿用播放器插件，待验证 | 系统播放器降级 |
| 托盘消息预览 | 原生浮窗 | 主窗口内浮层，待验证 | 主窗口内浮层，托盘依赖桌面环境 |

## 仍需完成的开发

1. macOS 优先：NSWindow 吸附需保存独立状态、处理主窗口移动/缩放/最小化、槽位与路由可见性、焦点和边缘留白；切换全过程保留同一 WebView/引擎，不能通过 URL 重建。
2. 资料卡继续保持独立窗口，不做吸附。补跨窗口悬停、进入后点击保留和屏幕工作区定位。
3. 实现每引擎真正的 Flutter 原生绘制确认，再打开相应能力。Core Animation flush 不是 Flutter raster ACK。
4. macOS 实现屏幕录制权限、全桌面截图、混合缩放与负坐标，再接入 ScreenCaptureService 和标注工作台。
5. Linux 区分 X11 与 Wayland。Wayland 无法保证任意全局坐标跟随，应明确能力限制；截图优先使用桌面 portal 协议。
6. 各功能必须在对应系统构建及真机验收后更新支持状态；不能只根据操作系统名称将尚未实现的能力设为 true。

## 验证

- 相关回归：75 项全部通过。覆盖平台原生通道派发与错误传播、关闭回调、未实现能力保护、首帧 warm-up、窗口吸附状态与回滚、浏览器会话、浮动窗口缩略图、窗口服务、URL 风控、Windows 回归以及 DPI 1.0/1.5/2.0 截图交互。
- 修改文件及新增测试的 `dart analyze`：No issues found。
- 全量 `lib` 与新增测试分析：无 error、无 warning；另有 8 条非本次改动文件的 info 提示，涉及 deep_link、group_management 等，保持范围不扩大。
- `flutter build bundle --debug --no-pub --target-platform windows-x64`：退出码 0，验证 Dart 入口和资源编译；这不是完整 Windows exe 原生链接构建。
- `git diff --check`：通过。
- 日志：`build/cross-platform-review-tests-final.log`、`build/cross-platform-review-changed-analyze.log`、`build/cross-platform-review-final-analyze.log`、`build/cross-platform-review-windows-bundle.log`（生成目录，不提交）。

当前为 Windows 开发机，无法执行 macOS Xcode 构建；本机 WSL 服务启动失败，未执行 Linux 原生构建。本轮没有进行对应系统的 GUI 实测，Dart mock 测试不等同于 AppKit/GTK 运行验收。

可重跑的回归命令：

```powershell
flutter test --no-pub test/core/platform test/core/native_window/desktop_window_dock_test.dart test/core/native_window/desktop_window_loading_test.dart test/core/browser/desktop_browser_dock_test.dart test/core/browser/desktop_browser_session_test.dart test/core/browser/floating_web_bubble_test.dart test/core/browser/app_webview_page_test.dart test/core/floating_window/floating_window_manager_test.dart test/core/services/window_service_test.dart test/core/security/url_security_test.dart test/desktop/windows_repair_regression_test.dart test/desktop/screen_capture_interaction_test.dart --reporter expanded
```

参考：

- [Flutter macOS FlutterViewController](https://api.flutter.dev/macos-embedder/interface_flutter_view_controller.html)
- [Apple CATransaction](https://developer.apple.com/documentation/quartzcore/catransaction)
- [Flutter Linux MethodCall API](https://api.flutter.dev/linux-embedder/fl__method__call_8h_source.html)
- [Flutter Linux PluginRegistrar API](https://api.flutter.dev/linux-embedder/fl__plugin__registrar_8h.html)
