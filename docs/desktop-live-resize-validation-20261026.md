# Windows 窗口实时缩放修复与实测记录

日期：2026-10-26。范围：Flutter Windows Runner、吸附布局去重和已有窗口诊断。无后端 API、数据库、Redis、Migration 或依赖升级。

## 原因与修改

1. 主引擎没有显式采用子窗口已有的独立 UI 线程策略；Win32 消息处理、Dart 布局及渲染可能互相等待。主引擎现在与现有 desktop_multi_window 实现一致，使用当前 SDK 的 RunOnSeparateThread。
2. SDK 插件中的 WM_SIZE 和 WM_WINDOWPOSCHANGED 都会触发内容尺寸同步，并使用 MoveWindow(..., TRUE) 同步重绘。修复在项目现有 WindowControls 中统一拦截并合并，不改 Pub Cache 或生成的插件目录。
3. 鼠标边缘缩放改用非阻塞原生捕获。高频鼠标事件只保留一个待处理消息，取当前物理坐标，按照被拖动的边/角更新矩形，保持另一边锚点及最小尺寸；松手提交准确终点，取消/失去捕获时结束。
4. 每个窗口只保留一个内容尺寸同步消息，执行时读取最新客户区，跳过相同尺寸。通过 SetWindowPos 更新 Flutter 子视图，去掉热路径中的同步 UpdateWindow。主窗口内容尺寸提交后再同步吸附窗口，位置移动仍实时跟随。
5. 相同吸附矩形不再重复发 IPC；槽位可见性不再每次布局都重发。新布局握手即便矩形相同也必须完成，新增测试覆盖窗口替换场景。

主要文件：

- windows/runner/window_controls.cpp：非阻塞缩放、尺寸同步合并、诊断计数。
- windows/runner/window_resize_policy.h：物理坐标缩放几何及最小尺寸锚点策略。
- windows/runner/main.cpp：主引擎 UI 线程策略。
- lib/core/native_window/desktop_dock_slot.dart、desktop_window_dock_controller.dart：布局及可见性去重。
- lib/core/browser/desktop_browser_window.dart：现有诊断返回 Flutter 视口和网页 innerWidth/innerHeight。

## 实际操作与结果

旧版本已通过 computer-use 实际操作过主窗口和独立浏览器的边缘。修复后另启动一个独立本地测试副本，使用真实 Flutter 主窗口、真实多引擎浏览器、WebView2 和本地 HTTP 页面；没有退出当前用户进程，没有输入或发送聊天消息。

实测中必须先置前目标窗口，再观察画面和操作最外侧边缘；窗口被遮挡的截图不能作为渲染验收依据。最初一次因输入干扰/等待超时未执行主窗口缩放，报告明确为失败，没有计作通过。重新启动后实际完成两处缩放，最终报告 passed=true：

| 观察项 | 主窗口 | 独立浏览器 |
| --- | --- | --- |
| 缩放前，逻辑尺寸 | 1280×720 | 1024×720 |
| 截图中的缩放后尺寸 | 1101×601 | 851×601 |
| 实际客户区，物理像素 | 1652×902 | 1277×902 |
| Flutter 子视图，物理像素 | 1652×902 | 1277×902 |
| 实际 DPI 比例 | 1.5 | 1.5 |
| Flutter 逻辑视口 | 1101.333×601.333 | 851.333×601.333 |
| 网页 DOM 视口 | 不适用 | 851×557（不含工具栏） |

主窗口中心的尺寸文字和浏览器页面内的尺寸文字均在操作后更新。原生检查确认鼠标缩放路径实际触发；结束后两处 nativeResizeActive 均为 false。测试还执行了后续吸附/脱离及媒体窗口切换，两个页面的 HTTP 加载计数均为 1，WebView 创建计数和导航计数为 [1,1]，JS 内存标记保持不变。

报告：build/live-resize-native-report2.json；首次未完成操作的报告为 build/live-resize-native-report.json。生成目录不提交。

测试副本已退出，当前用户进程保留。测试日志尾部有一条 Flutter task_runner_window 的 Failed to post message to main thread 信息；本轮未进一步定位该退出阶段日志，没有将其计作缩放成功或性能依据。

## 性能数值的含义

- 本次手动缩放后的诊断快照中，内容尺寸队列最大等待记录为 0ms。GetTickCount64 有分辨率限制，该值不代表端到端零延迟。
- 原生内容更新调用的生命周期最大耗时：主窗口 47ms、浏览器 140ms。浏览器 140ms 在手动缩放前的初始吸附快照中已经存在，不能当作该次拖动的耗时。
- contentResizeRequests 统计 WM_SIZE；Applied/Skipped 统计内容同步执行结果，后者也包含位置变化/最终提交触发的同步，不能将三个计数直接相减估算帧数。
- 这些诊断没有测量 GPU 完整呈现延迟或持续拖动 FPS，不宣称达到 60/120 FPS，也没有对真实账号的复杂聊天内容做性能基准。

## 自动化和构建

- 32 项相关 Flutter 回归全部通过，包括新增的 50 次相同矩形更新不重复发 IPC、相同矩形仍能完成替换握手。
- 原生测试通过：八个缩放方向、固定相对边、最小尺寸、负屏幕坐标及 DPI 物理位移。
- 修改文件静态分析：No issues found。
- Windows C++ 编译、链接和 Dart 资源 bundle 编译通过。
- 原生测试命令：build/live-resize-policy/Debug/window_resize_policy_test.exe。
- 日志：build/live-resize-native-build.log、live-resize-dart-tests.log、live-resize-analyze-final.log、live-resize-app-bundle.log。

## 运行与限制

完整修复预览目录：F:\Dev\GotoIM\gotoim-flutter\build\live-resize-preview。
完整退出旧程序后运行该目录的 gotoim_flutter.exe，保留整个目录。当前用户进程未被替换/关闭；旧 Debug 程序及上一轮预览不包含本轮原生修改。

本轮实测覆盖当前设备 150% 缩放下的本地测试页面。混合 DPI 跨屏、高刷新率持续拖动、复杂真实聊天内容以及系统贴边行为仍需后续验收。保持上一轮手动捕获模式的限制：不自动模拟 Windows 系统拖边贴靠/摇动行为。独立 UI 线程策略依赖当前 Flutter SDK 支持，后续 SDK 移除此能力时需要重新验证。
