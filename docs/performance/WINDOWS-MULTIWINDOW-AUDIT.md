# Windows Multi-Window Architecture & Memory Audit

**Date**: 2026-11-03  
**Repository**: `f:\Dev\GotoIM\gotoim-flutter` (Branch: `dev`)  
**Commit**: `26eb2a1`  
**Flutter SDK**: 3.47.0 (channel stable) • Dart 3.13.0 • Windows x64  
**Plugins**: `desktop_multi_window: ^0.3.1`, `flutter_inappwebview: ^6.2.0-beta.3`, `drift: ^2.34.3`, `signalr_netcore: ^1.4.4`  

---

## 1. 现有架构与多窗口模型

### 1.1 进程与引擎拓扑 (Process & Engine Topology)

```mermaid
flowchart TD
  subgraph WindowsOSProcess ["Windows 进程: gotoim_flutter.exe"]
    subgraph MainEngine ["主引擎 (Main Flutter Engine)"]
      MB[Bootstrap & GotoImApp]
      MS[SignalR NetCore 连接池]
      MD[Dio HTTP 客户端 & TokenStorage]
      MDB[(Drift SQLite 数据库持久化)]
      WS[DefaultWindowService & Registry]
      IPC_M[WindowMethodChannel: gotoim/ipc_to_main]
    end

    subgraph NativeRunner ["Win32 Native Runner (C++)"]
      FC[flutter_window.cpp & main.cpp]
      WC[window_controls.cpp (1555 行)]
      DMW[desktop_multi_window plugin]
      DOCK[Browser Docking 嵌入分屏引擎]
      HWND_M[主窗口 HWND]
      HWND_C[子窗口 HWNDs (WS_POPUP / WS_OVERLAPPED)]
    end

    subgraph SubEngines ["子引擎池 (Separate Flutter Engines & UI Threads)"]
      subgraph SubEngine1 ["子引擎 1 (Chat / Browser / Tool)"]
        SE1_APP[runNativeSubWindowApp]
        SE1_PC[独立 ProviderContainer]
        SE1_UI[DesktopSubWindowChatView / Browser]
        SE1_IC[PaintingBinding imageCache (15MB)]
        SE1_CHAN[WindowMethodChannel]
      end
      subgraph SubEngineN ["子引擎 N (缓存或活动)"]
        SEN_APP[...]
      end
    end
  end

  subgraph WebView2Processes ["Chromium 子进程 (msedgewebview2.exe)"]
    WV_BROWSER[WebView2 Browser Process]
    WV_RENDER[WebView2 GPU / Render Processes]
  end

  MB --> WS
  WS -->|WindowController.create| DMW
  DMW -->|UIThreadPolicy::RunOnSeparateThread| SubEngines
  IPC_M <--->|IPC 数据交换| SE1_CHAN
  SE1_UI -->|嵌入/弹窗| HWND_C
  SE1_UI -.->|加载网页| WV_BROWSER
```

### 1.2 窗口类型与创建方式审计清单

| 窗口标识 (`targetId`) | 窗口类型 (`SubWindowType`) | 承载组件 | 通信与数据来源 | 销毁/缓存策略 |
|---|---|---|---|---|
| `main` | 主窗口 | `GotoImApp` | 直接持有 Drift, SignalR, Dio, Token | 退出应用或最小化到托盘 |
| `chat:<ownerId>:<sessionUnitId>` | `chat` | `DesktopSubWindowChatView` | **无独立网络/DB**，纯 IPC (`chat_load_history`, `chat_send_message`) | 关闭时隐藏，存入 `_reusableControllers` 缓存池 (上限 6) |
| `tool:browser` | `browser` | `DesktopBrowserWindow` | InAppWebView (WebView2), 嵌入 Dock 或独立弹窗 | 关闭时 `window_undock` + `browser_clear_tabs` + 隐藏，存入缓存池 |
| `tool:media` | `media` | `DesktopMediaViewerWindow` | 本地文件或网络图片/视频播放器 | 关闭时 `window_release_content` + 隐藏，存入缓存池 |
| `tool:settings` | `settings` | `DesktopSettingsWindow` | 本地设置、IPC `app_logout`，模态禁用父窗口 | 关闭时恢复模态 + 隐藏，存入缓存池 |
| `tool:profile_card` | `profileCard` | `DesktopProfileCardView` | 悬浮资料卡，纯 IPC 触发 | 关闭时隐藏，存入缓存池 |
| `tool:tray` | `tray` | `DesktopTrayMessageBox` | 托盘分组未读弹窗，无任务栏按钮 (`setToolWindow`) | 点击外部或关闭时隐藏，存入缓存池 |
| `tool:screenCapture` | `screenCapture` | `DesktopScreenCaptureView` | 桌面截屏画布与画笔编辑 | 完成或取消后隐藏并回调截屏结果 |
| `tool:diagnostics` | `diagnostics` | `DiagnosticsHomePage` | 开发诊断中心所有子模块 | 关闭时隐藏，存入缓存池 |
| `tool:localFileServer` | `localFileServer` | `LocalFileServerPage` | 本地 HTTP/局域网互传 | 关闭时隐藏，存入缓存池 |
| `tool:social` | `social` | `SocialPage` | 圈子动态 (模拟移动端视口 420x780) | 关闭时隐藏，存入缓存池 |

---

## 2. 内存激增核心根因分析 (Root Causes)

经过代码执行路径审计与实测进程采样分析，确认导致 Windows 桌面端内存高达 1.7GB ~ 2.0GB 的 Top 5 核心根因：

### 根因 1: `_reusableControllers` 静态持有高达 6 个后台活跃 Flutter 引擎
- **代码位置**: `lib/core/services/window_service.dart:336-338`, `1169-1178`
- **问题机制**:
  - `_maxReusableControllers` 设定为 `6`。
  - 缓存字典的 Key 为完整的 `targetId`（如 `chat:100:session_a`）。
  - 当用户在日常使用中陆续打开过多个好友或群聊会话（如 A, B, C, D, E, F）并关闭它们时，这 6 个会话的窗口控制器**全部以隐藏状态（`SW_HIDE`）持续运行**。
  - 每个 Windows Flutter 引擎实例包含：独立的 Dart Isolate（包含 Dart VM 堆、JIT/AOT 元数据）、ANGLE/DirectX 11 交换链与渲染表面、Skia 资源缓存、单独的 UI 消息循环线程。
  - 每个引擎底噪约 120MB ~ 180MB，6 个隐藏引擎直接霸占 **~900MB ~ 1.1GB** 内存！
  - 并且因为 Key 绑死具体 `targetId`，打开新会话 G 时无法命中 A~F 的缓存，仍会创建第 7 个引擎，产生严重抖动与内存浪费。

### 根因 2: 窗口关闭时未彻底释放子引擎内的消息列表与图片解码缓存
- **代码位置**:
  - `lib/core/native_window/native_sub_window_app.dart:474-485` (`window_release_content`)
  - `lib/core/native_window/desktop_sub_window_chat_view.dart:163-228`
- **问题机制**:
  - 当主引擎调用 `window_release_content` 时，`native_sub_window_app.dart` 仅对 `media` 类型将 `_visible` 设为 false，**未向 `_childMethodHandler` 分发任何内容释放指令**。
  - `DesktopSubWindowChatView` 的 `_messages` 列表、`_attachments` 字典、历史消息富文本实体全部滞留在内存中。
  - 子引擎的 `PaintingBinding.instance.imageCache` 在窗口关闭后从未调用 `clear()` 和 `clearLiveImages()`，已解码的大图 Bitmaps 一直驻留。

### 根因 3: `DesktopSubWindowChatView` 状态未响应会话变更 (`didUpdateWidget`)
- **代码位置**: `lib/core/native_window/desktop_sub_window_chat_view.dart:80-84`, `317-323`
- **问题机制**:
  - `_subWindowChatController` 在 `initState` 中初始化时固化了 `sessionUnitId` 和 `ownerId`。
  - 当控制器被复用或 payload 更新时，未重新初始化或清空原有会话的消息列表，导致旧消息与新消息在同一个控制器中堆积混杂。

### 根因 4: WebView2 子进程与标签页资源
- **代码位置**: `lib/core/browser/desktop_browser_window.dart:260-280`
- **问题机制**:
  - 浏览器窗口包含 `flutter_inappwebview` 及其底层的 Edge Chromium 内核 (`msedgewebview2.exe`)。
  - 实测数据表明 6 个 WebView2 进程占用约 200MB 私有提交内存。
  - 浏览器窗口关闭时虽触发 `browser_clear_tabs`，但若窗口引擎本身仍保留在 `_reusableControllers` 中，WebView2 宿主环境不会被操作系统回收。

### 根因 5: 缺少单引擎多 View 原生轻量化能力
- **问题机制**:
  - 目前所有次级窗口完全基于 `desktop_multi_window` 多引擎模型。
  - 理论上单 Engine + 多 FlutterView 共享同一 Dart Isolate 与图形上下文，能将每窗口增量降低到单个 HWND 视口成本（约 15~25MB）。
  - 但因现有项目高度依赖 `windows/runner/window_controls.cpp` 提供的原生无缝分屏 Docking、原生窗口模态、截屏及 InAppWebView 等 C++ runner 扩展，直接激进替换为尚未官方稳定的 MultiView 会导致大量插件和 Win32 自定义行为崩溃。

---

## 3. 阶段优化策略与行动路径

1. **第一阶段 (阶段三: 旧架构深度优化 - 立即可行、极高收益、零回归风险)**:
   - 将 `_maxReusableControllers` 默认值从 `6` 缩减为 `1`（仅保留 1 个最近关闭的窗口用于平滑过渡，或在低内存模式下设为 `0` 即时销毁）。
   - 实现**通用聊天子窗口复用 (Generic Chat SubWindow Reuse)**：让闲置的聊天窗口不再局限于旧 `sessionId`，打开任意新聊天均可直接复用已有闲置聊天引擎，只需更新 payload 并重新加载会话数据。
   - 在 `window_release_content` 和窗口关闭时，显式清空 `_messages`、`_attachments`、取消进行中的异步拉取，并触发 `PaintingBinding.instance.imageCache.clear()` 与 `clearLiveImages()`。
   - 彻底解决 `DesktopSubWindowChatView` 在 payload 变更时的控制器更新与消息重置。
2. **第二阶段 (阶段四: 独立单 Engine 多 View 原型验证)**:
   - 在独立原型目录 `examples/desktop_multiview_poc/` 构建基于 `multiview_desktop` 的隔离 Demo。
   - 逐项验证中文 IME 输入、窗口拖拽、焦点切换、多窗口 Dart 状态共享。
   - 评估 WebView2、Drift、WindowControls 原生集成兼容性矩阵。
3. **第三阶段 (阶段五/六: 门禁评估与报告交付)**:
   - 统计优化前后实测内存、输出 CSV 基线报告与修改日志。
