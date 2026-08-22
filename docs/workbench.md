# 工作台动态应用指南 (Workbench)

工作台是 GotoIM 客户端的四大核心 Tab 之一（消息、通讯录、工作台、我的），用于集中管理和启动企业内部及第三方应用。

工作台采用**完全动态化设计**：所有应用列表、权限、图标、跳转地址及打开方式均由服务端接口下发，客户端支持离线缓存并实时刷新，新增或下线应用**无需修改客户端代码或重新发版**。

---

## 1. 核心架构与设计原则

```text
┌─────────────────────────────────────────────────────────────┐
│                       GotoIM 工作台                          │
│                                                             │
│   WorkbenchPage (UI 网格展示与交互)                          │
│        │                                                    │
│        ▼                                                    │
│   WorkbenchRepository.getApps()                             │
│        │ (离线优先)                                          │
│   ┌────┴───────────────────────────┐                        │
│   │ 1. 优先读取本地缓存             │ 2. 异步拉取后端 API     │
│   │    秒开渲染，避免白屏           │    更新缓存并刷新 UI   │
│   └────────────────────────────────┴────────────────────────┘
│                                                             │
│   点击应用 -> openWorkbenchApp(app)                        │
│        │                                                    │
│        ├─── openMode == systemTask ──► AppTaskManager (独立多任务)
│        ├─── openMode == page       ──► Navigator.push (应用内页面)
│        └─── openMode == current    ──► 替换当前容器 URL
└─────────────────────────────────────────────────────────────┘
```

### 核心原则
1. **离线优先（Offline First）**：进入工作台时优先展示本地缓存的应用列表，避免网络较慢时出现白屏或等待加载动画；后台异步请求服务器并更新缓存与 UI。
2. **零发版扩展（Zero-Release Extensibility）**：新增、下线或更新业务系统仅需在管理后台配置，客户端无需修改代码、无须修改 Android Manifest，即时生效。
3. **按需分发打开方式（Flexible Open Modes）**：根据每个应用的 `openMode` 属性灵活决定是以“系统级独立任务”、“应用内普通页面”还是“当前容器内替换”方式打开。

---

## 2. 数据模型与枚举定义

### 2.1 `WorkbenchApp`
工作台应用的实体模型：

```dart
class WorkbenchApp {
  final String appId;            // 唯一应用标识，例如 'crm', 'oa', 'erp'
  final String name;             // 应用显示名称
  final Uri url;                 // 实际加载的目标 URL
  final String? iconUrl;         // 图标图片地址（支持网络图片）
  final WorkbenchAppType type;   // 应用类型：web | flutter | native
  final AppOpenMode openMode;    // 打开方式：systemTask | page | current
  final bool reuseExisting;      // 再次打开时是否复用已有任务（默认 true）
  final MiniAppAuthMode authMode;// 认证模式：none | silent | userAuthorization
  final int sort;                // 排序权重（数值越小排序越靠前）
  final bool enabled;            // 是否启用
}
```

### 2.2 枚举定义

#### 应用类型 `WorkbenchAppType`
```dart
enum WorkbenchAppType {
  web,     // Web H5 应用（在 MiniAppHostPage WebView 容器中运行）
  flutter, // Flutter 原生子模块（预留）
  native,  // 平台原生应用（通过 Scheme/Intent 唤起，预留）
}
```

#### 打开方式 `AppOpenMode`
```dart
enum AppOpenMode {
  systemTask, // 独立系统任务栈（Android Document Task 独立卡片，iOS 平滑降级为页面）
  page,       // 应用内普通 Flutter 页面
  current,    // 在当前容器内直接替换 URL
}
```

#### 认证模式 `MiniAppAuthMode`
```dart
enum MiniAppAuthMode {
  none,              // 无需认证直接打开
  silent,            // 静默授权（通过 JSBridge 换取临时 ticket / 注入登录凭证）
  userAuthorization, // 弹窗请求用户显式授权公开信息
}
```

---

## 3. 服务端 JSON 契约示例

后端 API 返回的应用列表结构：

```json
[
  {
    "appId": "crm",
    "name": "客户管理 (CRM)",
    "iconUrl": "https://cdn.gotoim.com/icons/crm.png",
    "url": "https://crm.gotoim.com",
    "type": "web",
    "openMode": "systemTask",
    "reuseExisting": true,
    "authMode": "silent",
    "sort": 10,
    "enabled": true
  },
  {
    "appId": "oa",
    "name": "协同办公 (OA)",
    "iconUrl": "https://cdn.gotoim.com/icons/oa.png",
    "url": "https://oa.gotoim.com",
    "type": "web",
    "openMode": "systemTask",
    "reuseExisting": true,
    "authMode": "none",
    "sort": 20,
    "enabled": true
  },
  {
    "appId": "report",
    "name": "日常报表",
    "iconUrl": "https://cdn.gotoim.com/icons/report.png",
    "url": "https://bi.gotoim.com/report/today",
    "type": "web",
    "openMode": "page",
    "reuseExisting": true,
    "authMode": "none",
    "sort": 30,
    "enabled": true
  }
]
```

---

## 4. 业务使用方式

### 4.1 获取工作台应用列表 (`WorkbenchRepository`)

```dart
final repository = ref.read(workbenchRepositoryProvider);

// 获取应用列表（forceRefresh: true 强制从服务端拉取）
final List<WorkbenchApp> apps = await repository.getApps(forceRefresh: false);
```

### 4.2 统一打开应用 (`openWorkbenchApp`)

在 UI 点击事件中，直接调用内置的 `openWorkbenchApp` 辅助方法，系统会自动依据 `app.openMode` 进行路由分发：

```dart
import 'package:gotoim_flutter/core/services/task/app_task_manager.dart';
import 'package:gotoim_flutter/features/workbench/data/workbench_models.dart';

void onAppClick(BuildContext context, WidgetRef ref, WorkbenchApp app) {
  final taskManager = ref.read(appTaskManagerProvider);

  openWorkbenchApp(
    app,
    taskManager: taskManager,
    navigator: Navigator.of(context),
  );
}
```

---

## 5. 认证与安全设计

为保障主应用安全性，MiniApp 容器执行以下安全策略：
1. **禁止直接暴露主 Token**：MiniApp 无法直接读取 GotoIM 主应用的 `accessToken` 或 `refreshToken`，避免第三方 Web 脚本劫持凭证。
2. **Ticket / Code 授权换取机制**：
   - MiniApp 通过 JSBridge 向宿主发起授权请求；
   - 宿主生成高时效、一次性使用的 `code` / `ticket`；
   - MiniApp 服务端后端拿 `code` 向 GotoIM 鉴权中心换取用户信息并建立其自身会话。
3. **URL 协议隔离**：启动 Intent / Task 时仅传递 `url`、`title` 和 `appId`，严禁在 Intent Extra 或 URI Query 中明文传递密码与敏感 Token。
