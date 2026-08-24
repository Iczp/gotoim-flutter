# flutter 事项



### chooseVideo

1. 增加 是否要压缩 与及压缩的参数
2. 增加 是否载取视频缩略图，可以是多个缩略图



### webview 使用  flutter_inappwebview 库

1. JS 双向通信
2. WebView 控制能力
3. 文件上传
4. 下载监听
5. 页面生命周期
6. 视频播放控制
7. 注入 JS

在 开发诊断中心加入这些，同时还要有JS Bridge Harness ，示例 ,  同时写入Docs

### Flutter 渲染 HTML，flutter_html

1. 做自定义渲染
2. 消息文本渲染

### 文件选择（OK）

单选和多选，支持文件类型，多选时，选择器要有多选框，要有最大选择数，

### 数据库方案(OK)

迁移数据库，统一封装，原项目使用了Sqlite和IndexDb，主要是因为Web端不支持Sqlite，现在使用Flutter,  也是兼容多平台，移动端、桌面端，和WEB端。  能统一方案是最好的。

在 开发诊断中心 加入测试，并展示，如CRUD功能，表操作功能等。



1. 不能修改 原项目 F:\Dev\GotoIM\gotoim-mobile\gotoim-uniapp-ts，  原项目只是参考用的
2. 要改的项目是： F:\Dev\GotoIM\gotoim-flutter

### 离线推送方案

### 附件打印方案

### Native（完成）

实现 AGENTS.md 中的 Native / Device 能力：

- 截屏监听
- 振动
- 系统主题变化
- 内存不足
- 加速度计（默认约 5 次/秒）
- 陀螺仪
- 拨打电话
- 屏幕亮度
- 电量
- 距离传感器

要求：
- 优先 Flutter 内置能力，其次成熟插件，无法实现再写 Native Channel。
- 复用现有依赖，不重复封装。
- 事件监听必须支持取消订阅。
- Android/iOS 优先实现，其他平台安全降级。
- 所有能力加入开发诊断中心，可实时查看事件和返回结果。


特别说明：

项目中有些已经Native能力，如文件图片视频等，已有JsBridge， 和 jsBridge Harness, 



### 生物认证

开始 SOTER 生物认证。 startSoterAuthentication

获取本机支持的 SOTER 生物认证方式

获取本机支持的 SOTER 生物认证方式checkIsSupportSoterAuthentication

获取设备内是否录入如指纹等生物信息的接口 checkIsSoterEnrolledInDevice

### Share模块

###  统计方案 Analytics、statistic

### 日志方案  logger



### 图片剪裁方案

头像剪裁

### 图片预览查看器，



### 音频的录制和播放功能 Audio



### 视频相关

### 位置信息

### Maps模块管理地图控件

### 桌面角标



当前未完成的主要功能：

- IM 主链路：会话列表、聊天页、消息分页、发送队列、失败重试、撤回/删除/已读、未读数。
- 本地优先数据层：业务 Model、DAO、Repository、监听流、增量同步；当前数据库主要是 schema 和诊断 CRUD。
- SignalR → Repository → Drift → Riverpod 的真实同步链路。
- 联系人、群组创建与管理、成员、会话设置、资料/个人中心、设备管理。
- 附件上传下载、消息媒体渲染、图片预览、视频播放、语音播放、HTML 消息渲染。
- 推送/离线通知、设备注册、桌面角标与独立聊天窗口。
- 生物认证、分享、统计、统一日志、头像裁剪、地图/位置等 [`TODO.md`](F:\\Dev\\GotoIM\\gotoim-flutter\\TODO.md) 项目。
- `freezed`、`json_serializable`、`build_runner` 尚未接入；这与项目规范中的 DTO/Model 生成要求不一致。
- 工作台应从 Mock 数据源替换为 API + Drift 缓存。
- Auth 配置允许可选 `AUTH_CLIENT_SECRET` 打包进 `.env`；生产环境必须改为公开客户端 / PKCE，不能在客户端保存真实 secret。

建议下一步先做“会话与消息数据主链路”，先不急着堆聊天 UI：

1. 建立 `features/session` 和 `features/chat` 的 DTO、领域模型、Drift 表/DAO；补齐 `localId / serverId / clientMessageId / sessionId / sessionMessageId` 与消息状态。
2. 实现 `SessionRepository`、`MessageRepository`：本地先展示、HTTP 增量拉取、SignalR 事件落库、发送 Pending→Sent/Failed。
3. 给这条链路补并发、去重、分页、401 刷新、SignalR 同步测试，并在诊断中心加入“会话/消息同步测试”。
4. 再基于这些流构建响应式会话列表；聊天页随后用 `CustomScrollView/SliverList` 实现分页与稳定滚动。

这条顺序最稳：先让 IM 数据可离线、可同步、可测试，再做页面，避免未来把 UI 与 HTTP/SignalR 直接绑死。

