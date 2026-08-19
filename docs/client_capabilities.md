# 客户端能力统一入口

客户端能力由 `ClientCapabilityService` 统一提供，位置为 `lib/core/capabilities/`。业务页面、Riverpod Provider 和 JS Bridge 只能依赖该契约，不能直接调用 `connectivity_plus`、`device_info_plus`、`file_picker`、相机或系统剪贴板插件。

诊断入口：Debug 模式的“开发诊断中心 → 客户端能力中心”。每次调用会显示实际 JSON 返回值；扫码和本地通知仍在各自独立的诊断页测试。

## 分类与平台边界

| 分类 | 统一 API | Android / iOS / 平板 | Windows / macOS / Linux | Web |
| --- | --- | --- | --- | --- |
| 系统与窗口 | `getSystemInfo` | 支持 | 支持 | 支持 |
| 设备 | `getDeviceInfo` | 支持非敏感信息 | 支持非敏感信息 | 支持浏览器信息 |
| 网络 | `getNetworkType`、`onNetworkStatusChange` | 支持 | 支持 | 支持 |
| 剪贴板 | `setClipboardData`、`getClipboardData` | 支持 | 支持 | 受浏览器手势/权限策略限制 |
| 文件 | `chooseFile` | 系统选择器 | 系统选择器 | 上传选择器 |
| 扫码 | `scanCode`、`decodeImage` | 相机、相册、图片解码 | 不启用相机；选择/上传图片解码 | 不启用相机；上传图片解码 |
| 本地通知 | `notification.*` | 支持，可能需授权 | 支持（Web 另行适配） | 当前返回不支持 |

`getNetworkType` 只表示操作系统检测到的网络传输类型，**不能**用来断定后端或互联网一定可访问。真正的业务请求仍以 Dio 请求结果、超时和重试策略为准。

## Dart 契约

```dart
final capabilities = ref.read(clientCapabilityServiceProvider);
final system = await capabilities.getSystemInfo();
final network = await capabilities.getNetworkType();
final files = await capabilities.chooseFile(
  const FilePickerRequest(allowedExtensions: ['png', 'jpg']),
);
```

`scanCode` 需要 `NavigatorState`，以便打开统一扫码页；H5 调用时由根 Navigator 注入。`decodeImage` 接收 `DecodeImageRequest(bytes: ...)`，图片选择和图片解码互相独立。

## 接口入参与返回值

### `getSystemInfo()`

无入参。返回 `ClientSystemInfo.toJson()`：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `platform` | string | `android`、`ios`、`windows`、`macos`、`linux`、`web` 或 `unknown` |
| `isWeb` | boolean | 是否为 Web 运行环境 |
| `locale` | string | BCP-47 语言标签，例如 `zh-CN` |
| `brightness` | string | `light` 或 `dark` |
| `devicePixelRatio` | number | 物理像素与逻辑像素比例 |
| `windowWidth` / `windowHeight` | number | 当前 Flutter 视图逻辑像素尺寸 |
| `screenWidth` / `screenHeight` | number | 当前可用视图逻辑像素尺寸；多显示器精确物理屏幕信息不在本接口承诺范围内 |
| `safeAreaInsets` | object | `{top,right,bottom,left}`，单位为逻辑像素 |
| `appId` / `appName` / `appVersion` | string | 当前环境配置中的应用标识、名称和版本 |

### `getDeviceInfo()`

无入参。返回 `ClientDeviceInfo.toJson()`：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `platform` / `deviceType` | string | 当前平台和客户端类别 |
| `deviceId` | string | 本应用本地生成并持久化的 UUID；不是 IMEI、MAC、硬件序列号 |
| `brand` / `model` | string? | 平台可提供时返回；否则为 `null` |
| `systemName` / `systemVersion` | string? | 操作系统名称与版本；字段缺失时为 `null` |
| `isPhysicalDevice` | boolean? | 平台支持时返回真机/模拟器状态 |
| `browser` | string? | Web 的浏览器/UA 信息；非 Web 通常为 `null` |

不会返回硬件标识符、通讯录、地理位置或其他敏感信息。

### `getNetworkType()` 与 `onNetworkStatusChange()`

`getNetworkType()` 无入参，`onNetworkStatusChange()` 通过 `networkStatusChanges` Stream 订阅。每个返回/事件为：

```json
{
  "networkTypes": ["wifi", "vpn"],
  "isConnected": true,
  "observedAt": "2026-08-19T00:00:00.000Z"
}
```

`networkTypes` 可取 `none`、`wifi`、`mobile`、`ethernet`、`bluetooth`、`vpn`、`satellite`、`other`。系统可同时报告多个传输类型；仅当列表包含 `none` 时 `isConnected` 为 `false`。

### `setClipboardData(value)` / `getClipboardData()`

`setClipboardData` 的 `value` 为必填 string，成功后 `Future<void>` 完成。`getClipboardData` 无入参，返回 `String?`；没有文本或系统拒绝读取时为 `null`/异常。Web 浏览器可能要求用户手势才能读写。

### `chooseFile(request)`

`FilePickerRequest`：

| 参数 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `allowMultiple` | boolean | `false` | 是否允许选择多个文件 |
| `allowedExtensions` | `List<String>` | `[]` | 可选扩展名白名单，如 `['png','jpg']`；空数组代表不限类型 |
| `dialogTitle` | string? | `null` | 原生选择器标题，平台可忽略 |

返回 `List<SelectedFile>`；用户取消时返回空数组。每项：

```json
{"name":"photo.png","size":12034,"extension":"png","hasNativePath":false}
```

返回值不包含本机绝对路径和二进制字节，避免泄露文件系统信息；上传业务应在后续专用上传契约中处理文件内容。

### `scanCode(navigator, request)`

`ScanCodeRequest`：

| 参数 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `formats` | `List<ScanCodeFormat>` | `[]` | 空表示使用当前平台支持的全部码制 |
| `title` / `tip` | string | 扫码页默认中文文案 | 扫码页标题和提示 |
| `allowAlbum` | boolean | `true` | 是否显示相册/上传图片入口 |
| `allowTorch` | boolean | `true` | 是否显示闪光灯；非相机平台不显示 |

成功返回 `ScanCodeResult?`：`{content, format, source}`；用户关闭或图片中未识别到码时返回 `null`。`source` 是 `camera` 或 `album`。桌面和 Web 不会假装支持相机，而是显示上传图片入口。

### `decodeImage(request)`

`DecodeImageRequest`：`bytes` 为必填 `Uint8List`；`formats` 默认 `[qrCode]`；`source` 默认 `album`。返回同 `ScanCodeResult?`。当前纯 Dart 图片解码适配器承诺二维码；其他码制请使用移动端相机扫描。

### `getCapabilities()`

无入参，返回 `List<ClientCapabilitySupport>`。每项是：

```json
{"name":"scan.scanCode","isSupported":true,"message":"支持相机扫码、相册识别。"}
```

调用方必须依据 `isSupported` 决定是否展示入口，并向用户展示 `message`。

### `notification.getSupport` / `notification.requestPermission`

本地通知由既有 `LocalNotificationService` 实现。支持信息为 `{platform,isSupported,message}`；授权结果为 `{status,message}`，其中 `status` 可为 `granted`、`denied`、`notRequired`、`unsupported`、`unknown`。发送、取消和点击 payload 见 [本地通知文档](local_notifications.md)。
