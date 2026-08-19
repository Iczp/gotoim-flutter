# JS Bridge

JS Bridge 位于 `lib/core/jsbridge/`，由 `JsApiDispatcher` 完成 JSON 协议解析和能力分发。`JsBridgeSession` 将调度器绑定到 `JsBridgeTransport`：宿主 WebView 只需把 JavaScriptChannel 收到的文本传给 `handleIncoming()`，并实现 `postMessage()` 回推响应/事件。这使 `webview_flutter`、桌面 WebView 和未来宿主适配器能共享同一个协议。

开发验证入口：Debug 模式的“开发诊断中心 → JS Bridge 测试”。该页会模拟 JavaScriptChannel 输入，显示完整响应，并显示网络订阅事件。

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
| `chooseFile` | `file.chooseFile` | `{allowMultiple?:boolean,allowedExtensions?:string[],title?:string}` | `{files:[{name,size,extension,hasNativePath}]}` |
| `scanCode` | `scan.scanCode` | `{formats?:string[],title?:string,tip?:string,allowAlbum?:boolean,allowTorch?:boolean}` | `{result:{content,format,source}|null}` |
| `decodeImage` | `image.decodeImage` | `{base64:string,formats?:string[]}` | `{result:{content,format,source}|null}` |
| `onNetworkStatusChange` | `network.onStatusChange` | `{subscriptionId?:string}` | `{subscriptionId:string}` |
| `offNetworkStatusChange` | `network.offStatusChange` | `{subscriptionId:string}` | `{removed:boolean}` |
| `notification.getSupport` | — | `{}` | `{platform,isSupported,message}` |
| `notification.requestPermission` | — | `{}` | `{status,message}` |

`formats` 使用 Flutter 枚举名，例如 `qrCode`、`code128`、`ean13`；空数组表示默认全部。`decodeImage.base64` 可以是纯 base64，也可以是 `data:image/png;base64,...`，最大解码后大小为 10 MiB。文件选择结果刻意没有本地路径或文件 bytes。

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
// JavaScriptChannel 收到 message 后：
await session.handleIncoming(message);
// WebView 销毁时：
await session.dispose();
```

`JsBridgeSession` 不拥有也不会销毁全局 `JsApiDispatcher`，因此多个 WebView 的订阅生命周期应由宿主明确管理。当前工程未强行引入某个 WebView 插件；页面实际接入时只需增加该平台的 transport 适配器，不需要复制或改动任何 API 分发代码。
