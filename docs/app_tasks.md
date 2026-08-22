# 应用级独立多任务容器指南 (App Tasks & MiniApp)

GotoIM 提供了类似微信小程序的独立多任务运行架构：
- **主应用与子任务隔离**：主聊天窗口与每个动态应用运行在独立的系统任务（Task）与 FlutterEngine 中；
- **最近任务独立卡片**：在 Android 设备上，点击工作台应用可在系统“最近任务（Recents）”中展示为独立卡片；
- **智能复用**：同一个应用再次打开时默认切换回已有 Task，不重复创建；
- **轻量化引擎组**：基于 `FlutterEngineGroup`，每个独立任务仅占用约 180 KB 增量引擎内存；
- **全平台平滑降级**：iOS、macOS、Windows、Linux 及 Web 平台无缝降级为应用内容器，API 100% 统一。

---

## 1. 典型使用场景

### 场景 1：多任务并行与聊天/业务协同
- **痛点**：客服、销售人员或运营在沟通时，需要边看客户资料（CRM）、边查订单、边发聊天消息。单页面内跳转会导致聊天被遮挡，频繁返回容易丢失未发消息。
- **解决方案**：在 Android 端，CRM 以独立 Task 运行。用户在底部通过手势（或分屏）可瞬间在“GotoIM 聊天”与“CRM 系统”之间平滑滑动切换，如同操作两个独立 App。

### 场景 2：消息 Deep Link 与状态保持
- **痛点**：用户在聊天中收到审批卡片 `https://oa.gotoim.com/approval/999`，点击后若 OA 已在后台运行，不希望丢失此前正在填写的表单草稿。
- **解决方案**：通过 `AppTaskManager.openMiniApp(appId: 'oa', url: '...', reuseExisting: true)`，系统自动激活后台已有的 OA Task，并通过 `onNewIntent` 实时向 WebView 推送新 URL 进行内部跳转，保留已有表单与状态。

### 场景 3：单点故障隔离与后台资源节约
- **痛点**：复杂 Web 页面容易因内存泄漏或异常卡死影响整个 IM 主进程。
- **解决方案**：MiniApp 运行在独立 FlutterEngine 和独立的 Activity 中，MiniApp 崩溃或关闭完全不影响主 IM 进程；MiniApp 独立入口 `miniAppMain` 不启动 SignalR 长连接与后台同步任务，节约系统电量与内存。

---

## 2. 全平台支持矩阵与兼容策略

### 平台支持矩阵

| 平台 | 容器能力（WebView + JSBridge） | 运行形态 | 系统级独立多任务卡片 | 兼容策略 / 说明 |
| :--- | :---: | :--- | :---: | :--- |
| **Android (手机/平板)** | ✅ **完全支持** | 独立 Task（`MiniAppActivity`） | ✅ **完全支持** | 在系统“最近任务”独立显示卡片，按 `appId` 复用 |
| **iOS (iPhone)** | ✅ **完全支持** | 应用内页面（`MaterialPageRoute`） | ❌ **不支持（系统限制）** | 自动平滑退化为应用内新页面，顶部提供返回与关闭 |
| **iPadOS** | ✅ **完全支持** | 应用内页面（预留 Scene 扩展） | 🔄 **预留架构** | 接口预留后续扩展为 iPadOS Multi-Scene 独立分屏/多窗口 |
| **macOS / Windows** | ✅ **完全支持** | 应用内页面（预留 Window 扩展） | 🔄 **预留架构** | 接口预留后续通过 `WindowService` 弹出独立桌面窗口 |
| **Linux** | ✅ **完全支持** | 应用内页面 | 🔄 **预留架构** | 桌面级平滑降级 |
| **Web** | ✅ **完全支持** | 路由容器内加载 | ❌ **不适用** | 单页面内路由承载 |

### 为什么 iOS 无法实现系统独立任务卡片？
1. **iOS 沙盒与多任务机制限制**：苹果 iOS 系统严格规定 iPhone 在 App Switcher（后台任务切换器）中一个 App 只能拥有一个系统卡片，未向普通应用开放类似 Android Document Task 的系统级多卡片 API。
2. **微信/行业通用方案**：微信 iOS 版小程序也是在应用内通过多页面/悬浮窗管理，无法在 iOS 系统后台卡片中独立出现。
3. **GotoIM 统一抽象**：GotoIM 封装了统一的 `AppTaskManager`，在 iOS 端自动通过 `StubAppTaskManager` 平滑推入 `MiniAppHostPage`，业务层调用完全无需 `if (Platform.isAndroid)` 判断。

---

## 3. 使用方式与 API 说明

### 3.1 打开 MiniApp (`openMiniApp`)

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gotoim_flutter/core/services/task/app_task_manager.dart';

class OrderCardWidget extends ConsumerWidget {
  const OrderCardWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FilledButton(
      onPressed: () async {
        final taskManager = ref.read(appTaskManagerProvider);
        
        await taskManager.openMiniApp(
          MiniAppTaskRequest(
            appId: 'crm',                            // 必填：应用唯一标识（用于去重与复用）
            title: 'CRM 客户管理',                    // 必填：任务卡片标题
            url: Uri.parse('https://crm.gotoim.com'), // 必填：目标 Web URL
            iconUrl: 'https://cdn.gotoim.com/crm.png', // 可选：应用图标
            reuseExisting: true,                     // 可选：默认 true（复用已有 Task）
            arguments: {'source': 'chat_message'},   // 可选：透传业务参数
          ),
        );
      },
      child: const Text('查看客户订单'),
    );
  }
}
```

### 3.2 关闭当前任务 (`closeCurrentTask`)

在小程序容器或其自定义功能栏中提供“退出应用”操作：

```dart
final taskManager = ref.read(appTaskManagerProvider);

// Android: 调用 finishAndRemoveTask() 结束并移除系统任务卡片
// iOS/其它平台: 执行 Navigator.pop() 返回上一级
await taskManager.closeCurrentTask();
```

---

## 4. 技术架构与核心机制

```text
┌─────────────────────────────────────────────────────────────┐
│                       GotoIM Flutter                        │
│                                                             │
│   业务页面 / 工作台                                         │
│        │                                                    │
│        ▼                                                    │
│   AppTaskManager.openMiniApp(MiniAppTaskRequest)            │
│        │                                                    │
│   ┌────┴───────────────────────────┐                        │
│   │ (Android)                      │ (iOS / Web / Desktop)  │
│   ▼                                ▼                        │
│ MethodChannel                  StubAppTaskManager          │
│ ('com.gotoim.task_manager')    (MaterialPageRoute 降级)      │
└────────┬───────────────────────────────────┬────────────────┘
         │                                   │
         ▼                                   ▼
┌──────────────────┐               ┌──────────────────┐
│  Android Native  │               │   Flutter 内部   │
│  MainActivity    │               │  MiniAppHostPage │
│        │         │               └──────────────────┘
│  startActivity   │
│  (NEW_DOCUMENT)  │
│        │         │
│        ▼         │
│  MiniAppActivity │
│  (FlutterEngine) │
└────────┬─────────┘
         │ (createAndRunEngine with "miniAppMain")
         ▼
┌─────────────────────────────────────────────────────────────┐
│                 MiniApp FlutterEngine                       │
│                                                             │
│   miniAppMain() -> miniAppBootstrap()                       │
│        │                                                    │
│        ▼                                                    │
│   MiniAppApp (轻量级独立 MaterialApp)                       │
│        │                                                    │
│        ▼                                                    │
│   MiniAppHostPage (InAppWebView + JSBridge + 返回控制)       │
└─────────────────────────────────────────────────────────────┘
```

### 4.1 Task Identity 与 URL 解耦
- **Task Identity**：`gotoim://miniapp/{appId}`（写入 `Intent.data`）
- **页面 URL**：`https://crm.gotoim.com/order/123`（写入 `Intent.putExtra("url", ...)`）
- **复用机制**：配合 `AndroidManifest.xml` 中 `documentLaunchMode="intoExisting"` 与 `FLAG_ACTIVITY_NEW_DOCUMENT`，系统根据 `Intent.data`（即 `appId`）判断任务唯一性，即使在内部网页发生了多级跳转，再次打开该应用时依然切回现有 Task，不会出现重复卡片。

### 4.2 FlutterEngineGroup 轻量化多引擎
- 在 `GotoIMApplication.kt` 中持有单例 `FlutterEngineGroup`；
- 每个 `MiniAppActivity` 通过 `engineGroup.createAndRunEngine` 运行独立引擎，共享底层 Dart VM、Isolate Group、GC 内存与线程池，新引擎内存增量仅约 **180 KB**；
- 独立入口 `miniAppMain` 仅启动基础主题、网络与 WebView 容器，**不重复启动 SignalR 长连接、消息同步与未读数轮询**。

### 4.3 渲染稳定性（TextureView + Skia）
- 为防止多 Activity 与 WebView 混合合成（Hybrid Composition）在部分 GPU 驱动下发生 EGL 驱动上下文竞争（`EGL_BAD_ACCESS 12290`），`MiniAppActivity` 和 `MainActivity` 统一配置了 `RenderMode.texture`；
- `AndroidManifest.xml` 声明 Android 端渲染后端为稳定的 Skia 模式，保证多任务卡片流畅无黑屏。

### 4.4 返回键优先级
在 `MiniAppHostPage` 中完整接管返回键与手势：
1. **第一优先级**：若 WebView 内部浏览历史可以后退（`canGoBack == true`），执行 `InAppWebViewController.goBack()`；
2. **第二优先级**：已退至网页根路径时，按返回键或点击右上角关闭按钮，调用 `closeTask()` → Android Native `finishAndRemoveTask()` 优雅关闭并清理该 Task 卡片。

---

## 5. 开发诊断中心测试指引

在 Debug 模式下访问 **“开发诊断中心 → 应用级任务栈”**（`/diagnostics/app-task`）：
1. **平台能力检测**：顶部实时显示当前平台是否支持系统级独立任务卡片；
2. **多任务并行测试**：点击 `MiniApp A`、`MiniApp B`，按多任务键检查后台是否显示独立卡片；
3. **任务复用测试**：再次点击 `MiniApp A`，验证是否直接切回已有卡片且不增加新卡片；
4. **动态应用测试**：点击 `+ Cloud Drive`、`+ ERP` 动态添加新应用，验证零修改 Manifest 即可拉起独立任务；
5. **耗时与日志**：面板实时显示每次任务调用的执行耗时与详细结果。
