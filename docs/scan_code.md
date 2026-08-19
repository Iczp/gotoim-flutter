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

当前可跨 Web 与桌面稳定运行的本地图片解码实现保证 QR 码识别；Android/iOS 相册图片和实时相机均由原生扫描器识别请求中配置的多种码制。

## 目标支持策略

| 场景 | UI | 识别能力 |
| --- | --- | --- |
| Android / iOS（含平板） | 相机、扫描框动画、闪光灯、相册 | 由 `mobile_scanner` 支持的多种二维码与条形码 |
| Web / Windows / macOS / Linux | 明确提示暂不支持相机扫码；可上传图片 | 本地图片二维码识别 |

桌面和 Web 不初始化或模拟相机扫描插件；保留同一个 API，以便后续按平台接入更合适的实现。上传识别使用纯 Dart 解码器，因此不依赖相机或文件路径，当前保证 QR 码识别。若请求排除了 QR 码，会提示该平台暂不支持所请求的图片码制。

## 架构

```text
业务页面 / 后续 JsApiDispatcher
             -> ScanCodeService.scanCode(...)
             -> ScanCodePage
             -> Android/iOS: MobileScanner
             -> Web/桌面: 不支持相机提示 + 图片二维码解码
```

`NavigatorState` 作为 API 参数，未来 JS Bridge 可传入应用级 Navigator，而不用复制一套扫描实现。

## 依赖与升级边界

当前工作区的 Flutter 3.7.7 / Dart 2.19.4 最多只能解析 `mobile_scanner 3.5.7`，本项目已使用该工具链下可解析的最新版本；它只作为 Android/iOS 相机适配器，绝不因 Web 或桌面兼容性再降级。Android/iOS 已验证构建；该旧 Flutter 在编译 `mobile_scanner 3.5.7` 的 Web 插件时不认识 `dart:ui_web`，因此 Web 上传页需要在工具链升级后才能构建运行。

`mobile_scanner 7.4.0` 需要 Dart 3.7，迁移它需要先升级 Flutter SDK，再统一升级项目的 Dart 约束和相关插件。该升级属于项目工具链迁移，完成后再将此适配器升级到 v7；接口 `ScanCodeService`、`ImageCodeService` 与业务调用方不需要变更。

## 测试

Debug 登录后进入“开发诊断中心 -> 统一扫码测试”：

1. 使用“扫描所有支持的码”验证二维码和条形码。
2. 在移动端验证扫描线、闪光灯及相册识别。
3. 在 Web、Windows、macOS、Linux 验证“暂不支持相机扫码”提示、“上传二维码图片”按钮及二维码图片识别。
4. 单元测试：`flutter test test/scan_code_models_test.dart`。
