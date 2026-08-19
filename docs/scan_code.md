# 统一扫码 API

`ScanCodeService` 是 Flutter 与未来 WebView JS Bridge 共用的扫码入口。业务页面不直接依赖 `mobile_scanner`、相册选择或平台权限。

```dart
final result = await ref.read(scanCodeServiceProvider).scanCode(
  Navigator.of(context),
  const ScanCodeRequest(
    title: '扫描设备码',
    formats: <ScanCodeFormat>[
      ScanCodeFormat.qrCode,
      ScanCodeFormat.code128,
      ScanCodeFormat.ean13,
    ],
  ),
);

if (result != null) {
  // result.content / result.format / result.source
}
```

关闭扫码页时 API 返回 `null`；调用方无需管理相机控制器、闪光灯或相册权限。

## 图片解码 API

图片识码与文件选择是两项独立能力。`ImageCodeService.decodeImage(...)` 接收任意来源的图片字节，因此相册、桌面上传和未来 WebView JS Bridge 都能使用同一套结果模型：

```dart
final result = await ref.read(imageCodeServiceProvider).decodeImage(
  DecodeImageRequest(bytes: imageBytes),
);
```

当前可跨 Web 与桌面稳定运行的本地图片解码实现保证 QR 码识别；多格式条形码由移动端实时相机扫描支持。

## 支持策略

| 场景 | UI | 识别能力 |
| --- | --- | --- |
| Android / iOS | 相机、扫描框动画、闪光灯、相册 | 由 `mobile_scanner` 支持的多种二维码与条形码 |
| Web / Windows / macOS / Linux 无相机能力 | 上传图片按钮 | 本地图片二维码识别 |

桌面和 Web 的上传识别使用纯 Dart 解码器，因此不依赖相机或文件路径。当前该降级实现保证 QR 码识别；移动端相册识别仍支持请求中配置的多种码制。

## 架构

```text
业务页面 / 后续 JsApiDispatcher
             -> ScanCodeService.scanCode(...)
             -> ScanCodePage
             -> 移动端 MobileScanner / Web 与桌面上传图片解码
```

`NavigatorState` 作为 API 参数，未来 JS Bridge 可传入应用级 Navigator，而不用复制一套扫描实现。

## 测试

Debug 登录后进入“开发诊断中心 -> 统一扫码测试”：

1. 使用“扫描所有支持的码”验证二维码和条形码。
2. 在移动端验证扫描线、闪光灯及相册识别。
3. 在 Web、Windows、macOS、Linux 验证“上传图片”按钮和二维码图片识别。
4. 单元测试：`flutter test test/scan_code_models_test.dart`。
