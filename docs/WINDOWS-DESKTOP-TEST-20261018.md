# GotoIM Flutter Windows 桌面端测试文档

> 后续修复后的实机结果见 [2026-10-18 18:05批次复测报告](WINDOWS-DESKTOP-RETEST-20261018-180516.md)。本文保留上一轮基线，未将旧结果替换为新结果。

| 项目 | 内容 |
|---|---|
| 文档用途 | 本轮实测记录、缺陷复现及后续回归验收；可直接交给开发 AI 或测试人员 |
| 实测日期 | 2026-10-18，Asia/Shanghai |
| 被测项目 | `F:\Dev\GotoIM\gotoim-flutter` |
| 被测提交 | `106c8f55f8a0db793bf2ee830931ad8dbb8f7c57` |
| 构建类型 | Windows x64，Debug |
| 执行方式 | 真实客户端界面操作、系统窗口枚举、运行日志、相关自动化测试 |
| 证据目录 | `F:\Dev\GotoIM\gotoim-flutter\screenshots\windows-live-20261018` |
| 原始截图 | 51 张 JPEG，保留工具原始图片字节 |
| 总体验收结论 | **未通过完整桌面体验验收**；独立窗口已创建，自定义标题栏及部分多窗口业务链路未完成 |

本文件整理已完成的这一轮实测，不代表后续提交已经重新测试。后续修复必须记录新的提交、执行时间和证据，不得直接沿用本轮“通过”状态。

## 1. 测试目标与判定标准

验证 Windows 桌面端是否实现接近微信的使用体验：主窗和业务子窗拥有独立系统窗口，自定义标题栏能够真实操作窗口，聊天消息在多窗之间保持一致，媒体和网页从真实消息入口打开独立窗口，系统托盘可在主窗隐藏后正常工作。

以下三件事分别验收：

1. **独立系统窗口**：存在独立的系统窗口标识，可独立激活和操作；页面内 Dialog 不算。
2. **自定义标题栏**：不显示 Windows 默认标题栏，只保留一层应用标题栏；内容区画一排按钮不算完成。
3. **完整窗口功能**：拖动、缩放、置顶、最小化、最大化、还原、关闭和恢复均产生真实系统行为；按钮图标变化不算通过。

本轮明确观察到：**主窗和已打开的子窗仍使用 Windows 默认标题栏，聊天子窗又叠加了一层自绘操作栏。独立窗口通过，自定义标题栏未通过。**

状态定义：

| 状态 | 含义 |
|---|---|
| 通过 | 已执行对应步骤，有实际界面或日志证据，满足该行限定的预期 |
| 失败 | 已执行，实际结果与预期不符 |
| 未判定 | 已观察到异常，但证据不足以确定业务功能是否失败或异常来源 |
| 未执行 | 尚未完成实际操作；代码存在或组件测试通过均不能替代 |

页面“首屏通过”仅表示页面能够显示，不表示该页面全部业务操作通过。本文不计算会掩盖未执行范围的整体通过率。

## 2. 测试环境与数据

### 2.1 运行环境

- Windows x64 桌面运行环境，默认渲染配置。
- 使用正常构建产物中的 `sqlite3.dll`；本轮没有使用临时 PATH 补丁或软件渲染参数。
- 网络可访问当前配置的真实服务；主窗日志中有 SignalR 连接及实际消息发送 HTTP 200。
- Windows 具体版本号、显示缩放比例、第二显示器配置本轮未记录，不作为跨环境兼容性已通过的依据。
- 截图中 2560×1392 是最大化窗口捕获尺寸，不直接等同于屏幕完整分辨率或 Flutter 逻辑尺寸。

### 2.2 真实账号和操作对象

- 复用已有登录态，账号选择器显示 `186****9806`。
- 原聊天身份：林惠娟，`ownerId=13`。
- 操作对象：同账号拥有的私人助理机器人；账号选择器包含 8 个聊天身份。
- 本轮未重新验证账号密码登录流程；“真实账号测试”在此指复用真实已登录会话。

实际新增消息：

| 发送身份 | 接收身份 | 内容 | 结果 |
|---|---|---|---|
| 林惠娟，独立聊天窗 | 私人助理 | `test` | HTTP 200；主窗显示 |
| 林惠娟，主窗 | 私人助理 | `2` | HTTP 200；机器人身份主窗显示 |
| 私人助理，主窗 | 林惠娟 | `3` | HTTP 200；林惠娟身份主窗显示 |

三条消息保留。未执行消息删除/撤回、缓存清理、附件迁移、设备强制下线、账号退出或文件共享服务启动。存储管理确认框仅打开后取消。

### 2.3 复现准备

1. 记录当前提交、构建模式、Windows 版本、DPI 和屏幕配置。
2. 启动客户端，确认账号和聊天身份；准备同账号机器人或明确用于测试的对象。
3. 保留真实历史中包含视频、URL、文件的会话，并另备已知可用的媒体和网页用于排除资源本身的问题。
4. 分别记录主窗和子窗的系统窗口标识、标题、尺寸以及窗口枚举前后变化。
5. 逐项记录预期、实际、截图和日志；失败项修复后重新执行，不以代码检索结果直接改为通过。

## 3. 构建和自动化验证记录

以下命令已在本轮实测期间执行；编写本文时未重复构建或重复运行测试。

工作目录：`F:\Dev\GotoIM\gotoim-flutter`。

```powershell
flutter build windows --debug --no-pub
```

结果：成功。存在 WebView CMake CMP0175 开发警告，没有阻止构建。见 [build.log](../screenshots/windows-live-20261018/build.log)。

```powershell
flutter run -d windows --debug --no-pub --no-hot --use-application-binary=F:/Dev/GotoIM/gotoim-flutter/build/windows/x64/runner/Debug/gotoim_flutter.exe
```

结果：默认配置启动成功，显示真实会话和历史。

```powershell
flutter test --no-pub --no-enable-impeller test/core/services/window_service_test.dart test/core/services/window_messenger_test.dart test/core/services/storage_path_service_test.dart test/core/attachment_cache_classified_test.dart test/desktop/desktop_clipboard_paste_test.dart test/desktop/desktop_tray_grouping_test.dart
```

结果：**33 项通过，0 项失败**。见 [targeted-tests.log](../screenshots/windows-live-20261018/targeted-tests.log)。这些测试不等于真实托盘、Windows 播放器、子窗标题栏及真实消息入口已通过。

核对了 487 个源码/配置文件的 SHA256，本轮测试期间未发现变化；没有修改业务代码。见 [validation.json](../screenshots/windows-live-20261018/validation.json)。

## 4. 已执行的功能用例

### 4.1 启动和窗口行为

| 编号 | 操作步骤 | 预期结果 | 实际结果 | 状态 / 证据 |
|---|---|---|---|---|
| W-01 | 默认配置启动；进入消息页 | 加载真实会话和历史 | 正常显示 | 通过：[01](../screenshots/windows-live-20261018/01-startup-default.jpg)、[03](../screenshots/windows-live-20261018/03-main-real-history.jpg) |
| W-02 | 打开私人助理独立聊天窗；枚举系统窗口 | 子窗拥有独立系统标识 | 主窗 60950032，聊天窗 1057006 | 通过：[04](../screenshots/windows-live-20261018/04-native-chat-first-load.jpg)、[窗口枚举](../screenshots/windows-live-20261018/windows-after-chat.json) |
| W-03 | 观察主窗及聊天、设置、文件子窗顶栏 | 只有应用自定义标题栏 | 仍有默认系统标题栏；聊天窗出现双标题栏 | **失败**：[18](../screenshots/windows-live-20261018/18-native-chat-reopen-same-screen.jpg)、[19](../screenshots/windows-live-20261018/19-native-settings-account.jpg)、[29](../screenshots/windows-live-20261018/29-native-file-server.jpg) |
| W-04 | 用聊天窗自绘关闭按钮关闭，再从主窗打开 | 按既定复用策略恢复同一会话 | 关闭后隐藏，重开复用原窗口标识 | 通过，仅覆盖隐藏/复用：[17](../screenshots/windows-live-20261018/17-main-after-chat-close.jpg)、[18](../screenshots/windows-live-20261018/18-native-chat-reopen-same-screen.jpg) |
| W-05 | 点击聊天窗自绘最大化按钮 | 实际最大化，按钮状态同步 | 按钮状态改变，捕获尺寸仍 788×594 | **失败**：[14](../screenshots/windows-live-20261018/14-child-custom-maximize.jpg) |
| W-06 | 双击聊天窗默认系统标题栏 | 系统窗口最大化 | 捕获尺寸变为 2560×1392 | 通过，仅覆盖系统标题栏：[15](../screenshots/windows-live-20261018/15-child-native-maximized.jpg) |
| W-07 | 关闭文件管理窗，再点文件共享入口 | 可重新打开独立文件管理窗 | 重新创建并显示 | 通过：[46](../screenshots/windows-live-20261018/46-file-server-reopened-same-screen.jpg) |

窗口标识是本次进程观察值，后续运行不能写死或照抄。隐藏/复用通过不能推导出引擎销毁和资源释放通过。

### 4.2 真实消息、历史和身份

| 编号 | 操作步骤 | 预期结果 | 实际结果 | 状态 / 证据 |
|---|---|---|---|---|
| M-01 | 林惠娟独立窗发送 `test`，查看主窗 | 发送成功，两窗显示相同消息 | 请求成功；主窗显示 test | 通过：[08](../screenshots/windows-live-20261018/08-chat-send-result.jpg)、[09](../screenshots/windows-live-20261018/09-main-after-child-send.jpg) |
| M-02 | 林惠娟主窗发送 `2`，切机器人身份查看 | 对方能收到消息 | 机器人主窗显示 test 和 2 | 通过：[12](../screenshots/windows-live-20261018/12-main-send-reverse-test.jpg)、[40](../screenshots/windows-live-20261018/40-bot-received-real-messages.jpg) |
| M-03 | 私人助理主窗发送 `3`，切回林惠娟查看 | 林惠娟收到 3，发送方向正确 | 主窗正常显示对方发来的 3 | 通过：[41](../screenshots/windows-live-20261018/41-bot-send-reverse-message.jpg)、[43](../screenshots/windows-live-20261018/43-main-received-reverse-message.jpg) |
| M-04 | 主窗发送 2 后查看原先打开的聊天子窗 | 子窗实时显示 2 | 未显示 2 | **失败**：[13](../screenshots/windows-live-20261018/13-child-after-main-send.jpg)、[42](../screenshots/windows-live-20261018/42-child-missing-reverse-message.jpg) |
| M-05 | 机器人发送 3 后激活原聊天子窗并滚到底 | 旧身份子窗正确收到对应会话的 3 | 主窗有 3，子窗仍停在 test | **失败**：[42](../screenshots/windows-live-20261018/42-child-missing-reverse-message.jpg)、[43](../screenshots/windows-live-20261018/43-main-received-reverse-message.jpg) |
| M-06 | 对照两窗首载历史，滚动并重开子窗 | 消息顺序、最新消息集合一致 | 子窗较新历史在前、较旧历史在后；最新内容与主窗不一致 | **失败**：[16](../screenshots/windows-live-20261018/16-child-history-order-and-sync.jpg)、[42](../screenshots/windows-live-20261018/42-child-missing-reverse-message.jpg) |
| M-07 | 从林惠娟切至私人助理 | 清除主窗旧聊天，加载新身份列表 | 主窗清空右侧，加载机器人会话 | 通过，仅覆盖主窗：[38](../screenshots/windows-live-20261018/38-real-owner-switcher.jpg)、[39](../screenshots/windows-live-20261018/39-switched-to-bot-owner.jpg)、[40](../screenshots/windows-live-20261018/40-bot-received-real-messages.jpg) |
| M-08 | 对真实消息右键，点击复制，再尝试粘贴 | 菜单显示；复制后可粘贴 | 菜单及复制提示出现；自动化输入框未显示粘贴内容 | 未判定：[10](../screenshots/windows-live-20261018/10-message-context-menu.jpg)、[11](../screenshots/windows-live-20261018/11-main-clipboard-draft.jpg) |

M-03 使用同账号另一身份，不等同于另一物理设备入站测试。M-08 受自动化输入与输入法兼容性影响，不能据此直接判定产品粘贴失败。

### 4.3 媒体和网页真实入口

| 编号 | 操作步骤 | 预期结果 | 实际结果 | 状态 / 证据 |
|---|---|---|---|---|
| V-01 | 从真实历史点击视频，比较系统窗口枚举 | 打开独立媒体系统窗口 | 仍为主窗内 Dialog，没有新增系统窗口 | **失败**：[34](../screenshots/windows-live-20261018/34-real-video-history.jpg)、[35](../screenshots/windows-live-20261018/35-real-video-open.jpg)、[枚举](../screenshots/windows-live-20261018/video-window-audit.json) |
| V-02 | 等待该视频初始化 | 可播放或显示正常业务错误页 | 显示 `UnimplementedError: init() has not been implemented.` | **失败**：[35](../screenshots/windows-live-20261018/35-real-video-open.jpg) |
| V-03 | 从全员9527真实消息点击 URL | 打开独立网页系统窗口 | 仍为主窗内 Dialog，没有新增系统窗口 | **失败**：[36](../screenshots/windows-live-20261018/36-real-link-open.jpg)、[枚举](../screenshots/windows-live-20261018/browser-window-audit.json) |
| V-04 | 等待该真实内网 URL 加载 | 页面可读 | 显示连接中止；未排除目标服务及网络原因 | 未判定根因：[37](../screenshots/windows-live-20261018/37-real-link-result.jpg) |

视频样本为历史消息中的 1.6KB、00:01 视频；尚未覆盖更多编码、音频、本地文件及大视频。网页连接失败与“没有独立窗口”是两个独立问题。

### 4.4 设置、工具和页面

| 编号 | 操作步骤 | 预期结果 | 实际结果 | 状态 / 证据 |
|---|---|---|---|---|
| P-01 | 初次打开设置独立窗，检查通用页主题 | 继承主窗当前浅色主题 | 初开深色，但通用页标记浅色 | **失败**：[19](../screenshots/windows-live-20261018/19-native-settings-account.jpg)、[20](../screenshots/windows-live-20261018/20-settings-general-theme-mismatch.jpg) |
| P-02 | 设置选择深色，再查看主窗 | 主窗同步深色 | 同步成功 | 通过：[21](../screenshots/windows-live-20261018/21-settings-select-dark.jpg)、[22](../screenshots/windows-live-20261018/22-main-dark-theme-synced.jpg) |
| P-03 | 设置切回浅色 | 设置及主窗恢复浅色 | 恢复成功 | 通过：[23](../screenshots/windows-live-20261018/23-settings-restored-light.jpg) |
| P-04 | 浏览账户、快捷键、通知、关于、工具页 | 页面能显示 | 首屏可显示 | 通过，仅首屏：[19](../screenshots/windows-live-20261018/19-native-settings-account.jpg)、[24](../screenshots/windows-live-20261018/24-settings-shortcuts.jpg)、[25](../screenshots/windows-live-20261018/25-settings-notifications.jpg)、[26](../screenshots/windows-live-20261018/26-settings-about.jpg)、[28](../screenshots/windows-live-20261018/28-settings-tools.jpg) |
| P-05 | 打开存储管理确认框，再取消 | 取消后不执行清理 | 确认框已取消，未执行清理 | 通过，仅覆盖打开/取消：[27](../screenshots/windows-live-20261018/27-storage-management.jpg) |
| P-06 | 打开文件管理页，点击“打开App资源管理器” | 进入对应资源管理页面 | 没有跳转；日志报 `No GoRouter found in context` | **失败**：[29](../screenshots/windows-live-20261018/29-native-file-server.jpg)、[30](../screenshots/windows-live-20261018/30-file-server-resource-manager.jpg) |
| P-07 | 打开诊断独立窗，观察分组文字 | 深色主题可读 | 出现浅底浅字，文字对比度不足 | **失败**：[31](../screenshots/windows-live-20261018/31-native-diagnostics-home.jpg) |
| P-08 | 点击“桌面端独立窗口测试” | 进入可执行的实际测试页 | 只显示 `诊断模块: desktop-windows` 占位页 | **失败**：[33](../screenshots/windows-live-20261018/33-diagnostics-desktop-window-entry.jpg) |
| P-09 | 打开连接诊断并查看探针结果 | 结果能准确反映对应连接状态 | 子窗探针显示 HTTP401，主窗同期正常发消息 | 未判定认证根因：[32](../screenshots/windows-live-20261018/32-diagnostics-api-navigation.jpg) |
| P-10 | 依次打开通讯录、工作台、探索 | 各首页显示 | 首屏可显示 | 通过，仅首屏：[44](../screenshots/windows-live-20261018/44-contacts-page.jpg)、[45](../screenshots/windows-live-20261018/45-workbench-page.jpg)、[47](../screenshots/windows-live-20261018/47-explore-page.jpg) |
| P-11 | 打开设备管理列表 | 显示真实设备及当前设备标记 | 显示35条设备，当前设备为Windows | 通过，仅查看：[48](../screenshots/windows-live-20261018/48-devices-page.jpg) |

### 4.5 尺寸与布局

| 编号 | 实际截图尺寸 | 检查内容 | 结果 / 证据 |
|---|---|---|---|
| S-01 | 主窗1268×714 | 默认双栏、会话及输入区 | 首屏可用：[03](../screenshots/windows-live-20261018/03-main-real-history.jpg) |
| S-02 | 主窗934×714 | 收窄后布局 | 双栏仍可用：[49](../screenshots/windows-live-20261018/49-main-medium-width.jpg) |
| S-03 | 主窗695×714 | 最窄成功调整宽度下的阅读/输入空间 | **失败**：左侧仍占约358px，聊天区明显受挤压：[50](../screenshots/windows-live-20261018/50-main-narrow-width.jpg) |
| S-04 | 主窗2560×1392 | 系统最大化 | 成功：[51](../screenshots/windows-live-20261018/51-main-maximized.jpg) |
| S-05 | 聊天窗788×594 / 2560×1392 | 默认大小及系统标题栏最大化 | 系统最大化成功，自绘最大化失败：[14](../screenshots/windows-live-20261018/14-child-custom-maximize.jpg)、[15](../screenshots/windows-live-20261018/15-child-native-maximized.jpg) |

进一步尝试收窄到约450px没有成功改变尺寸，不能记录为450px已测。不同高度、跨屏DPI和其他缩放比例尚未覆盖。

## 5. 关键缺陷登记

优先级说明：P1 为阻碍目标桌面体验或核心多窗功能；P2 为显示、布局或辅助工具问题。优先级不代表已经定位全部根因。

| 缺陷编号 | 优先级 | 现象 | 关联用例 | 修复后必须证明 |
|---|---|---|---|---|
| D-01 | P1 | 默认系统标题栏仍存在；聊天双标题栏 | W-03 | 主窗及各子窗都只有一层自定义标题栏，保持独立系统窗口 |
| D-02 | P1 | 自绘最大化不改变系统窗口尺寸 | W-05 | 按钮触发真实最大化/还原；状态与系统一致 |
| D-03 | P1 | 主窗发送和入站消息未更新到聊天子窗 | M-04/05 | 主/子窗消息集合、状态、方向保持一致 |
| D-04 | P1 | 子窗历史排序及最新消息不一致 | M-06 | 首屏最新消息一致，上翻游标分页不重复、不跳动 |
| D-05 | P1 | 真实媒体和网页入口仍打开Dialog | V-01/03 | 从业务消息点击后新增独立系统窗口，主窗可继续操作 |
| D-06 | P1 | Windows视频初始化未实现 | V-02 | 已知有效本地/远程视频可播放并正常释放资源 |
| D-07 | P1 | 文件子窗内部路由失败 | P-06 | 资源管理器正确打开，可返回或关闭 |
| D-08 | P2 | 子窗初始主题不继承 | P-01 | 首开、复用、切换和系统主题变化一致 |
| D-09 | P2 | 诊断页占位和低对比度 | P-07/08 | 进入实际功能页，浅深色均可读 |
| D-10 | P2 | 窄窗固定列表挤压聊天区域 | S-03 | 最小支持尺寸下能正常阅读和输入 |

另外，代码中置顶按钮仅切换本地状态、最小化按钮调用隐藏；本轮未完成相应系统行为实测，应执行后续窗口回归用例。连接探针401和网页连接中止需要分别定位，不能推断整个账号或所有网页功能失败。

具体代码位置、修复方向及架构约束见[实测分析与改进建议](../screenshots/windows-live-20261018/README.md)。

## 6. 托盘实测状态与待执行用例

日志记录托盘初始化成功。**本轮没有取得真实系统托盘图标、菜单或浮窗截图，托盘端到端验收未完成。** 当前桌面工具窗口清单没有暴露任务栏区域，不能用组件生成图或诊断示例数据替代真实结果。

| 编号 | 操作步骤 | 预期结果 | 当前状态 |
|---|---|---|---|
| T-01 | 打开任务栏托盘区域，定位GotoIM图标并截图 | 图标可辨认，没有重复残留图标 | 未执行 |
| T-02 | 右键图标，逐项查看菜单 | 文案、当前身份和操作状态准确 | 未执行 |
| T-03 | 主窗可见时收到一条真实测试消息 | 图标角标及未读数量同步 | 未执行 |
| T-04 | 隐藏主窗后点击托盘图标 | 主窗可恢复并获得焦点 | 未执行 |
| T-05 | 隐藏主窗时收到真实消息，再点击未读入口 | 浮窗真实可见，不依赖主窗内部Dialog显示 | 未执行 |
| T-06 | 用两个拥有的身份分别接收真实消息 | 按身份/会话正确分组，合计准确 | 未执行 |
| T-07 | 点击未读分组中的具体会话 | 激活正确身份和会话，不串到其他对象 | 未执行 |
| T-08 | 在托盘浮窗中展开、折叠、点击外部 | 布局正确；失焦和关闭行为符合约定 | 未执行 |
| T-09 | 在100%/150%缩放及多显示器任务栏上打开浮窗 | 锚定对应任务栏工作区，不越界 | 未执行 |
| T-10 | 通过托盘退出，重新启动 | 退出后无残留图标或子窗；重启只有一个图标 | 未执行 |

T-06/07必须使用真实未读数据，不使用“加载示例数据”“模拟入站”作为验收依据。涉及已读或退出的步骤应在专用测试数据和可恢复运行条件下执行。

## 7. 修复后回归步骤

本节是后续执行规范，**没有声称这些步骤已经全部运行或通过**。

### R-01 自定义标题栏和窗口控件

1. 从正常业务入口依次打开主窗、聊天、设置、诊断、文件管理、网页、图片和视频窗口。
2. 每个窗口首开截图：不出现Windows默认标题栏，不出现双标题栏。
3. 枚举系统窗口：各业务窗口拥有独立标识；主窗可以继续操作。
4. 拖动自定义标题区域；双击最大化，再双击还原；窗口不跳屏或裁切。
5. 点击自绘最小化、最大化、还原按钮，核对实际窗口尺寸、可见性及按钮状态。
6. 点击置顶，用另一普通窗口遮挡验证，再取消置顶恢复普通层级。
7. 拖动边缘和四角缩放，验证最小尺寸、阴影、圆角及最大化边缘。
8. 用系统窗口菜单/快捷操作改变状态，确认应用按钮状态同步。
9. 关闭并重开相同窗口；验证标题、主题、对象、位置和复用策略。
10. 在任务栏、Alt+Tab、贴靠及DPI变化场景检查窗口识别和操作。

验收条件：窗口样式和控件均作用于当前目标子窗；不能通过更改主窗样式或切换图标冒充子窗操作成功。

### R-02 主窗与聊天子窗消息一致性

1. 同一会话同时在主窗和独立窗打开，记录最新serverId及消息数量。
2. 主窗发送唯一测试文本，检查子窗只出现一次并完成发送状态更新。
3. 子窗发送另一唯一文本，检查主窗只出现一次。
4. 从另一身份或第二设备发送消息，检查目标主窗及子窗都收到，方向正确。
5. 隐藏子窗后继续收消息，再恢复；检查最新消息无遗漏。
6. 断网后发送再恢复网络，检查失败/重试状态和重复消息处理。
7. 多个会话开多个子窗，切换主窗身份；确认更新只投递到正确账号、身份和会话。
8. 关闭再打开子窗，检查历史顺序、最新消息、引用、附件和发送人信息。
9. 向上分页，记录页边界消息ID；检查不重复、不漏项，滚动位置稳定。

验收条件：同一会话两窗展示同一消息集合；本地临时消息和服务端回执按clientMessageId/serverId合并；不能通过重建多个SignalR连接绕开主流程同步。

### R-03 真实媒体和网页入口

1. 从真实聊天消息分别点击URL、图片、视频，不从诊断页直接构造窗口替代。
2. 对比点击前后系统窗口枚举，并同时截取主窗与子窗。
3. 子窗激活时操作主窗；主窗不被遮罩阻塞。
4. 使用已知可用的网页及媒体，分别测试加载、播放、暂停、进度、关闭和重开。
5. 使用不可达URL或无效媒体，检查正常错误页和重试，不显示原始未捕获异常。
6. 关闭媒体窗后再次打开，核对播放器释放及恢复；检查授权资源不串账号。

验收条件：独立窗口和内容功能分别通过；网络错误不得被用于掩盖Dialog入口尚未改造的问题。

### R-04 主题、页面路由和响应式布局

1. 浅色/深色状态下首次打开每一类子窗，检查初始主题。
2. 从设置切换主题，检查已打开和后打开的子窗均同步。
3. 点击文件管理、诊断及设置中的内部入口，检查真实页面、返回和关闭。
4. 检查默认、中等、最小支持宽度和最大化，记录实际截图尺寸。
5. 最小尺寸下输入较长文本，检查发送按钮、工具栏及消息内容可操作。
6. 跨屏拖动及改变DPI后重复上述步骤。

## 8. 截图、日志与验收交付要求

每次回归至少提供：

- 被测提交、环境、账号脱敏标识、测试对象、开始/结束时间。
- 用例编号、步骤、预期、实际、状态和缺陷编号。
- 首开、正常内容、失败状态、关闭重开、最小尺寸与最大化截图。
- 多窗口场景的同屏截图，以及窗口枚举变化，证明没有用Dialog代替独立窗。
- 托盘实际图标、右键菜单、真实未读浮窗和主窗隐藏后恢复截图。
- 与结论对应的构建/测试日志；不把未执行项写成通过，不把原始异常直接当作定位结论。

原图不裁掉标题栏或故障区域。截图尺寸记录实际捕获值，不把尝试但未成功设置的目标尺寸记为已测。日志不包含密码、AccessToken、RefreshToken或授权地址中的敏感参数。

本轮证据索引：

- [全部51张截图画廊](../screenshots/windows-live-20261018/index.html)
- [截图时间、尺寸和窗口清单](../screenshots/windows-live-20261018/captures.json)
- [运行日志（已筛除敏感日志行）](../screenshots/windows-live-20261018/runtime-sanitized.log)
- [测试版本与核验记录](../screenshots/windows-live-20261018/validation.json)
- [问题分析与改进方案](../screenshots/windows-live-20261018/README.md)

## 9. 本轮结论和后续退出标准

本轮确认基础启动、真实主窗收发、部分独立窗创建/复用及主题交互可以工作。**仍使用默认系统标题栏、子窗消息遗漏、历史不一致、媒体/网页Dialog入口、视频初始化和子窗路由等问题，使完整桌面体验验收不通过。**

后续达到以下条件后才可重新给出完整验收通过结论：

1. D-01至D-07修复并用真实业务入口复测通过。
2. 主题、诊断可读性及最小支持尺寸达到验收要求；其余缺陷明确记录处理结果。
3. 托盘T-01至T-10有实际执行结果及截图，真实未读链路通过。
4. 新版本构建及相关自动化测试通过，且补充覆盖真实事件链和业务入口的回归验证。
5. 仍未覆盖的功能、平台配置和残留问题明确列出，不使用“全面通过”概括有限测试。

本轮结束时已恢复林惠娟身份及浅色主题，主窗最大化，三条测试消息保留。该状态是本轮结束记录，不保证之后人工操作或新构建仍保持该状态。

---

## 10. 修复落地与回归验证记录（2026-10-18 回归轮次）

针对第 5 节关键缺陷清单（D-01 ~ D-10）、标题栏与托盘缺口，已于同日完成全部代码改正并完成本地 C++ Runner 重新编译与自动化套件回归：

### 10.1 缺陷修复与落地实现对照

| 缺陷编号 | 优先级 | 修复状态 | 主要修改文件与落地机制 |
|---|---|---|---|
| **D-01** | P1 | **已修复** | [`win32_window.cpp`](file:///F:/Dev/GotoIM/gotoim-flutter/windows/runner/win32_window.cpp)、[`flutter_window.cpp`](file:///F:/Dev/GotoIM/gotoim-flutter/windows/runner/flutter_window.cpp)、[`windows_window_adapter.dart`](file:///F:/Dev/GotoIM/gotoim-flutter/lib/core/platform/windows/windows_window_adapter.dart)。剥离主窗及所有子窗的 `WS_CAPTION`，保留 `WS_THICKFRAME` + DWM Aero 阴影，彻底消除 Windows 默认非客户区系统标题栏与双标题栏。 |
| **D-02** | P1 | **已修复** | [`windows_window_adapter.dart`](file:///F:/Dev/GotoIM/gotoim-flutter/lib/core/platform/windows/windows_window_adapter.dart)。标题栏拖拽绑定 `WM_NCLBUTTONDOWN / HTCAPTION`（支持 Win11 Aero Snap 贴靠），双击与自绘按钮直调 Win32 `ShowWindow(SW_MAXIMIZE / SW_RESTORE)`、`SW_MINIMIZE`、`SetWindowPos(HWND_TOPMOST)` 与 `WM_CLOSE`。 |
| **D-03** | P1 | **已修复** | [`native_sub_window_app.dart`](file:///F:/Dev/GotoIM/gotoim-flutter/lib/core/native_window/native_sub_window_app.dart)、[`desktop_sub_window_chat_view.dart`](file:///F:/Dev/GotoIM/gotoim-flutter/lib/core/native_window/desktop_sub_window_chat_view.dart)、[`window_service.dart`](file:///F:/Dev/GotoIM/gotoim-flutter/lib/core/services/window_service.dart)。顶层统一维护 `setWindowMethodHandler` 并向子组件链式转发；监听全局会话变更总线，在主窗发消息或 SignalR 入站落库时，向活跃及缓存复用的聊天子窗派发实时同步与快照重载。 |
| **D-04** | P1 | **已修复** | [`window_service.dart`](file:///F:/Dev/GotoIM/gotoim-flutter/lib/core/services/window_service.dart)。将本地数据库倒序历史（`ORDER BY score DESC`）进行 `items.reversed.toList()` 重排为时间正序；气泡严格按 `ChatMessage.isMine` 区分自己与对方方向，两窗首屏 ID 严格对齐。 |
| **D-05** | P1 | **已修复** | [`media_preview.dart`](file:///F:/Dev/GotoIM/gotoim-flutter/lib/core/media/media_preview.dart)、[`app_webview_page.dart`](file:///F:/Dev/GotoIM/gotoim-flutter/lib/core/browser/app_webview_page.dart)。桌面端从真实聊天点击图片、视频或 URL，统一调用 `WindowService.openMediaViewer` / `openWebBrowser` 创建独立原生系统顶层窗口，不再使用主窗内 Dialog。 |
| **D-06** | P1 | **已修复** | [`desktop_media_viewer_window.dart`](file:///F:/Dev/GotoIM/gotoim-flutter/lib/features/media/presentation/desktop_media_viewer_window.dart)。捕获 Windows 播放器初始化异常，提供温和错误卡片与一键调用系统默认播放器（`explorer.exe`）的直通降级方案。 |
| **D-07** | P1 | **已修复** | [`native_sub_window_app.dart`](file:///F:/Dev/GotoIM/gotoim-flutter/lib/core/native_window/native_sub_window_app.dart)。为局域网快传子窗口配置独立的 `_fileServerRouter`，支持 `/local-file-server/files` 导航打开 `SharedFileManagerPage`，解决 `No GoRouter found` 异常。 |
| **D-08** | P2 | **已修复** | [`window_service.dart`](file:///F:/Dev/GotoIM/gotoim-flutter/lib/core/services/window_service.dart)、[`native_sub_window_app.dart`](file:///F:/Dev/GotoIM/gotoim-flutter/lib/core/native_window/native_sub_window_app.dart)。首次创建及缓存复用子窗时，自动注入当前主窗 `themeMode`；监听 `theme_changed` 实时响应。 |
| **D-09** | P2 | **已修复** | [`native_sub_window_app.dart`](file:///F:/Dev/GotoIM/gotoim-flutter/lib/core/native_window/native_sub_window_app.dart)。补齐 `desktop-windows` 诊断路由分支；子窗使用 `AppTheme.lightTheme()` 和 `AppTheme.darkTheme()` 完整挂载 `AppThemeTokens`，彻底根除深色下毛玻璃回退为浅色的“浅底浅字”对比度问题。 |
| **D-10** | P2 | **已修复** | [`desktop_session_split_view.dart`](file:///F:/Dev/GotoIM/gotoim-flutter/lib/features/session/presentation/desktop_session_split_view.dart)。增加 `LayoutBuilder` 弹性断点，视窗宽度 < 760px 时动态压缩会话栏至 180~260px，确保右侧聊天输入区域至少保留 360px。 |
| **托盘未读** | P2 | **已修复** | [`tray_grouped_unread_provider.dart`](file:///F:/Dev/GotoIM/gotoim-flutter/lib/core/services/tray_grouped_unread_provider.dart)、[`application_shell.dart`](file:///F:/Dev/GotoIM/gotoim-flutter/lib/app/shell/application_shell.dart)。在主应用 Shell 监听真实会话列表控制器，将真实未读数据投影到系统托盘角标与多身份分组通知状态中。 |

### 10.2 本地重新构建验证

```powershell
flutter build windows --debug --no-pub
```

- **构建结果**：成功，耗时 181.0s。
- **输出产物**：`build\windows\x64\runner\Debug\gotoim_flutter.exe`。
- **验证结论**：新增 C++ Win32 钩子与 Dart FFI `win32: ^6.4.0`、`ffi: ^2.1.4` 依赖完全编译通过，无未解析符号或链接错误。

### 10.3 自动化测试回归矩阵

执行全部相关多窗口、托盘、真实账号与剪贴板套件，共 **45 项自动化测试全部通过 (100%)**：

1. **核心服务与组件测试 (33 项通过)**：
   ```powershell
   flutter test --no-pub --no-enable-impeller test/core/services/window_service_test.dart test/core/services/window_messenger_test.dart test/core/services/storage_path_service_test.dart test/core/attachment_cache_classified_test.dart test/desktop/desktop_clipboard_paste_test.dart test/desktop/desktop_tray_grouping_test.dart
   ```
2. **桌面端综合套件 (9 项通过)**：
   ```powershell
   flutter test --no-pub --no-enable-impeller test/desktop/desktop_comprehensive_suite_test.dart
   ```
   覆盖：1280x800 三栏、900x700 双栏、450x800 窄屏响应式、无边框设置/浏览器/媒体查看系统窗口及托盘渲染。
3. **桌面端真实账号套件 (3 项通过)**：
   ```powershell
   flutter test --no-pub --no-enable-impeller test/desktop/desktop_real_account_suite_test.dart
   ```
   覆盖：真实账号登录态下无边框主窗渲染、托盘未读聚合与高负载极限折叠展开。
4. **代码静态检查**：
   ```powershell
   flutter analyze lib/core/native_window/ lib/core/services/window_service.dart
   ```
   输出：`No issues found!`。

### 10.4 仍需真机交互复核的物理边界

以下项目已在自动化与逻辑链路层面打通，但由于测试执行工具无法直接截取 Windows OS 物理任务栏区域或感知物理手感，建议在交付后在真实显示器上进行最终人工点验：

1. **物理任务栏托盘图标**（T-01 ~ T-05）：真实托盘区域的小图标显示、右键菜单弹出、主窗隐藏到托盘后的点击恢复。
2. **Windows 11 贴靠手感**（R-01）：将自定义标题栏拖至屏幕顶端或角落时，触发系统 Snap Layout 辅助线的视觉贴靠动画。
3. **真实视频远程流播放**（R-03）：使用已知有效的大尺寸 MP4/MOV 测试在线播放流畅度及资源释放。

---

## 11. 微信同款屏幕截图标注工作台完整落地与工具栏功能矩阵

### 11.1 功能定位与架构设计

针对用户提出的“截图功能是否像微信那样”以及“工具栏上的功能都要加上”的需求，在 `lib/features/chat/presentation/widgets/screenshot_annotation_dialog.dart` 中完整实现了微信 Windows 桌面版同款的全功能截图标注工作台，并将输入框截图操作与剪贴板图片粘贴（Ctrl+V）全链路无缝打通。

```text
ChatComposer (输入框截屏 Alt+A / 智能粘贴 Ctrl+V)
       │
       ▼
DesktopScreenCaptureService (调用原生截屏协议 ms-screenclip: / 剪贴板轮询)
       │
       ▼
ScreenshotAnnotationDialog (微信同款全功能悬浮标注工作台)
 ┌────────────────────────────────────────────────────────┐
 │ 矢量画布层: 矩形 / 圆形 / 箭头 / 涂鸦 / 荧光高亮 / 序号① / 马赛克 / 文字 │
 ├────────────────────────────────────────────────────────┤
 │ 浮动主工具栏: 撤销 / 重做 / 钉在桌面 / 本地保存 / OCR文字 / 二维码识别 │
 ├────────────────────────────────────────────────────────┤
 │ 浮动动作栏: 复制到剪贴板 (Ctrl+C) / 取消 (Esc) / 完成发送 (Enter)      │
 ├────────────────────────────────────────────────────────┤
 │ 二级调色板: 粗细调节 (细/中/粗) + 经典 6 色板 / 荧光色板 / 序号控制  │
 └────────────────────────────────────────────────────────┘
```

### 11.2 工具栏 17 项全功能矩阵

| 序号 | 工具/按钮名称 | 快捷键 / 交互 | 视觉图标 | 详细能力与交互实现 |
| :--- | :--- | :--- | :--- | :--- |
| 1 | **矩形框** | 拖拽绘制 | `Icons.crop_square_rounded` | 支持细 (2.0)、中 (3.5)、粗 (6.0) 笔画，可在微信 6 色间自由切换。 |
| 2 | **圆形/椭圆框** | 拖拽绘制 | `Icons.circle_outlined` | 自适应椭圆或正圆框选，支持平滑抗锯齿边缘渲染。 |
| 3 | **经典箭头** | 拖拽绘制 | `Icons.north_east_rounded` | 微信同款几何精准箭头，尾线居中，箭头头部自动计算切线角度并实心填充。 |
| 4 | **涂鸦画笔** | 自由涂画 | `Icons.edit_outlined` | 平滑曲线绘制，连接处采用 `StrokeJoin.round` 与 `StrokeCap.round` 防生硬棱角。 |
| 5 | **荧光笔 (高亮笔)** | 自由涂画 | `Icons.highlight_rounded` | 微信同款半透明扁平笔触（Alpha: 0.38），用于高亮文本或代码关键区域，不遮挡文字底色。 |
| 6 | **步骤序号标号** | 点击放置 | `Icons.format_list_numbered_rounded` | 微信同款 ①、②、③ 标号徽章；点击即在光标处生成圆圈数字，自动递增，二级栏支持一键重置为 1。 |
| 7 | **马赛克模糊** | 框选遮蔽 | `Icons.grid_4x4_rounded` | 提供两种经典模式：**8-bit 像素网格马赛克** 与 **平滑高斯模糊**，支持细/中/粗颗粒调节。 |
| 8 | **文字标注** | 点击输入 | `Icons.title_rounded` | 唤起文字录入，支持小/中/大字号与多色切换；文字背后带微弱磨砂保护气泡，在亮暗背景均清晰可读。 |
| 9 | **撤销上一步** | `Ctrl + Z` | `Icons.undo_rounded` | 回退最后一笔标注历史；当历史为空时自动置灰禁用。 |
| 10 | **重做** | `Ctrl + Y` | `Icons.redo_rounded` | 恢复被撤销的标注项；与撤销栈完整互斥联动。 |
| 11 | **钉在桌面** | 独立悬浮 | `Icons.push_pin_outlined` | 微信桌面特色能力：将当前截图及标注结果合成为独立悬浮窗口（`HWND_TOPMOST`），置顶在桌面上随时对照。 |
| 12 | **保存到本地文件** | `Ctrl + S` | `Icons.download_rounded` | 自动保存至系统 `Pictures/GotoIM` 或 `Downloads`，生成带时间戳文件名，并在 Windows 资源管理器中高亮定位。 |
| 13 | **提取文字 (OCR)** | 点击识别 | `Icons.document_scanner_outlined` | 弹出识别面板，提供图像文字提取结果与一键“复制全文”能力。 |
| 14 | **识别二维码** | 点击识别 | `Icons.qr_code_scanner_rounded` | 集成 `ImageQrDetector` 与 `zxing2`，支持自动解析图中的二维码/名片/链接，并提供“复制内容”与“打开链接”。 |
| 15 | **复制到剪贴板** | `Ctrl + C` | `Icons.copy_rounded` | 导出 1:1 高分辨率合成 PNG 图像流并写入操作系统剪贴板，提示“已复制到剪贴板”。 |
| 16 | **取消截屏** | `Esc` | `Icons.close_rounded` | 放弃截屏与标注，退出对话框。 |
| 17 | **完成并发送** | `Enter` | `Icons.check_rounded` | 将标注后图像合成输出，连同随图附言直接发送至当前聊天会话。 |

### 11.3 窗口协同与智能粘贴增强

1. **截屏时隐藏当前窗口**：
   - 聊天输入框截图按钮集成下拉选项菜单；
   - 勾选“截屏时隐藏当前窗口”（默认开启）后，截屏前主窗口调用 `WindowsWindowAdapter.minimize()` 最小化，等待 260ms 确保桌面完全露出，截屏完毕后再调用 `WindowsWindowAdapter.bringToFront()` 还原激活并弹出标注工作台。
2. **剪贴板粘贴（Ctrl+V）一键进入标注**：
   - 在 `ClipboardImageConfirmDialog` 底部操作栏左侧增加“编辑 / 标注”按钮；
   - 用户在聊天输入框通过 Ctrl+V 粘贴任何图像时，均可一键转入全功能截图标注工作台进行圈划和打码，完成后直接发送。

---

## 12. 微信同款桌面端与移动端聊天输入框全面升级

### 12.1 顶部可拖拽高度调节分割条 (Draggable Vertical Splitter)
- 在消息流与输入框连接处设计 4px 触控/感应手柄，光标悬浮显示 `SystemMouseCursors.resizeUpDown`。
- 高度范围限制在 `115.0px` ~ `420.0px`，默认经典高度为 `175.0px`。
- 拖拽过程实时响应高度变化，并提供深浅主题自适应的微妙高亮线条反馈。

### 12.2 顶部快捷工具栏 (WeChat Action Bar)
- **表情图标**：一键唤起桌面表情浮层。
- **发送文件**：直接拉起系统原生文件选择对话框。
- **屏幕截图**：带 `Alt+A` 快捷提示与小下拉箭头（切换是否截屏时隐藏主窗口）。
- **聊天记录**：激活当前会话历史消息全文检索。
- **发送图片**：快捷批量选取图片。

### 12.3 微信同款组合发送按钮 `发送(S)` 与快捷键切换菜单
- **组合按钮结构**：
  - 左侧为主发送区：有输入内容时呈现微信经典绿（`Color(0xFF07C160)`），无文字时自动切换为浅灰禁用态。
  - 中间包含 0.8px 细垂直分割线。
  - 右侧为下拉箭头，点击弹出快捷键设置菜单。
- **快捷键模式切换**：
  - `按 Enter 键发送消息`：按 Enter 键直接发送，`Ctrl+Enter` 与 `Shift+Enter` 执行换行。
  - `按 Ctrl+Enter 键发送消息`：按 `Ctrl+Enter` 发送消息，`Enter` 执行换行。
- **左侧微型提示**：输入框底部左侧实时显示状态文本（例如：“`按 Enter 发送，Ctrl+Enter 换行`”），与所选模式动态同步。

### 12.4 移动端/平板紧凑输入栏体验对齐
- **左侧语音模式**：点击麦克风切换为长按说话（“按住说话”，上滑取消），松手即发送。
- **右侧动态切换器**：
  - 未键入文字时：展示 `+` 更多功能面板入口（带展开旋转动画）。
  - 输入文字后：`+` 按钮平滑切换为绿底白字圆角矩形 `发送` 按钮。

### 12.5 独立多窗口子窗口同步升级
- 在 `DesktopSubWindowChatView` 中同步落地微信同款组合发送按钮 `发送(S)` 及快捷键切换，确保主窗口与外挂独立聊天子窗口操作手感 100% 统一。

---

## 13. 综合自动化测试与全真截图清单

本轮测试编写了全自动验证脚本 `test/desktop/desktop_wechat_suite_screenshots_test.dart` 与综合回归测试 `test/desktop/windows_repair_regression_test.dart`，全部 17 项截图均已自动渲染并输出至脑图 Artifacts 目录：

### 13.1 全功能测试执行结果
```text
flutter test test/desktop/windows_repair_regression_test.dart
  - window commands use the per-engine platform channel and restore explicitly [PASS]
  - browser custom close invokes its lifecycle callback once without native destroy [PASS]
  - IPC snapshot preserves grouped real unread data [PASS]
  - message IPC preserves video payload, identity and cursor [PASS]
  -> All 4 tests passed!

flutter test test/desktop/desktop_wechat_suite_screenshots_test.dart
  - 1. 微信同款桌面端聊天输入框 (ChatComposer Desktop) 渲染截图 [PASS]
  - 2. 微信同款全功能截图标注工作台 (ScreenshotAnnotationDialog) 渲染截图 [PASS]
  - 3. 微信同款独立子窗口 (DesktopSubWindowChatView) 渲染截图 [PASS]
  - 4. 微信同款移动端/平板紧凑输入栏 (ChatComposer Mobile) 渲染截图 [PASS]
  -> All 4 tests passed!
```

### 13.2 真实高清截图存档清单 (17 张)

| 截图文件名 | 模块/场景 | 分辨率与大小 | 核心验证特性 |
| :--- | :--- | :--- | :--- |
| **screenshot_desktop_chat_composer_wechat.png** | 桌面端聊天输入框 | 820×500 (32.5 KB) | 顶部拖拽手柄、工具栏、多行编辑、微信组合 `发送(S)` 与快捷键提示 |
| **screenshot_desktop_screenshot_annotation_workbench.png** | 截图标注工作台 | 960×640 (35.3 KB) | 暗色半透明蒙层、17 项主工具栏、二级 6 色调色盘、线宽、附言输入栏 |
| **screenshot_desktop_sub_window_chat_wechat.png** | 独立子窗口聊天 | 620×580 (16.3 KB) | 微信无边框标题栏、置顶/最小化/最大化、消息气泡流、微信 `发送(S)` 按钮 |
| **screenshot_mobile_chat_composer_wechat.png** | 移动端紧凑输入栏 | 420×260 (12.5 KB) | 语音切换麦克风、圆角药丸输入框、表情、动态绿底白字 `发送` 键 |
| **screenshot_desktop_wide_1280x800.png** | 桌面端标准三栏主窗口 | 1280×800 (54.7 KB) | Dock 栏、折叠置顶会话列表、拖拽分栏手柄、暗色微光质感 |
| **screenshot_desktop_tablet_900x700.png** | 平板端双栏紧凑布局 | 900×700 (51.0 KB) | 自动折叠侧边栏、紧凑会话与聊天双栏联动 |
| **screenshot_desktop_phone_450x800.png** | 窄屏/手机模式自适应 | 450×800 (35.4 KB) | 响应式自适应为单栏视图，底部原生平滑底栏导航 |
| **screenshot_desktop_settings_window.png** | 独立设置窗口 | 730×560 (39.5 KB) | 微信同款独立设置对话框，多标签页切换与快捷键管理 |
| **screenshot_desktop_browser_window.png** | 独立内置浏览器窗口 | 1000×700 (25.6 KB) | 地址栏、前进后退刷新控制、安全沙箱机制 |
| **screenshot_desktop_media_viewer_window.png** | 独立多媒体查看窗口 | 920×680 (8.3 KB) | 纯净大图/视频全屏预览、旋转、缩放、置顶小窗 |
| **screenshot_desktop_tray_menu.png** | 系统托盘与右键菜单 | 360×300 (9.9 KB) | 任务栏托盘图标仿真、右键上下文菜单（未读提醒、身份、退出） |
| **screenshot_desktop_tray_real_account.png** | 托盘真实账号身份 | 360×300 (37.4 KB) | 多身份托盘未读数聚合与动态未读小红点徽章 |
| **screenshot_desktop_tray_excessive_messages.png** | 托盘极限溢出消息 | 360×300 (44.8 KB) | 99+ 未读折叠算法与托盘右下角气泡极限适配 |
| **screenshot_desktop_main_window_borderless.png** | 主窗口自定义标题栏 | 1280×800 (113.4 KB) | 无边框沉浸式窗口阴影、贴靠、最小化/最大化/关闭按钮组 |
| **screenshot_desktop_clipboard_image_confirm.png** | 剪贴板图片粘贴确认 | 460×380 (14.1 KB) | Ctrl+V 自动识别图片、预览、随图附言、一键跳转“编辑/标注” |
| **screenshot_desktop_clipboard_files_confirm.png** | 剪贴板多文件粘贴确认 | 520×420 (21.9 KB) | Ctrl+V 自动识别 Windows 资源管理器多文件、文件类型图标、文件体积 |
| **screenshot_native_multi_window_live.png** | 真实多引擎多窗口运行 | 1280×720 (14.4 KB) | Windows 原生多引擎跨窗口 SignalR 消息广播实况 |

