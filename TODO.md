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

### 数据库方案

迁移数据库，统一封装，原项目使用了Sqlite和IndexDb，主要是因为Web端不支持Sqlite，现在使用Flutter,  也是兼容多平台，移动端、桌面端，和WEB端。  能统一方案是最好的。

在 开发诊断中心 加入测试，并展示，如CRUD功能，表操作功能等。



1. 不能修改 原项目 F:\Dev\GotoIM\gotoim-mobile\gotoim-uniapp-ts，  原项目只是参考用的
2. 要改的项目是： F:\Dev\GotoIM\gotoim-flutter

### 离线推送方案

### 附件打印方案