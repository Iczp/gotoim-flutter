# 工作台动态应用与 Android 独立任务栈

GotoIM 提供了类似微信小程序的轻量级多应用容器体验：
- **GotoIM 主应用**保持一个独立的系统任务；
- **工作台应用**由服务端动态返回，不写死在客户端；
- **独立任务栈**：在 Android 设备上，点击工作台应用可在系统“最近任务（Recents）”中展示为独立卡片；
- **任务复用**：同一个应用再次打开时默认切换回已有 Task，不重复创建；
- **零发版扩展**：新增或修改工作台应用不需要修改 Android Manifest 或重新发版；
- **跨平台平滑降级**：iOS、macOS、Windows、Linux 及 Web 平台降级为应用内页面/容器打开，保持业务代码调用一致。

---

## 1. 核心架构

```text
┌─────────────────────────────────────────────────────────────┐
│                       GotoIM Flutter                        │
│                                                             │
│   WorkbenchPage / 业务页面                                   │
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
│   MiniAppApp (Lightweight MaterialApp)                      │
│        │                                                    │
│        ▼                                                    │
│   MiniAppHostPage (InAppWebView + JSBridge + Back/Close)   │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. 数据模型

### `WorkbenchApp`

定义工作台应用的元数据：

```dart
class WorkbenchApp {
  final String appId;            // 唯一应用标识，例如 'crm', 'oa'
  final String name;             // 应用显示名称
  final Uri url;                 // 实际加载的 Web URL
  final String? iconUrl;         // 图标地址
  final WorkbenchAppType type;   // web | flutter | native
  final AppOpenMode openMode;    // systemTask | page | current
  final bool reuseExisting;      // 是否复用已有任务（默认 true）
  final MiniAppAuthMode authMode;// none | silent | userAuthorization
  final int sort;                // 排序权重
  final bool enabled;            // 是否启用
}
```

### `MiniAppTaskRequest`

传递给 `AppTaskManager.openMiniApp` 的请求载荷：

```dart
class MiniAppTaskRequest {
  final String appId;
  final String title;
  final Uri url;
  final String? iconUrl;
  final bool reuseExisting;
  final Map<String, String>? arguments;
}
```

---

## 3. Android Task 创建与复用机制

### Task Identity 与 URL 解耦

Task 唯一身份绑定于 `appId`，而不是当前打开的网页 URL：

- **Task Identity**：`gotoim://miniapp/{appId}`（设置到 `Intent.data`）
- **页面 URL**：`https://crm.gotoim.com/customer/123`（通过 `Intent.putExtra("url", ...)` 传递）

### Manifest 配置

在 `AndroidManifest.xml` 中仅需声明一次通用的 `MiniAppActivity`：

```xml
<activity
    android:name=".task.MiniAppActivity"
    android:exported="false"
    android:launchMode="standard"
    android:documentLaunchMode="intoExisting"
    android:excludeFromRecents="false"
    android:autoRemoveFromRecents="false"
    android:theme="@style/LaunchTheme"
    android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
    android:hardwareAccelerated="true"
    android:windowSoftInputMode="adjustResize">
    <meta-data
        android:name="io.flutter.embedding.android.NormalTheme"
        android:resource="@style/NormalTheme" />
</activity>
```

### 启动标志位与复用逻辑

1. `MainActivity` 启动 `MiniAppActivity` 时：
   - 添加 `Intent.FLAG_ACTIVITY_NEW_DOCUMENT`；
   - 设置 `intent.data = Uri.parse("gotoim://miniapp/$appId")`；
   - 结合 `documentLaunchMode="intoExisting"`，系统会首先根据 `Intent.data` 匹配现有 Task 列表。
2. **首次打开**：创建新的 Document Task 卡片；
3. **再次打开（相同 appId）**：直接切回已有 Task，并通过 `onNewIntent` 派发最新参数，不重复新建卡片。

---

## 4. FlutterEngine 生命周期与轻量化

### `FlutterEngineGroup`

在 `GotoIMApplication.kt`（继承 `FlutterApplication`）中持有单例 `FlutterEngineGroup`：
- 每个 `MiniAppActivity` 通过 `engineGroup.createAndRunEngine` 创建独立的 `FlutterEngine`；
- 多引擎共享底层的 Dart VM、Isolate Group、GC 与底层线程池，每个新引擎内存开销仅约 **180 KB**。

### MiniApp 独立入口 `miniAppMain`

MiniApp 运行在独立的 Dart Entrypoint：

```dart
@pragma('vm:entry-point')
Future<void> miniAppMain() async {
  runZonedGuarded(() async {
    await miniAppBootstrap();
  }, (error, stackTrace) {
    debugPrint('MiniApp unhandled error: $error\n$stackTrace');
    runApp(BootstrapErrorApp(error: error, stackTrace: stackTrace));
  });
}
```

MiniApp 只初始化：
- 主题 / 语言配置
- HTTP 基础与环境配置
- WebView 与 JSBridge 调度器

**明确不启动**：
- SignalR 主长连接
- IM 本地消息与会话同步队列
- 未读数轮询 Job
- 主应用全局后台任务

---

## 5. 返回与关闭优先级

MiniApp 容器页面（`MiniAppHostPage`）拦截物理返回与导航返回：

1. **WebView 内部可后退**：优先触发 `InAppWebViewController.goBack()`；
2. **已到网页根路径 / 不可后退**：调用 `closeTask()` → Android Native `finishAndRemoveTask()`；
3. **点击右上角关闭按钮**：直接执行 `closeTask()` 退出并从最近任务中移除。

---

## 6. 开发诊断中心测试

进入 **“开发诊断中心 → 应用级任务栈”**（`/diagnostics/app-task`）：

1. **手动参数测试**：输入任意 `appId`、`title`、`url`、`reuseExisting`，点击“打开独立 Task”；
2. **快捷测试**：点击 `MiniApp A`、`MiniApp B` 或 `随机 AppId`，验证多任务并行；
3. **动态应用测试**：点击 `+ Cloud Drive`、`+ ERP`、`+ Project` 动态添加应用到工作台，验证零修改 Manifest 即可启动独立任务；
4. **状态与异常诊断**：展示耗时、返回结果及异常调用栈。

---

## 7. 平台兼容与降级

| 平台 | 任务模式 | 实现机制 |
| :--- | :--- | :--- |
| **Android** | 系统级独立 Task 卡片 | `MiniAppActivity` + `FLAG_ACTIVITY_NEW_DOCUMENT` + `documentLaunchMode="intoExisting"` |
| **iOS / iPadOS** | 应用内页面 | `StubAppTaskManager`（MaterialPageRoute / 预留 iPad Scene 扩展） |
| **Windows / macOS / Linux** | 应用内页面 / 预留多窗口 | `StubAppTaskManager`（预留 WindowService 多窗口扩展） |
| **Web** | 应用内页面 | `StubAppTaskManager`（路由容器内加载） |
