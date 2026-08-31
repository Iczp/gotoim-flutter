# Flutter 局域网文件管理方案

## 1. 功能目标

在 Flutter APP 内启动一个本地 HTTP Server，并内置一套 H5 文件管理页面。

同一局域网内的 PC、手机、平板，可以通过浏览器访问 APP 上的文件。

例如：

```text
http://192.168.1.128:5678
```

主要功能：

- 浏览 APP 共享文件
- 上传文件到 APP
- 下载文件
- 新建文件夹
- 重命名
- 移动文件
- 删除文件
- 文件预览
- 大文件分片上传
- 断点续传
- APP 实时显示已连接终端
- APP 显示上传、下载进度
- APP 可主动断开终端

------

## 2. 整体架构

```text
Flutter APP
│
├─ Local HTTP Server
│
├─ 内置 H5 文件管理页面
│
├─ REST File API
│
└─ WebSocket
     │
     ├─ 终端在线状态
     ├─ 心跳
     └─ 文件操作 / 传输进度
            │
            ▼
       局域网 Wi-Fi
            │
    ┌───────┴────────┐
    │                │
Windows 浏览器     手机/平板浏览器
```

推荐技术：

```text
HTTP Server
shelf

静态 H5
shelf_static

WebSocket
shelf_web_socket

H5
Vue 3 + Vite + TypeScript  (IOS 风格)
```

------

## 3. Flutter 页面

例如：

```text
局域网文件管理

● 服务已开启

访问地址


验证码


[复制地址] [显示二维码]

-----------------------

已连接终端 2

Windows PC
Chrome
192.168.1.20
正在下载 video.mp4  68%
[断开]

iPad
Safari
192.168.1.30
在线 · 空闲
[断开]

-----------------------

[关闭文件共享]
```

------

## 4. HTTP Server

监听：

```text
0.0.0.0:47832
```

不要监听：

```text
127.0.0.1
```

否则局域网其他设备无法访问。

端口可以从：

```text
47832
47833
47834
...
```

自动寻找可用端口。

------

## 5. 内置 H5

单独建立：

```text
F:\Dev\GotoIM\gotoim-flutter-local-share-web
```

使用：

```text
Vue 3
Vite
TypeScript
```

编译：

```bash
pnpm build
```

生成：

```text
dist/
├─ index.html
└─ assets/
```

放入 Flutter：

```text
assets/file_web/
```

由本地 HTTP Server 提供：

```text
GET /
GET /assets/*
```

------

## 6. 文件 API

建议：

```text
GET    /api/files
GET    /api/files/info
GET    /api/files/content

POST   /api/files/mkdir

PUT    /api/files/rename
PUT    /api/files/move

DELETE /api/files
```

上传：

```text
POST /api/uploads
PUT  /api/uploads/:id/chunks/:index
GET  /api/uploads/:id
POST /api/uploads/:id/complete
DELETE /api/uploads/:id
```

WebSocket：

```text
/ws
```

------

## 7. 大文件处理

禁止：

```dart
file.readAsBytes()
```

大文件下载必须使用：

```dart
file.openRead()
```

流式发送。

上传采用分片，例如：

```text
4 MB / Chunk
```

流程：

```text
创建上传任务
    ↓
上传 Chunk 0
上传 Chunk 1
上传 Chunk 2
    ↓
中途断开
    ↓
重新查询已上传 Chunk
    ↓
继续上传
    ↓
Complete
```

下载建议支持 HTTP：

```text
Range
```

用于：

- 断点下载
- 视频拖动播放
- 音频 Seek
- 大文件读取

------

## 8. 终端管理

浏览器打开页面后建立：

```text
WebSocket /ws
```

客户端发送：

```json
{
  "type": "hello",
  "terminalId": "xxx",
  "name": "Chrome",
  "platform": "Windows"
}
```

APP 保存：

```text
terminalId
IP
浏览器
平台
连接时间
最后活动时间
当前状态
```

状态：

```text
online
idle
uploading
downloading
offline
```

每隔约 15 秒进行心跳。

长时间没有心跳则认为终端离线。

------

## 9. WebSocket 职责

WebSocket 不传输大文件。

只负责：

```text
终端上线
终端下线
心跳
文件新增
文件删除
文件修改
上传状态
下载状态
传输进度
```

例如：

```json
{
  "type": "transfer.progress",
  "fileName": "video.mp4",
  "received": 125829120,
  "total": 524288000
}
```

真正的文件内容全部通过 HTTP Stream 传输。

------

## 10. 安全

每次启动文件共享服务生成：

```text
4 位验证码
```

例如：

```text
6789
```

浏览器必须登录后才能访问文件 API。

也可以提供二维码：

```text
http://192.168.1.128:47832/?token=xxx
```

二维码 Token：

- 一次性使用
- 短时间有效
- 登录成功后换成 Session Token

同时必须防止目录穿越：

```text
../
../../
%2e%2e/
```

H5 不允许直接访问手机真实文件路径。

只暴露虚拟路径：

```text
/
├─ 图片
├─ 视频
├─ 文档
├─ 下载
└─ 聊天文件
```

------

## 11. 终端权限

后续可以支持：

```text
浏览文件
下载文件
上传文件
创建目录
重命名
移动文件
删除文件
```

例如：

```text
Windows PC

☑ 浏览
☑ 下载
☑ 上传
☑ 新建目录
☐ 删除文件

[断开连接]
```

------

## 12. Flutter 目录建议

```text
lib/features/local_file_server/

├─ local_file_server.dart
├─ local_file_server_controller.dart
│
├─ server/
│  ├─ http_server.dart
│  ├─ router.dart
│  ├─ auth_middleware.dart
│  └─ websocket_handler.dart
│
├─ api/
│  ├─ file_api.dart
│  ├─ upload_api.dart
│  └─ terminal_api.dart
│
├─ services/
│  ├─ file_manager.dart
│  ├─ terminal_manager.dart
│  └─ transfer_manager.dart
│
├─ models/
│  ├─ connected_terminal.dart
│  ├─ shared_file.dart
│  └─ transfer_task.dart
│
└─ pages/
   └─ local_file_server_page.dart
```

------

## 13. 平台注意事项

### Android

传输期间可使用 Foreground Service，提高后台稳定性。

### iOS

局域网访问需要申请 Local Network 权限。

iOS 进入后台或锁屏后，APP 可能被系统挂起，因此文件管理页面应提示：

```text
文件传输期间请保持 APP 在前台。
```

### Windows / macOS/linux

可以长期运行本地 HTTP Server，适合作为稳定的文件共享端。

------

## 14. 第一阶段实现范围

第一版建议只实现：

```text
Local HTTP Server
+
Vue H5
+
文件列表
+
上传 / 下载
+
新建 / 删除 / 重命名 / 移动
+
大文件分片上传
+
Range 下载
+
WebSocket 终端状态
+
APP 实时显示连接设备
+
验证码 / 二维码认证
```

暂时不需要：

```text
WebRTC
mDNS
公网穿透
复杂 P2P
```

先把纯局域网文件管理做稳定。