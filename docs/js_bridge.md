# JS Bridge

JS Bridge 位于 `lib/core/jsbridge/`，由 `JsApiDispatcher` 完成 JSON 协议解析和能力分发。`JsBridgeSession` 将调度器绑定到 `JsBridgeTransport`：宿主 WebView 只需把收到的文本传给 `handleIncoming()`，并实现 `postMessage()` 回推响应/事件。当前 Debug Harness 使用单一的 `flutter_inappwebview` 适配器覆盖 Android、iOS、macOS 和 Windows；H5 必须等待 `flutterInAppWebViewPlatformReady` 后，再通过 `window.flutter_inappwebview.callHandler('GotoIMBridge', json)` 请求 Flutter。

开发验证入口：Debug 模式的“开发诊断中心 → JS Bridge 测试”。该页会模拟 WebView Bridge 输入，显示完整响应，提供文件上传任务闭环，并显示网络及上传订阅事件。每个响应和事件面板均可选中或点击复制，便于人工比对。

## 请求与响应协议

每次请求必须是一个 JSON 对象：

```json
{"id":"request-123","action":"getSystemInfo","data":{}}
```

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | string | 是 | 调用方生成的非空请求 ID；响应原样返回 |
| `action` | string | 是 | API 名称，见下表 |
| `data` | object | 否 | API 参数；未给出时等同 `{}` |

成功响应：

```json
{"id":"request-123","success":true,"data":{"platform":"android"}}
```

失败响应：

```json
{
  "id":"request-123",
  "success":false,
  "error":{"code":"INVALID_ARGUMENT","message":"data 必须是对象。"}
}
```

错误码：`INVALID_REQUEST`（请求 JSON/字段不合法）、`INVALID_ARGUMENT`（API 参数不合法）、`NOT_SUPPORTED`（未知或未接入 action）、`UNAVAILABLE`（当前宿主不可用，例如无 Navigator）、`PAYLOAD_TOO_LARGE`（图片 base64 超过 10 MiB）、`INTERNAL_ERROR`（未预期异常）。业务页面不应依赖 `INTERNAL_ERROR` 的文本。

## Action 清单

短名称与分类名称等价；短名称用于兼容 Uni 风格，分类名称建议用于新代码。

| Action | 等价分类名 | `data` 入参 | 成功 `data` 返回 |
| --- | --- | --- | --- |
| `getSystemInfo` | `system.getSystemInfo` | `{}` | [系统信息](client_capabilities.md#getsysteminfo) 对象 |
| `getDeviceInfo` | `device.getDeviceInfo` | `{}` | [设备信息](client_capabilities.md#getdeviceinfo) 对象 |
| `getNetworkType` | `network.getNetworkType` | `{}` | 网络状态对象 |
| `getCapabilities` | `capabilities.get` | `{}` | `{capabilities:[{name,isSupported,message}]}` |
| `setClipboardData` | `clipboard.setData` | `{data:string}` | `{ok:true}` |
| `getClipboardData` | `clipboard.getData` | `{}` | `{data:string|null}` |
| `chooseFile` | `file.chooseFile` | `{allowMultiple?:boolean,allowedExtensions?:string[],title?:string}` | `{files:[{fileId,name,size,mimeType,uri,path,…}]}` |
| `saveFile` | `file.saveFile` | `{fileName:string,base64:string,mimeType?:string,title?:string,initialDirectory?:string}` | `{file:{uri,path,hasNativePath}|null}` |
| `readFile` | `file.readFile` | `{fileId:string}` | `{file,base64}`，上限 10 MiB |
| `getFileInfo` | `file.getInfo` | `{fileId:string}` | `{file}` |
| `releaseFile` | `file.release` | `{fileId:string}` | `{released:boolean}` |
| `uploadFile` | `file.upload` | `{fileId,uploadUrl,method?:POST\|PUT,multipart?:boolean,fieldName?:string,headers?:object,formData?:object,timeoutSeconds?:5..600}` | 立即返回 `{task:{taskId,state:'queued',…}}` |
| `getUploadTask` | `file.getUploadTask` | `{taskId:string}` | `{task}` |
| `cancelUpload` | `file.cancelUpload` | `{taskId:string}` | `{cancelled:boolean}` |
| `onUploadEvent` | `file.onUploadEvent` | `{subscriptionId?:string,taskId?:string}` | `{subscriptionId,taskId}` |
| `offUploadEvent` | `file.offUploadEvent` | `{subscriptionId:string}` | `{removed:boolean}` |
| `clearTemporaryFiles` | `file.clearTemporaryFiles` | `{}` | `{cleared:boolean}` |
| `chooseImage` | `media.chooseImage` | [媒体选择参数](media_and_files.md#图片与相机) | `{files:[file]}` |
| `takePhoto` | `media.takePhoto` | 同上 | `{file:file|null}` |
| `chooseVideo` | `media.chooseVideo` | `{maxDurationSeconds?:int}` | `{file:file|null}` |
| `recordVideo` | `media.recordVideo` | `{maxDurationSeconds?:int}` | `{file:file|null}` |
| `compressImage` | `image.compress` | `{fileId:string,quality?:int,maxWidth?:int,maxHeight?:int,format?:jpeg\|png\|webp}` | `{image:{fileName,mimeType,size,originalSize,width,height},base64}` |
| `getVideoInfo` | `video.getInfo` | `{fileId:string}` | `{durationMs,width,height,size,path}` |
| `getVideoThumbnail` | `video.getThumbnail` | `{fileId:string,quality?:int,positionMs?:int}` | `{mimeType:'image/jpeg',base64}` |
| `compressVideo` | `video.compress` | `{fileId:string,quality?:low\|medium\|high\|original,includeAudio?:boolean}` | `{file:file|null}` |
| `startAudioRecording` | `audio.startRecording` | `{fileNamePrefix?:string,sampleRate?:int,bitRate?:int,numChannels?:int}` | `{started:true}` |
| `pauseAudioRecording` | `audio.pauseRecording` | `{}` | `{paused:true}` |
| `resumeAudioRecording` | `audio.resumeRecording` | `{}` | `{resumed:true}` |
| `stopAudioRecording` | `audio.stopRecording` | `{}` | `{file:file|null}` |
| `cancelAudioRecording` | `audio.cancelRecording` | `{}` | `{cancelled:true}` |
| `scanCode` | `scan.scanCode` | `{formats?:string[],title?:string,tip?:string,allowAlbum?:boolean,allowTorch?:boolean}` | `{result:{content,format,source}|null}` |
| `decodeImage` | `image.decodeImage` / `scan.decodeImage` | `{base64?:string,fileId?:string,formats?:string[]}`（二者之一必填） | `{result:{content,format,source}|null}` |
| `scanCodeFromImage` | `scan.chooseImageAndDecode` | 图片选择参数及 `formats?:string[]` | `{file:file|null,result:{content,format,source}|null}` |
| `onNetworkStatusChange` | `network.onStatusChange` | `{subscriptionId?:string}` | `{subscriptionId:string}` |
| `offNetworkStatusChange` | `network.offStatusChange` | `{subscriptionId:string}` | `{removed:boolean}` |
| `notification.getSupport` | — | `{}` | `{platform,isSupported,message}` |
| `notification.requestPermission` | — | `{}` | `{status,message}` |
| `vibrate` | `device.vibrate` | `{style?:light\|medium\|heavy\|selection\|vibrate,duration?:int}` | `{ok:true}` |
| `getBatteryInfo` | `device.getBatteryInfo` | `{}` | `{level:int,isCharging:boolean,status:string}` |
| `getScreenBrightness` | `device.getScreenBrightness` | `{}` | `{value:double}`（0.0 ~ 1.0） |
| `setScreenBrightness` | `device.setScreenBrightness` | `{value:double}`（0.0 ~ 1.0） | `{ok:boolean,value:double}` |
| `makePhoneCall` | `system.makePhoneCall` | `{phoneNumber:string}` | `{ok:boolean}` |
| `onUserCaptureScreen` | `system.onUserCaptureScreen` | `{subscriptionId?:string}` | `{subscriptionId:string}` |
| `offUserCaptureScreen` | `system.offUserCaptureScreen` | `{subscriptionId:string}` | `{removed:boolean}` |
| `onThemeChange` | `system.onThemeChange` | `{subscriptionId?:string}` | `{subscriptionId,currentBrightness:light\|dark}` |
| `offThemeChange` | `system.offThemeChange` | `{subscriptionId:string}` | `{removed:boolean}` |
| `onResize` | `system.onResize` | `{subscriptionId?:string}` | `{subscriptionId,currentSize:{width,height}}` |
| `offResize` | `system.offResize` | `{subscriptionId:string}` | `{removed:boolean}` |
| `onMemoryWarning` | `system.onMemoryWarning` | `{subscriptionId?:string}` | `{subscriptionId:string}` |
| `offMemoryWarning` | `system.offMemoryWarning` | `{subscriptionId:string}` | `{removed:boolean}` |
| `onAccelerometerChange` | `sensor.onAccelerometerChange` | `{subscriptionId?:string,interval?:int}` | `{subscriptionId:string}` |
| `offAccelerometerChange` | `sensor.offAccelerometerChange` | `{subscriptionId?:string}` | `{ok:true}` |
| `onGyroscopeChange` | `sensor.onGyroscopeChange` | `{subscriptionId?:string,interval?:int}` | `{subscriptionId:string}` |
| `offGyroscopeChange` | `sensor.offGyroscopeChange` | `{subscriptionId?:string}` | `{ok:true}` |
| `onProximityChange` | `sensor.onProximityChange` | `{subscriptionId?:string}` | `{subscriptionId:string}` |
| `offProximityChange` | `sensor.offProximityChange` | `{subscriptionId?:string}` | `{ok:true}` |
| `diagnostics.reportHostPing` | — | `{pingId:string,receivedAt:string,success:boolean,systemInfo?:object,error?:object}` | `{received:true}`；仅 Debug Harness 用于上报主动调用回执 |

`formats` 使用 Flutter 枚举名，例如 `qrCode`、`code128`、`ean13`；空数组表示默认全部。`decodeImage.base64` 可以是纯 base64，也可以是 `data:image/png;base64,...`，最大解码后大小为 10 MiB。文件选择结果包含平台可用的原始 URI/路径；`fileId` 只在当前宿主会话有效。URI/path 不是 H5 可直接访问的地址，后续操作必须传 `fileId`。媒体能力、上传白名单与平台限制见 [媒体与文件能力](media_and_files.md)。

详细字段语义和平台支持矩阵见 [客户端能力统一入口](client_capabilities.md)。

## 网络订阅事件

调用 `onNetworkStatusChange` 成功后，Flutter 在网络变化时发送独立事件消息：

```json
{
  "event":"network.statusChange",
  "data":{
    "subscriptionId":"network-1",
    "status":{
      "networkTypes":["wifi"],
      "isConnected":true,
      "observedAt":"2026-08-19T00:00:00.000Z"
    }
  }
}
```

页面销毁或不再监听时必须调用 `offNetworkStatusChange`，避免保留 Stream 订阅。网络类型仅代表传输层状态，不代表后端可达。

## 文件上传与事件示例

```javascript
const { files } = await goto.invoke('file.chooseFile', { allowMultiple: false });
const file = files[0];
if (!file) return; // 用户取消

const { subscriptionId } = await goto.invoke('file.onUploadEvent', {});
const stopProgress = goto.on('file.uploadProgress', (event) => {
  if (event.subscriptionId !== subscriptionId) return;
  console.log(`${Math.round(event.progress * 100)}%`, event.sentBytes, event.totalBytes);
});

goto.on('file.uploadCompleted', (event) => {
  if (event.subscriptionId === subscriptionId) console.log(event.response);
});
goto.on('file.uploadFailed', (event) => {
  if (event.subscriptionId === subscriptionId) console.error(event.error);
});

const { task } = await goto.invoke('file.upload', {
  fileId: file.fileId,
  uploadUrl: 'https://uploads.example.com/presigned-path',
  method: 'PUT',
  multipart: false,
  headers: { 'Content-Type': file.mimeType || 'application/octet-stream' },
  timeoutSeconds: 120
});

// 需要取消时：await goto.invoke('file.cancelUpload', { taskId: task.taskId });
// 页面销毁时：await goto.invoke('file.offUploadEvent', { subscriptionId }); stopProgress();
```

上传地址主机必须位于 Flutter 环境变量 `JS_BRIDGE_UPLOAD_ALLOWED_HOSTS`。Bridge 不会自动附带 App Token；使用业务后端签发的短期上传令牌或对象存储预签名 URL。`UPLOAD_DISABLED` 表示白名单未配置，`UPLOAD_HOST_NOT_ALLOWED` 表示主机不在白名单，`UPLOAD_FAILED` 会通过失败事件给出网络或 HTTP 状态。开发诊断预置地址来自 `JS_BRIDGE_UPLOAD_URL`（当前为 `http://10.0.5.20:4173/upload`），而不是根据 Harness 页面地址拼接。

## Flutter 主动调用 H5

Harness 宿主可通过 WebView 向页面投递独立事件；当前诊断按钮发送：

```json
{
  "event": "host.command",
  "data": {"name": "harness.ping", "pingId": "2026-08-20T00:00:00.000Z"}
}
```

H5 收到 `host.command` 后调用 `getSystemInfo`，再调用仅供诊断使用的 `diagnostics.reportHostPing`。Flutter 会发出 `diagnostics.hostPingResult` 事件，Harness 页将完整 payload 显示在“Flutter → H5 Ping 回执”面板；`success:true` 且带有 `systemInfo` 即代表 Flutter → H5 → Flutter 的往返链路已完成。该面板可直接复制用于缺陷报告。业务 H5 不应依赖 `diagnostics.*` action。

## H5 Promise 包装示例

宿主应为每个请求建立 Promise，并在收到匹配 `id` 的响应时 resolve/reject；事件通过独立回调分发：

```javascript
const result = await goto.invoke('getSystemInfo', {});
const { subscriptionId } = await goto.invoke('onNetworkStatusChange', {});
goto.on('network.statusChange', ({ subscriptionId: id, status }) => {
  if (id === subscriptionId) console.log(status.networkTypes);
});
```

不要把 access token、刷新 token、私密文件路径或大文件二进制放入 Bridge `data`。Bridge 是 H5 与宿主能力的边界，不替代后端鉴权、上传或下载 API。

## WebView 宿主接入

宿主创建时将 `JsBridgeTransport` 适配到具体 WebView 的 `evaluateJavascript`/消息通道，然后：

```dart
final session = JsBridgeSession(dispatcher: dispatcher, transport: transport);
session.start();
// flutter_inappwebview JavaScript Handler 收到 message 后：
await session.handleIncoming(message);
// WebView 销毁时：
await session.dispose();
```

`JsBridgeSession` 不拥有也不会销毁全局 `JsApiDispatcher`，因此多个 WebView 的订阅生命周期应由宿主明确管理。Harness 已统一使用 `flutter_inappwebview`，业务页面若采用其他 WebView 插件，只需另建 transport 适配器，不需要复制或改动 API 分发代码。
