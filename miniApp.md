# Flutter 工作台动态应用 + Android 独立任务栈

目标：实现类似微信小程序的体验。

* GotoIM 主应用保持一个系统任务。
* 工作台应用由服务端动态返回，不写死。
* 点击工作台应用后，Android 可在“最近任务”中出现独立卡片。
* 同一个应用再次打开时，默认切回已有 Task，不重复创建。
* 新增工作台应用不需要修改 Android Manifest 或重新发版。
* iOS 暂不实现独立系统 Task，退化为普通页面。
* 所有功能加入“开发诊断中心”，方便真机测试。

---

## 1. 核心架构

不要用 Flutter `Navigator.push()` 模拟系统任务。

Android 使用：

```text
MainActivity
└── GotoIM 主 FlutterEngine

MiniAppActivity
├── Task: CRM
├── Task: OA
└── Task: 其他动态应用
```

Android 只新增一个通用：

```text
MiniAppActivity
```

禁止为每个应用创建：

```text
CrmActivity
OaActivity
ErpActivity
...
```

工作台应用数量必须完全动态。

---

## 2. Android Task

新增 `MiniAppActivity`，继承现有项目适合的：

```kotlin
FlutterActivity
```

如插件要求 `FragmentActivity`，再使用对应 Flutter Fragment Activity。

Manifest：

```xml
<activity
    android:name=".task.MiniAppActivity"
    android:exported="false"
    android:launchMode="standard"
    android:documentLaunchMode="intoExisting"
    android:excludeFromRecents="false"
    android:autoRemoveFromRecents="false"
    android:hardwareAccelerated="true"
    android:windowSoftInputMode="adjustResize" />
```

启动使用：

```text
FLAG_ACTIVITY_NEW_DOCUMENT
```

默认：

```text
reuseExisting = true
```

Task 唯一身份使用：

```text
gotoim://miniapp/{appId}
```

例如：

```text
gotoim://miniapp/crm
gotoim://miniapp/oa
gotoim://miniapp/cloud-drive
```

Task Identity 必须使用 `appId`，不要使用当前网页 URL。

---

## 3. URL 和 Task Identity 分离

例如：

```text
appId = crm

Task Identity:
gotoim://miniapp/crm

实际页面:
https://crm.gotoim.com/customer/123
```

Android：

```text
Intent.data
→ gotoim://miniapp/crm
```

启动参数：

```text
url
title
appId
arguments
```

通过 extras / launch payload 传递。

禁止通过 Intent、URI、initialRoute 传：

```text
accessToken
refreshToken
password
```

---

## 4. FlutterEngine

使用：

```text
FlutterEngineGroup
```

主应用和 MiniApp 使用独立 FlutterEngine。

增加独立 Dart 入口：

```dart
void main() {
  runMainApp();
}

@pragma('vm:entry-point')
void miniAppMain() {
  runMiniApp();
}
```

MiniApp Engine 只初始化：

```text
Theme
Localization
HTTP
Auth
Storage
WebView
JSBridge
必要日志
```

不要重复启动：

```text
SignalR 主连接
消息同步
会话同步
Badge Job
主应用后台任务
```

不同 FlutterEngine 不要依赖 Dart `static` / singleton 共享状态。

---

## 5. Flutter API

业务层统一使用：

```dart
abstract interface class AppTaskManager {
  bool get isSupported;

  Future<void> openMiniApp(
    MiniAppTaskRequest request,
  );

  Future<void> closeCurrentTask();
}
```

请求：

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

默认：

```text
reuseExisting = true
```

业务代码禁止直接调用：

```text
MethodChannel
Intent
MiniAppActivity
```

---

## 6. 重复打开

第一次：

```text
打开 CRM
→ 创建 CRM Task
```

再次打开：

```text
打开 CRM
→ 找到 gotoim://miniapp/crm
→ 激活已有 CRM Task
```

不要重新创建 CRM。

普通从工作台再次点击 CRM 时：

```text
保留 CRM 当前页面状态
```

不要自动回首页。

---

## 7. Deep Link 到已有应用

需要支持：

```text
openMiniApp(
  appId: crm,
  url: https://crm.gotoim.com/customer/123
)
```

如果 CRM 未打开：

```text
创建 CRM Task
→ 打开 customer/123
```

如果 CRM 已打开：

```text
激活 CRM Task
→ MiniAppActivity.onNewIntent()
→ PlatformChannel
→ MiniApp Flutter
→ WebView 打开 customer/123
```

实现简单的：

```dart
abstract interface class MiniAppLaunchHandler {
  Future<void> handleLaunch(
    MiniAppLaunchRequest request,
  );
}
```

---

## 8. 关闭和返回

关闭 MiniApp：

```text
closeCurrentTask()
→ Android finishAndRemoveTask()
```

只关闭当前 MiniApp，不影响 GotoIM。

返回优先级：

```text
1. WebView 可以后退 → goBack()
2. Flutter Navigator 可以 pop → pop()
3. 已到 MiniApp 根页面 → 关闭当前 Task
```

禁止：

```text
System.exit
killProcess
```

---

## 9. 工作台动态应用

工作台只是 GotoIM 的一个 Tab。

```text
GotoIM
├── 消息
├── 通讯录
├── 工作台
└── 我的
```

工作台从 API 动态加载应用。

建议模型：

```dart
class WorkbenchApp {
  final String appId;
  final String name;
  final String? iconUrl;
  final Uri url;

  final WorkbenchAppType type;
  final AppOpenMode openMode;

  final bool reuseExisting;
  final MiniAppAuthMode authMode;

  final int sort;
  final bool enabled;
}
```

枚举：

```dart
enum WorkbenchAppType {
  web,
  flutter,
  native,
}

enum AppOpenMode {
  current,
  page,
  systemTask,
}

enum MiniAppAuthMode {
  none,
  silent,
  userAuthorization,
}
```

后端可以返回：

```json
{
  "appId": "crm",
  "name": "CRM",
  "iconUrl": "...",
  "url": "https://crm.gotoim.com",
  "type": "web",
  "openMode": "systemTask",
  "reuseExisting": true,
  "authMode": "silent",
  "sort": 10,
  "enabled": true
}
```

新增应用后客户端刷新即可显示，不需要修改 Android 代码。

---

## 10. 工作台 Repository

增加：

```dart
abstract interface class WorkbenchRepository {
  Future<List<WorkbenchApp>> getApps({
    bool forceRefresh = false,
  });
}
```

优先复用现有 Drift。

流程：

```text
进入工作台
→ 先读取本地缓存
→ 立即显示
→ 请求服务器
→ 更新缓存
→ 刷新 UI
```

避免等待网络出现白屏。

---

## 11. 打开方式

统一：

```dart
Future<void> openWorkbenchApp(
  WorkbenchApp app,
)
```

根据：

```text
openMode
```

执行：

```text
systemTask
→ AppTaskManager

page
→ Flutter 页面

current
→ 当前容器打开
```

不要所有应用都强制创建独立 Task。

---

## 12. MiniApp 容器

第一阶段主要支持 Web MiniApp。

建议独立：

```text
MiniAppHostPage
```

负责：

```text
WebView
标题
返回
关闭
加载状态
错误页面
JSBridge
认证
```

Task 层不要直接处理 WebView 业务。

---

## 13. 认证安全

MiniApp 不直接获得 GotoIM RefreshToken。

推荐：

```text
MiniApp
→ JSBridge
→ GotoIM Auth
→ 临时 code / ticket
→ H5 服务端换自己的登录状态
```

后续再实现：

```text
none
silent
userAuthorization
```

三种授权模式。

本次至少保证架构支持。

---

## 14. 进程恢复

必须考虑 Android 杀进程。

例如最近任务中有：

```text
GotoIM
CRM
OA
```

进程被杀后直接点击 CRM：

```text
重新创建 Application
→ FlutterEngineGroup
→ MiniAppActivity
→ 根据 Intent 恢复 CRM
```

恢复不能依赖纯内存数据。

至少能恢复：

```text
appId
title
url
```

---

## 15. 平台兼容

Android：

```text
真正独立 Task
```

iPhone：

```text
普通 Flutter 页面
```

暂不模拟 Android 最近任务效果。

接口保留以后扩展：

```text
Android → Task
iPad → Scene
Windows/macOS → Window
```

---

## 16. 开发诊断中心

增加：

```text
开发诊断中心
→ 应用级任务栈
```

页面支持输入：

```text
appId
title
url
reuseExisting
```

按钮：

```text
打开独立 Task
关闭当前 Task
```

增加快捷测试：

```text
MiniApp A
MiniApp B
随机 AppId
```

显示：

```text
平台
是否支持 System Task
appId
url
reuseExisting
最后结果
异常
```

再增加工作台动态测试：

```text
初始：
CRM
OA

动态增加：
Cloud Drive
ERP
Project
```

验证增加应用后：

```text
不修改 Manifest
不增加 Activity
仍然可以创建独立 Task
```

---

## 17. Android 真机验收

启动 GotoIM：

```text
最近任务：
GotoIM
```

打开 CRM：

```text
GotoIM
CRM
```

打开 OA：

```text
GotoIM
CRM
OA
```

再次打开 CRM：

```text
必须切换到原 CRM
不能出现两个 CRM
```

测试：

```text
Home
最近任务切换
系统 Back
返回手势
WebView 后退
关闭 Task
锁屏恢复
横竖屏
低内存
进程重建
```

关闭 CRM 后：

```text
GotoIM
OA
```

仍正常存在。

---

## 18. 日志

Debug 日志至少记录：

```text
[AppTask] open
[AppTask] appId
[AppTask] taskId
[AppTask] onCreate
[AppTask] onNewIntent
[AppTask] onDestroy
[AppTask] close
```

禁止输出 Token、Cookie、Authorization。

---

## 19. 最终交付

完成后说明：

1. 修改了哪些文件
2. AppTaskManager 如何调用
3. 工作台如何动态加载
4. Android Task 创建与复用机制
5. FlutterEngine 生命周期
6. 如何测试
7. 哪些项目需要 Android 真机人工确认
8. 已知 iOS 限制

优先适配现有项目结构和现有依赖，不要为了符合本文目录而大规模重构，也不要新增不必要的第三方库。
