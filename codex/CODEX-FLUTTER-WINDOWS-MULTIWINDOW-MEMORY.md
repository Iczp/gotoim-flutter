# CODEX — Flutter Windows 多窗口内存优化与单 Engine 多 View 迁移任务书

> 用途：交给 Codex / 代码代理在**当前实际仓库**中执行。
> 范围：Windows 桌面端优先；Android、iOS、Web、macOS、Linux 不得受到无意破坏。
> 日期：2026-11-03。
> 核心原则：**先审计与测量 → 先做低风险优化 → 独立验证单 Engine 多 View → 通过门禁再迁移**。

## 0. 执行身份与总目标

你是资深 Flutter、Dart、Windows Win32/C++ Runner、性能诊断工程师。现在直接在打开的仓库里工作；不要仅给出泛泛建议。必须读取实际代码、完成可执行的改动、构建/测试并提交可复核的报告。没有本地 Windows 工具链或无法运行 GUI 时，仍应完成可执行的静态分析、脚本、单元测试及分支原型，但**必须明确标记哪些测试未实际执行**。

项目背景：GotoIM 类聊天应用，Flutter 多端，Windows 有独立聊天窗口。既有实现据称使用 `desktop_multi_window`；用户观察到多窗口全开后约 1.7GB 内存，但此数字、统计口径、窗口数量、WebView2 进程归属均**尚未实测核实**。项目可能具有多聊天身份 `ChatObjectId`、SignalR、Dio、SQLite、图片视频预览、WebView2、系统托盘等能力；以实际仓库为准，不得凭背景信息编造代码。

最终目标：

1. 找到“基础内存 + 每新增窗口内存 + 业务重复初始化 + 媒体/WebView2”各自的开销；
2. 消除重复初始化、重复消息订阅、重复连接、不可回收的窗口资源；
3. 评估并验证 **单 Flutter Engine + 多 FlutterView + 多 Windows 原生窗口**；
4. 若验收通过，低风险迁移 Windows 多窗口实现，同时保留现有聊天业务功能、账号/身份隔离与其他端的运行；
5. 产出真实的可复现报告，不能把预计内存节省写成实际成果。

## 1. 硬性规则（优先级最高）

- **必须先读仓库**：根目录 `AGENTS.md`、相关子目录规则、`pubspec.yaml`、`pubspec.lock`、Flutter/Dart 版本、`windows/runner`、窗口打开/关闭/通信代码、启动入口和服务注入。仓库规则优先于本通用示例。
- **未经验证，禁止直接全量替换** `desktop_multi_window`，禁止直接整文件覆盖已有 `windows/runner/flutter_window.cpp`、`flutter_window.h`、`main.cpp`；应先保存差异并逐项合并本项目自定义行为。
- 不得升级整个 Flutter SDK、修改后端 API/数据库结构、引入与本任务无关的大规模重构；确有必要先写兼容性说明。
- 移动端和 Web 维持当前入口；桌面窗口能力用平台隔离接口包装。仅 Windows 首先实现新方案；其他桌面平台沿用现有方案或明确标注未实现。
- 任何新 API/依赖都必须依据**安装版本**和当前源码验证，不得直接照搬其他版本的 README。
- 不要把“多 Engine = 多进程”或“多 Engine = 多个独立 Dart VM”当成普遍事实；必须观察真实进程/Engine 模型。
- 不能假定单 Engine 会使 WebView2、GPU、图片内存、SQLite、播放器全部自动共享或消失。运行时共享与资源回收分别处理。
- 禁止输出访问令牌、私聊内容、手机号、数据库密钥到性能日志；采样数据需脱敏。
- 遇到阻断性兼容问题，**保留旧架构并交付完成的阶段成果**，不要伪称迁移成功。
- 减少无关改动；写清每个文件为何修改。优先稳定性、正确性，其次性能。

## 2. 必须生成的工作文件

按仓库约定放在 `docs/performance/` 或已有性能文档目录，名称可依据既有规范微调：

```text

docs/performance/
  WINDOWS-MULTIWINDOW-AUDIT.md         # 当前实现、进程/Engine模型、引用路径、风险
  WINDOWS-MEMORY-BASELINE.md           # 实测环境、实验步骤、1/2/5/10窗口数据
  WINDOWS-MULTIVIEW-FEASIBILITY.md     # 插件/官方API评估和兼容性矩阵
  WINDOWS-MULTIWINDOW-ACCEPTANCE.md    # 构建、功能、性能、回归、阻断项
  WINDOWS-MULTIWINDOW-CHANGELOG.md     # 实际修改文件、迁移/回滚方式
scripts/perf/
  windows-memory-sample.ps1            # Windows 进程树内存采样，CSV输出
```

若仓库已有相同能力文件，按现有结构整合，不要制造重复规范。生成的报告必须包含真实路径、真实版本、真实测试命令与结果。

## 3. 阶段一：代码审计与架构图（必须先完成）

### 3.1 找出全部窗口实现

搜索 `desktop_multi_window`、`WindowController`、`window_manager`、`FlutterViewController`、`runApp`、`main()`、`MethodChannel`、`WindowMethodChannel`、`webview`、`flutter_inappwebview`、`sqlite`、`drift`、`sqflite`、`signalr`、`HubConnection`、`Dio`、`ImageCache`、`CachedNetworkImage`、各类 `get_it` / Provider / Riverpod / Bloc 注册入口。搜索仅作为线索，逐个阅读实际调用链。

至少列出：

| 项目 | 审计内容 |
|---|---|
| 环境 | Flutter/Dart、Windows SDK、MSVC、编译架构（x64/arm64）、Release/Profile构建方式 |
| 窗口 | 主窗口、聊天窗口、资料卡、菜单、媒体预览、设置、WebView、登录、浮窗等及每类打开方式 |
| Engine | 每窗口 Engine/Isolate/进程模型；插件注册方式；消息通道 |
| 服务 | SignalR、Token、Dio、数据库、消息仓储、消息同步器、图片媒体缓存、计时器初始化路径 |
| 释放 | `dispose()`、`close()`、StreamSubscription、`Timer`、Controller、WebView/播放器销毁与引用残留 |
| 会话 | 账号切换、多 `ChatObjectId`、`SessionId`、同会话复用窗口策略 |
| 原生 | Windows Runner 自定义代码、系统托盘、单实例、任务栏、文件拖放、快捷键、深链、通知 |

绘制当前架构与目标架构，使用 Mermaid 或仓库现有技术文档格式；所有结论附代码路径和相关类/函数名。

### 3.2 关键排查项

- 每新开一个窗口，是否重新登录、创建 SignalR HubConnection / Redis 相关客户端、创建 Dio、打开 SQLite 连接、拉取全部聊天/联系人、预热图片或缓存？
- 是否存在“同一账号/聊天身份/SessionId 打开多个相同窗口”或重复订阅相同消息？
- 关闭窗口后是否仍有消息订阅、定时器、Provider/Bloc、图像缓存、浏览器内核进程？
- 子窗口启动逻辑是否执行主窗口全量初始化？能否初始化只需的依赖？
- 对多 Engine 方案：Dart 单例**只在单个 Isolate 范围内**有效。需要跨 Engine 共享时，提出主 Engine 持有服务 + IPC 的实际实现；不要用普通静态变量假装全局共享。
- SQLite 多连接访问可行，但必须检查 WAL、锁冲突、事务、并发写入、关闭顺序；不允许未经分析共享原生连接句柄。

交付 `WINDOWS-MULTIWINDOW-AUDIT.md` 后进入阶段二。

## 4. 阶段二：可复现的 Windows 内存基线

### 4.1 测量原则

- 使用同一台机器、同一份测试账号/脱敏数据、同一显示器/DPI及分辨率、相同内容、同一运行模式（优先 **Release**；需要 VM 堆信息可补充 Profile）。
- 区分 Windows `Working Set`、`Private Bytes`/私有提交、Dart Heap、GPU、WebView2 子进程。不能把不同口径混写。
- 记录根进程 PID、进程树、主/子窗口数量、WebView2 子进程归属；**不要统计其他软件的所有 `msedgewebview2.exe`**。
- 记录冷启动、热启动、多开及关闭后的变化，并重复 3 次取中位数。
- 不需要读真实私聊内容；使用测试会话或脱敏数据即可。

### 4.2 实验矩阵

主窗口单独运行后分别测试：

| 组别 | 场景 |
|---|---|
| S0 | 仅主窗口，空闲稳定后 |
| S1 | 主窗口 + 1 个空聊天窗口 |
| S2 | 主窗口 + 4 个空聊天窗口 |
| S3 | 主窗口 + 9 个空聊天窗口 |
| S4 | 共 10 窗口，文字消息 100/500 条（按实际可测） |
| S5 | 共 10 窗口，若干头像与图片消息 |
| S6 | 按实际功能加入视频/图片预览、WebView2 |
| S7 | 连续打开/关闭相同窗口 30 轮，观察内存回落及长期趋势 |
| S8 | 多窗口同时接收消息、滚动、切换身份，观察帧率和响应 |

必须输出 CSV：`scenario,iteration,timestamp,root_pid,window_count,process_count,private_mb,working_set_mb,webview_private_mb,dart_heap_mb,notes`。不可获得的指标填空且注明原因，不允许伪造 0。

`scripts/perf/windows-memory-sample.ps1` 需：

1. 参数化根进程名称/PID、采样间隔、采样次数、输出路径；
2. 通过 Windows 进程父子关系追踪应用进程树（标明子进程归属判断的局限性），对失联/孤儿 WebView2 另外记录；
3. 输出每进程和进程树汇总两种 CSV；
4. 不执行任何终止进程或清缓存等破坏性操作；
5. 在 PowerShell 5.1/7 条件下尽量可用，并捕获进程退出期间的异常；
6. 记录起始时刻的进程映射及测试环境，不将全系统浏览器进程混入统计。

如果没有 Windows GUI 执行环境：生成脚本、说明执行步骤和预期文件格式，`measured=false`，不得报告模拟的“内存下降百分比”。

### 4.3 基线诊断输出

计算：

- `M_base`：S0 的典型私有内存；
- `ΔM_mean = (M_10 - M_1)/9`：1 到 10 窗口区间平均增量（**不是每窗固定内存**）；
- 单开文字/图片/WebView 的额外增量；
- 关闭窗口后的内存趋势，不强求操作系统工作集立即归零；
- CPU、UI/raster 帧耗时、消息到达延迟与内存优化之间是否存在权衡。

先列最有证据的 Top 5 内存开销来源及对应文件/函数，再决定阶段三的优化项。

## 5. 阶段三：在旧架构上实施低风险优化

每一项必须先证明当前实现存在问题，再更改；每项更改前后记录独立实验结果：

1. **防止重复窗口**：按业务语义创建稳定 `WindowKey`，建议候选维度：`accountId + chatObjectId + sessionId + windowType`；如果当前系统的身份作用域不同，以仓库实体/路由约束为准。重复打开则激活已有窗口；并发打开要使用互斥或 in-flight 去重。
2. **按需启动子窗口**：减少子窗口进入时不需要的联系人、全量消息、媒体库、导航模块初始化。
3. **网络/实时连接**：审计是否每窗建立 SignalR。若采用主 Engine 集中持有连接 + IPC，需具备请求超时、重连、订阅与取消订阅、消息顺序、幂等、丢包补偿和主窗口关闭策略；如果暂时无法安全集中，至少消除重复订阅并说明缘由。不得破坏原本的离线游标补偿。
4. **缓存**：减小默认图片解码尺寸（头像按 DPR、消息图片按视口）、限制无界内存缓存、缩略图优先，不把全分辨率图片长期缓存到每个窗口。
5. **消息列表**：视口分页/虚拟化、图片懒加载、保留必要的滚动锚点与本地数据库索引，不为了省内存破坏历史消息定位。
6. **释放**：关闭窗口需释放该窗口独占的定时器、Controller、StreamSubscription、播放器、WebView、输入框状态；共享服务需引用计数或由 AppRuntime 统一管理，不能误释放其他窗口仍在使用的对象。
7. **WebView2**：按需创建和关闭；记录其子进程。不要宣称 Flutter Engine 合并必然消除 Chromium 进程。

必要的测试：主窗和子窗重复打开、关闭、登录/登出、切换账号/聊天身份、弱网重连、消息撤回/仅自己删除/修改（如果项目支持）、断线后本地补偿；不得仅验证空窗口。

阶段三结束时，写清“仅优化旧架构”能节省多少**实测**内存。如果已达目标且新方案风险过大，可以建议暂停迁移，但仍进入独立原型可行性评估。

## 6. 阶段四：单 Engine 多 View 的独立原型

### 6.1 方案候选（不能先入为主）

- **候选 A：`multiview_desktop`**：截至 2026-11-03，pub.dev 可见 2.0.2；主张 Windows/macOS/Linux 单 Engine、多 FlutterView、单 Dart Isolate。其 Windows Runner 集成需要修改 `flutter_window.cpp`、`.h`、`main.cpp`；2.x 的部分窗口方法改为 FFI 同步调用。确认项目使用的 Flutter/Dart 版本满足依赖约束。
- **候选 B：Flutter 官方 Desktop Windowing API**：官方 2026-08-24 博文说明当时仅在 `main` channel 通过实验 flag 使用；不可未经验证将实验性 API 作为生产默认路径。可以用隔离 SDK 原型评估，不得改动正式开发 SDK 配置。
- **候选 C：当前 `desktop_multi_window` 优化版**：若单 Engine 不通过兼容性/稳定性门禁，则作为保底方案。

**必须重新查询当前依赖与官方文档，确认实际版本、许可证、最近维护、已知问题、Windows Runner 实现及与本仓库插件兼容性。**

参考：
- https://pub.dev/packages/multiview_desktop
- https://pub.dev/packages/multiview_desktop/changelog
- https://pub.dev/packages/desktop_multi_window
- https://flutter.dev/blog/desktop-windowing-apis
- https://docs.flutter.dev/release/breaking-changes/window-singleton

### 6.2 原型策略

- 在隔离分支或 `examples/desktop_multiview_poc/` 建最小 demo；**不要先替换正式主应用的所有 WindowController**。
- 目标功能：1 个主窗口 + 9 个真实 OS 聊天窗口；每窗有独立导航、窗口标题、最小/最大化、任务栏显示、焦点与文本输入；复用同一份 Dart 消息状态并实时刷新。
- 证明单 Engine：记录原生 Engine 初始化次数、窗口/FlutterView 数量和 Dart 状态实例标识；不能只凭进程数量推断。
- Windows Runner 改动必须与当前项目的自定义托盘、`WM_CLOSE`、`WM_FONTCHANGE`、插件注册、任务栏、深链、关闭策略逐项合并。原插件文档要求用新插件管理 Engine/主 View 和消息处理，**但不能整文件覆盖现有定制**。
- 若需要每个子窗口独立根 `MaterialApp`、多语言/主题，验证 `InheritedWidget`/Provider/Riverpod/Bloc 作用域；多个 FlutterView 之间主窗口 Context 不可直接用于子窗口导航。
- 混合 DPI、多显示器、窗口移动、缩放、最小化/恢复、边界溢出菜单必须测试。
- 记录窗口打开延迟、私有内存增量、页面首帧、消息同步延迟、窗口关闭后内存趋势和稳定性。

### 6.3 插件兼容性矩阵（必须逐项）

对仓库**实际使用**的包逐一建立以下表格，若未安装填 N/A：

| 插件/能力 | 主窗口 | 子 FlutterView | 跨 View 状态 | 关闭释放 | 证据/问题 |
|---|---|---|---|---|---|
| window_manager / 托盘 | | | | | |
| WebView2 / inappwebview | | | | | |
| SQLite / drift / sqflite | | | | | |
| 文件选择 / 拖放 / 剪贴板 | | | | | |
| 系统通知 / 深链 / 单实例 | | | | | |
| 全局快捷键 / 本地快捷键 | | | | | |
| 图片 / 音视频 / Hero预览 | | | | | |
| 输入法（中文 IME）/ 焦点 / 光标 | | | | | |
| 主题 / 本地化 / 字体 / 系统缩放 | | | | | |
| 窗口关闭 / Alt+F4 / 任务栏 / 系统托盘 | | | | | |

禁止仅填写“理论支持”。每项注明 `通过/失败/未测` 与测试证据。

## 7. 阶段五：通过门禁后才迁移正式项目

### 7.1 迁移准入门禁

须同时满足：

- 原型 Release 构建成功且 Windows Runner 及插件无阻断兼容错误；
- 真实多窗口 UI/消息共享/输入法/焦点/关闭/托盘/文件拖放等核心功能通过；
- 连续 30 次打开关闭及长时间运行没有明显持续增长、崩溃、黑屏、卡死或资源泄漏；
- 10 窗口对照下，**实测**私有内存显著下降，目标可先以相对旧架构 **≥30%** 作为“理想收益参考”，不是可凭空保证的硬事实；如果收益不足，给出是否值得承担改造风险的量化判断；
- 消息收发、身份隔离与离线补偿正确，响应/帧耗时无不可接受退化；
- 有明确回滚路径。任何关键能力失败 → **不要迁移生产入口**，留下原型、审计及阻断报告。

### 7.2 推荐正式抽象（结合仓库现有架构调整）

```text
DesktopWindowService（抽象，业务层只依赖此接口）
 ├─ LegacyMultiEngineWindowService （旧实现，保留回滚能力）
 └─ SingleEngineMultiViewWindowService （Windows 新实现）

AppRuntime（每个实际运行时作用域初始化一次）
 ├─ Auth/AccountScope
 ├─ DioClients
 ├─ SignalRConnectionManager
 ├─ LocalDatabase / Repositories
 ├─ MessageSyncService
 ├─ MediaCachePolicy
 └─ WindowRegistry
     ├─ MainWindow
     ├─ ChatWindow(accountId, chatObjectId, sessionId)
     ├─ MediaPreviewWindow
     └─ SettingsWindow
```

说明：以上是**建议结构，不是强制新建这一组类**。若仓库已有类似服务，复用之，避免再建第二套框架。

业务要求：

1. 同一会话重复打开 → 复用/聚焦已有窗口；不同聊天身份必须互相隔离；
2. 账号退出/切换时，正确关闭或重绑定子窗口、取消订阅、防止账号 A 的消息显示在账号 B；
3. 窗口共享消息仓储、同步状态、图片缓存策略，但每窗独立 `ScrollController`、焦点、选中状态、输入草稿及导航栈（草稿是否共享以既有产品规则为准）；
4. 关闭主窗口时遵守现有“最小化到托盘/退出应用/子窗口继续存在”产品设定，不能由插件默认值覆盖；
5. 不改动服务端 SignalR 消息协议、数据库结构及现有游标语义；确实需要变更时单独记录，禁止擅自实施。

尽量采用平台配置/构建时开关支持回退。**不要在同一构建中不加验证地同时初始化两个相互冲突的原生窗口插件。**

## 8. 阶段六：最终验收与报告

### 8.1 功能验收清单

- [ ] Windows Release 构建成功，`flutter analyze` 和相关测试通过。
- [ ] 主窗口启动、重启、关闭、从托盘恢复正常，无白屏/黑屏。
- [ ] 1、2、5、10 窗口创建/恢复/聚焦/关闭稳定。
- [ ] 同一个 `accountId/chatObjectId/sessionId` 不重复创建窗口。
- [ ] 同账号不同身份的消息、未读、权限与缓存不会串用。
- [ ] 多窗口 SignalR 实时接收、发送、撤回、删除、修改、离线补偿按现有业务预期工作。
- [ ] 多个窗口同时滚动聊天记录、图片预览/视频播放无明显卡顿。
- [ ] 中文 IME、复制粘贴、拖拽/文件选择、快捷键、Alt+Tab、任务栏、DPI、双屏正常。
- [ ] 系统托盘、窗口置顶、最小化到托盘、主窗口关闭行为符合旧版本。
- [ ] 子窗口关闭后订阅、播放器、WebView2、Controller、Timer 释放，重复 30 轮无明显内存长期上升。
- [ ] 非 Windows 平台编译/入口未被破坏；无法验证的端明确注明未测。
- [ ] 无真实用户隐私数据进入基准测试输出。

### 8.2 性能对照表（必须填写实际测量值，未测则写“未测”）

| 指标 | 原始现状 | 旧架构优化后 | 单 Engine 原型 | 正式迁移后 |
|---|---:|---:|---:|---:|
| S0 主窗口 Private MB | | | | |
| S1 共2窗口 Private MB | | | | |
| S2 共5窗口 Private MB | | | | |
| S3 共10窗口 Private MB | | | | |
| 10窗 WebView2 Private MB | | | | |
| 10窗平均新增窗口 MB | | | | |
| 首次打开子窗 P50/P95 ms | | | | |
| 消息到达→UI更新 P50/P95 ms | | | | |
| 连续开关30轮趋势 | | | | |
| 崩溃/错误/功能回归 | | | | |

要求提供：测试设备/CPU/内存/GPU/屏幕DPI、Flutter/Dart 版本、构建模式、Git commit、采样日志路径、实际运行命令、异常日志、性能收益计算方法。不能以 Task Manager 截图的单一数字替代对照报告。

### 8.3 最终答复模板

完成工作后给用户一份**简明但有证据**的总结：

1. **已完成**：具体文件、功能及测试；
2. **原始根因**：有代码路径和测量证据的 Top N；
3. **改造结果**：旧架构与新架构 1/2/5/10 窗口的真实数据、收益百分比和测量口径；
4. **未完成/阻断**：原因、可重现步骤、风险；
5. **推荐决策**：正式采用单 Engine / 保留旧架构 / 等待官方稳定 API；
6. **回滚方法**：具体开关、分支或回退 commit；
7. **测试命令**：已真实运行与仅推荐人工运行的命令分别列出。

如果最终只能完成前两阶段，仍要提交有价值的审计、基线脚本和结论，**不得以“已做完优化”描述未执行的工作**。

## 9. Codex 操作顺序（严格执行）

```text
1. 阅读 AGENTS.md / 仓库结构 / pubspec.lock / Windows Runner
2. 创建审计文档，标注真实代码入口和重复资源
3. 添加可运行的 Windows 内存采样脚本
4. 在具备环境时跑 1/2/5/10 窗口基线；无环境则标未测
5. 修复可证实的旧架构重复初始化、窗口去重与资源释放问题
6. 隔离分支或 examples 创建单 Engine 多 View Windows POC
7. 建兼容矩阵；构建、测试中文输入、焦点、托盘、WebView 等
8. 根据实际收益和门禁决定是否迁移正式 Windows 入口
9. 若迁移，通过抽象封装窗口后端，保留明确回退途径
10. 运行可执行的回归/性能测试，提交报告与真实验证记录
```

**执行指令**：现在开始第 1 步。除非遭遇确实不可恢复的构建/访问权限阻断，否则继续向下执行到可达的最远阶段。发现仓库与本任务书不符时，以代码事实为准并写入审计报告，不要反复要求人工确认已能从代码获得的信息。
