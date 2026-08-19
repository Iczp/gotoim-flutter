# 本地通知

本文说明 Goto IM Flutter 客户端的本地通知接入、参数和测试方式。

## 目标与边界

本地通知用于在**客户端已经拿到事件**后，由系统显示一条通知。它不负责接收服务器推送：后续 SignalR、推送服务或离线同步收到新消息后，应调用统一的 `LocalNotificationService`，而不是在页面、Repository 或业务 UseCase 中直接调用通知插件。

当前已接入 Android、iOS、macOS、Linux、Windows 的即时本地通知；Web 返回明确的“不支持”结果，不会静默失败。业务层只依赖统一契约，后续补充浏览器实现时无需改动聊天业务代码。

## 架构与代码位置

```text
SignalR / Push / 本地同步事件
              ↓
     业务 UseCase（后续接入）
              ↓
LocalNotificationService（平台无关契约）
              ↓
FlutterLocalNotificationService（唯一插件适配器）
              ↓
flutter_local_notifications / 系统通知服务
```

| 位置 | 职责 |
| --- | --- |
| `lib/core/notifications/local_notification_contract.dart` | 平台无关的 Service、请求、结果与点击事件模型。 |
| `lib/core/notifications/local_notification_service.dart` | 条件导出；Web 使用 Stub，原生平台使用适配器。 |
| `lib/core/notifications/local_notification_service_io.dart` | 插件初始化、权限、展示、取消和通知点击回调。这里是唯一直接依赖插件的平台层代码。 |
| `lib/app/bootstrap.dart` | 启动时初始化通知服务并注入 Riverpod，确保通知点击回调尽早注册。 |
| `lib/features/diagnostics/...local_notification...` | 仅 Debug 模式可用的诊断控制器与测试页面。 |

## 支持矩阵

| 平台 | 当前状态 | 权限 / 说明 |
| --- | --- | --- |
| Android / Android Tablet | 已接入 | Android 13（API 33）及以上需要 `POST_NOTIFICATIONS` 运行时授权；低版本通常无需弹窗。 |
| iOS / iPad | 已接入 | 在诊断页主动请求 alert、badge、sound 授权。 |
| macOS | 已接入 | 在诊断页主动请求 alert、badge、sound 授权。 |
| Linux | 已接入 | 由 Freedesktop 系统通知服务决定最终能力；通常没有应用级运行时授权弹窗。 |
| Windows | 已接入 | 使用 `flutter_local_notifications_windows` 的 Windows Toast FFI 实现。无需应用级运行时授权；可在系统通知设置中关闭或管理。 |
| Web | 预留适配器 | 当前不调用浏览器 API；后续单独实现浏览器 `Notification API` 与用户授权流程。 |

`flutter_local_notifications 22.3.0` 支持 Android、iOS、macOS、Linux、Windows 与 Web；本项目仅使用其原生平台适配器，Web 仍保留独立实现入口。Android 8 及以上的通知渠道在首次创建后，其声音、振动等关键设置由系统固定；修改相同渠道 ID 的这些参数通常不会生效。

## 参数说明

所有业务通知通过 `LocalNotificationRequest` 传递。

| 参数 | 类型 | 必填 | 规则与用途 |
| --- | --- | --- | --- |
| `id` | `int` | 是 | 通知唯一 ID，必须为非负整数。相同 ID 的新通知通常更新/覆盖同一条通知；取消时也使用该 ID。建议业务使用可重现的稳定 ID，而不是随机数。 |
| `channelId` | `String` | 是 | Android 8+ 的通知渠道标识，例如 `gotoim_message`。渠道相当于系统设置入口，不应随意复用不同业务等级。当前诊断默认 `gotoim_debug`。非 Android 平台忽略此项。 |
| `channelName` | `String` | 是 | Android 系统设置中给用户展示的渠道名称，例如“消息通知”。非 Android 平台忽略此项。 |
| `title` | `String` | 是 | 通知标题。IM 正式业务应遵循用户的隐私显示设置，不应默认暴露联系人或敏感内容。 |
| `body` | `String` | 是 | 通知正文。用于显示摘要，不应塞入 Token、密码或完整敏感消息。 |
| `payload` | `String` | 否 | 用户点击通知后原样回传给应用。推荐 JSON，例如 `{"type":"chat_message","sessionUnitId":"...","messageId":"..."}`。不要放 access token、refresh token、密码或附件私有地址。 |
| `delay` | `Duration` | 否 | `Duration.zero` 为立即展示；大于 0 时当前实现用 Dart `Timer` 延迟。**它不持久化，应用被关闭、进程被杀或重启时不会触发。** |

当前 Android 适配使用 `Importance.max` 与 `Priority.high`。正式 IM 应根据会话静音、免打扰、前后台状态、用户设置以及消息类型，集中决定渠道与优先级；不要由 UI 页面自行决定。

## 权限与原生配置

### Android

已在 `android/app/src/main/AndroidManifest.xml` 声明：

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

诊断页的“请求权限”会在 Android 13+ 请求授权。拒绝后，应引导用户到系统的应用通知设置；应用不能强行重新弹出已被系统限制的授权框。

插件 22.x 依赖 Java 17 与 core-library desugaring 支持，因此 `android/app/build.gradle.kts` 已开启 `isCoreLibraryDesugaringEnabled` 并添加 `desugar_jdk_libs`。默认小图标为 `android/app/src/main/res/drawable/ic_stat_notification.xml`，使用单色 drawable，避免把彩色启动图标显示成异常的状态栏图标。

### iOS / macOS

初始化阶段不会自动弹出权限框；由诊断页或未来的业务授权引导在合适的时机调用 `requestPermission()`。这样不会在首次启动时无上下文地打断用户。

### Linux

通知功能依赖当前桌面环境的 Freedesktop 通知服务，展示样式、声音、常驻能力等可能不同。Linux 插件不支持系统级的定时/待发送通知；当前的 `delay` 同样仅限应用进程存活。

### Windows

Windows 使用 Toast 通知。初始化时以固定的应用名、App User Model ID 和 GUID 注册激活回调，因此这三个标识必须保持稳定。诊断页的“请求权限”会返回“无需应用级授权”；如果横幅未显示，请在 Windows 的“通知”系统设置中确认 **Goto IM** 没有被禁用。

开发目录直接运行的 EXE 可以展示通知并接收应用运行期间的点击回调；Windows 只有在应用以 MSIX 等方式获得 package identity 后，`cancel` / `cancelAll` 才能可靠移除已经显示的系统通知。进程内延迟任务仍会被取消。

## 通知点击事件

用户点击通知时，插件回调会转换为 `LocalNotificationTapEvent`：

| 字段 | 说明 |
| --- | --- |
| `receivedAt` | 客户端接收到点击回调的本地时间。 |
| `actionId` | 点击的通知动作 ID；当前基础通知没有业务动作，通常为空或默认动作。 |
| `payload` | 创建通知时传入的原始字符串。 |

诊断页会显示并支持复制最近 100 条点击事件。当前基础层只负责上报事件；正式聊天路由应由单独的 `NotificationNavigationCoordinator`（后续任务）校验 payload、恢复登录状态，并导航到对应会话。不要在通知适配器中直接依赖 GoRouter 或聊天页面。

## 诊断中心测试步骤

1. 使用 Debug 模式登录后，进入“开发诊断中心 → 本地通知测试”。
2. 点击“请求权限”，并在系统弹窗中允许通知。
3. 依次编辑通知 ID、Android 渠道、标题、正文、Payload 与延迟秒数；每一个输入框都可以复制。
4. 点击“发送通知”。延迟为 `0` 时立即请求系统展示；为了观察横幅，可将应用切到后台。
5. 点击系统通知后，回到页面检查“通知点击事件”，确认 `payload` 是否完整回传。
6. 用“取消当前 ID”验证指定通知取消；用“取消全部”清理测试通知和进程内延迟任务。

测试页只在 `kDebugMode` 下开放。它允许编辑并显示 Payload，便于联调，但正式页面不得展示 Token、密码或完整私密消息。

## 现在没有实现的能力

- 可靠的系统级定时通知、重启恢复、时区处理与闹钟权限。
- Android 通知分组、会话样式、快捷回复、图片大图、附件下载与自定义声音。
- 按会话静音、免打扰、前台抑制、未读计数和通知折叠策略。
- iOS / Android 的远程推送接收；本地通知只是最终展示的一环。
- Web 的浏览器通知适配器。
- 点击通知后的业务导航与冷启动恢复流程。

如果后续需要可靠定时通知，应另建 `ScheduledNotificationService`：使用时区库、原生平台权限、Android 重启恢复广播及待发送任务持久化。不要把这类需求塞进当前 `delay` 字段。
