# Flutter 接入 IczpNet.AppStatistic

## 1. 目标

Flutter 客户端接入 `IczpNet.AppStatistic`，统一采集：

- App 启动
- 前后台切换
- 登录/退出
- 页面访问
- 页面停留
- Session
- 设备信息
- App 版本
- 渠道
- 自定义事件

要求：

```
低侵入
异步
批量上传
断网不丢
失败重试
不影响主业务
```

# 2. 推荐目录

```
lib/core/statistic/

statistic_service.dart
statistic_event.dart
statistic_device.dart
statistic_session.dart

statistic_repository.dart
statistic_api.dart

statistic_queue.dart
statistic_storage.dart

statistic_route_observer.dart

statistic_event_names.dart
statistic_page_names.dart
```

业务代码只调用：

```
StatisticService
```

不要直接操作 API 和本地数据库。

# 3. 初始化

App 启动时：

```
await StatisticService.instance.initialize();
```

初始化完成：

```
读取/创建 DeviceKey
获取设备信息
获取 AppVersion
获取 Platform
恢复未上传事件
创建 Session
记录 app_start
启动上传任务
```

# 4. DeviceKey

首次安装生成：

```
UUID
```

持久化保存。

例如：

```
550e8400-e29b-41d4-a716-446655440000
```

不要使用：

```
IMEI
MAC
IDFA
```

作为统一设备标识。

# 5. 设备信息

采集：

```
deviceKey
platform
manufacturer
model
osName
osVersion
appVersion
channel
language
timezone
```

建议使用：

```
device_info_plus
package_info_plus
```

渠道建议由编译配置传入，例如：

```
const channel = String.fromEnvironment(
  'APP_CHANNEL',
  defaultValue: 'official',
);
```

# 6. 核心事件

统一常量：

```
class StatisticEventNames {
  static const appStart = 'app_start';

  static const appForeground = 'app_foreground';
  static const appBackground = 'app_background';

  static const login = 'login';
  static const logout = 'logout';

  static const pageView = 'page_view';
  static const pageLeave = 'page_leave';

  static const crash = 'crash';
}
```

# 7. 事件模型

```
class StatisticEvent {
  final String eventId;
  final String eventName;

  final String? sessionId;
  final String? page;

  final DateTime eventTime;

  final Map<String, dynamic>? properties;
}
```

每个事件创建独立：

```
eventId
```

使用 UUID/ULID。

服务端依靠 EventId 去重。

# 8. 记录事件

统一接口：

```
Future<void> track(
  String eventName, {
  String? page,
  Map<String, dynamic>? properties,
});
```

例如：

```
await StatisticService.instance.track(
  'search',
  properties: {
    'source': 'home',
  },
);
```

调用 `track()` 时：

```
生成 EventId
补充 SessionId
补充时间
写本地队列
尝试触发上传
```

不要等待服务器返回后再继续业务。

# 9. App 生命周期

使用：

```
WidgetsBindingObserver
```

监听：

```
resumed
paused
inactive
detached
```

映射：

```
App启动
→ app_start

进入前台
→ app_foreground

进入后台
→ app_background
```

不要依赖：

```
app_exit
```

因为移动端不能保证退出事件一定执行。

# 10. Session

App 启动生成：

```
SessionId
```

例如：

```
final sessionId = const Uuid().v4();
```

同一 Session 下所有事件携带：

```
sessionId
```

规则：

```
Cold Start
→ 新 Session

进入后台
→ 保留当前 Session

后台超过 30 分钟
→ 再次进入前台时创建新 Session
```

超时时间做成配置：

```
Duration sessionTimeout = const Duration(minutes: 30);
```

# 11. 登录 / 退出

登录成功：

```
StatisticService.instance.setUser(userId);

StatisticService.instance.track(
  StatisticEventNames.login,
);
```

退出：

```
await StatisticService.instance.track(
  StatisticEventNames.logout,
);

StatisticService.instance.clearUser();
```

统计服务只保存：

```
UserId
```

不依赖完整用户模型。

# 12. 页面统计

不要直接使用真实 Route 作为统计名称。

定义稳定：

```
class StatisticPageNames {
  static const home = 'home';

  static const chatHome = 'chat.home';
  static const chatSession = 'chat.session';

  static const contacts = 'contacts.home';

  static const profile = 'profile.home';
}
```

例如：

```
/chat/10001
/chat/10002
/chat/:id
```

全部统计为：

```
chat.session
```

# 13. RouteObserver

开发：

```
StatisticRouteObserver
```

监听页面：

```
进入
离开
```

进入：

```
page_view
```

离开：

```
page_leave
```

同时计算：

```
durationSeconds
```

例如：

```
{
  "eventName": "page_leave",
  "page": "chat.session",
  "properties": {
    "durationSeconds": 82
  }
}
```

# 14. 页面接入方式

页面通过 Route 配置统计名。

例如：

```
StatisticPageRoute(
  pageName: StatisticPageNames.chatSession,
  child: const ChatPage(),
);
```

或者在路由 Metadata 中配置：

```
GoRoute(
  path: '/chat/:id',
  name: 'chat',
  builder: ...,
)
```

统一转换成：

```
chat.session
```

禁止业务页面自己大量手写：

```
track('page_view')
```

页面统计尽量自动化。

# 15. 本地队列

事件必须先写本地。

如果项目已经使用 Drift，直接增加：

```
StatisticEventQueue
```

表：

```
Id
EventId
Payload
CreatedTime
RetryCount
NextRetryTime
```

流程：

```
track
 ↓
Drift
 ↓
Batch Upload
 ↓
Success
 ↓
Delete
```

断网：

```
继续保存
网络恢复后上传
```

# 16. 批量上传

接口：

```
POST /api/app-statistic/events
```

建议触发条件：

```
累计 >= 20 条

或

距离上次上传 >= 15 秒

或

App进入后台

或

网络恢复
```

单次最大：

```
100 条
```

# 17. 请求示例

```
{
  "device": {
    "deviceKey": "xxx",
    "platform": "android",
    "manufacturer": "Xiaomi",
    "model": "xxx",
    "osVersion": "16",
    "appVersion": "3.2.0",
    "channel": "official"
  },
  "events": [
    {
      "eventId": "event-1",
      "eventName": "app_start",
      "sessionId": "session-1",
      "eventTime": "2026-09-30T12:00:00+08:00"
    }
  ]
}
```

# 18. 上传失败

失败不能删除本地数据。

重试：

```
1分钟
5分钟
15分钟
30分钟
1小时
```

建议指数退避。

最大失败次数不要直接丢弃。

超过阈值：

```
降低重试频率
```

仍保留事件。

# 19. 上传并发

只允许一个上传任务执行。

例如：

```
bool _uploading = false;
```

避免：

```
Timer上传
后台上传
网络恢复上传
```

同时执行产生重复请求。

EventId 即使重复上传，服务端也必须保持幂等。

# 20. 网络

使用现有 Dio Client。

例如：

```
Business Dio
```

调用：

```
/api/app-statistic/events
```

统计失败：

```
不能阻塞业务接口
不能弹 Toast
不能影响登录
```

只记录 Debug Log。

# 21. Crash

V1 可以接：

```
FlutterError.onError
```

以及：

```
PlatformDispatcher.instance.onError
```

记录：

```
crash
```

Properties：

```
errorType
message
stackHash
page
```

不要上传完整敏感业务数据。

完整 Crash 平台后续可接：

```
Sentry
Firebase Crashlytics
```

AppStatistic 只做基础统计。

# 22. Properties 原则

允许：

```
properties: {
  'source': 'push',
  'network': 'wifi',
}
```

禁止上传：

```
Password
Token
手机号
聊天内容
完整接口请求体
身份证
敏感个人信息
```

Properties 只能保存统计需要的信息。

# 23. Debug 模式

开发环境增加：

```
StatisticConfig(
  enabled: true,
  debugLog: true,
);
```

日志：

```
[Statistic] track page_view chat.session

[Statistic] queued event xxx

[Statistic] upload 20 events

[Statistic] upload success
```

便于和后台：

```
事件分析
```

一起验证埋点。

# 24. 开关配置

```
class StatisticConfig {
  final bool enabled;

  final bool debugLog;

  final int batchSize;

  final Duration uploadInterval;

  final Duration sessionTimeout;
}
```

默认：

```
enabled = true
batchSize = 20
uploadInterval = 15秒
sessionTimeout = 30分钟
```

# 25. StatisticService 对外接口

最终尽量只暴露：

```
StatisticService.instance.initialize();

StatisticService.instance.track(...);

StatisticService.instance.setUser(...);

StatisticService.instance.clearUser();

StatisticService.instance.flush();
```

业务层不要知道：

```
Drift
Dio
UploadQueue
DeviceInfo
Session实现
```

# 26. App 启动流程

```
main()
 ↓
初始化 Drift
 ↓
初始化 Dio
 ↓
StatisticService.initialize()
 ↓
读取 DeviceKey
 ↓
读取设备信息
 ↓
创建/恢复 Session
 ↓
记录 app_start
 ↓
runApp()
```

统计初始化失败：

```
记录日志
继续启动 App
```

不能因为统计服务导致 App 无法启动。

# 27. V1 必须实现

```
DeviceKey

Device 信息

AppStart

Foreground

Background

Login

Logout

PageView

PageLeave

Session

Drift 本地缓存

批量上传

失败重试

EventId 幂等
```

# 28. V1 暂不实现

```
复杂用户行为漏斗

热力图

广告归因

A/B Test

复杂性能监控

完整Crash平台

业务统计
```

# 29. 验收

启动 App 后后台应看到：

```
Device
AppEvent(app_start)
AppSession
```

进入页面：

```
page_view
```

离开页面：

```
page_leave
durationSeconds > 0
```

进入后台：

```
app_background
```

恢复：

```
app_foreground
```

断网产生事件：

```
本地保留
```

恢复网络：

```
自动上传
```

重复上传同一个 EventId：

```
服务端只统计一次
```

# 30. 最终原则

Flutter 端统计能力统一收口到：

```
StatisticService
```

业务代码只负责：

```
告诉统计系统发生了什么
```

统计模块负责：

```
什么时候保存
什么时候上传
如何重试
设备信息
Session
公共字段
```

最终实现：

```
业务低侵入
统计可追踪
断网可靠
后台可分析
```