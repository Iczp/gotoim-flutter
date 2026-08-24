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

### 开始 SOTER 生物认证。 startSoterAuthentication

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

