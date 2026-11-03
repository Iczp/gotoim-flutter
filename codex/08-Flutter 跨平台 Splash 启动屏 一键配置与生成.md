# Flutter 跨平台 Splash 启动屏 一键配置与生成

## 1. 目标

在现有 Flutter 项目中实现统一的 Splash / 启动画面管理。

要求支持：

- Android
- iOS
- macOS
- Windows
- linux
- Web 可预留，不是本次重点

最终开发人员只维护：

```text
config/splash.yaml
assets/branding/splash/
```

执行一个命令：

```bash
dart run tool/app.dart splash apply
```

即可自动完成所有平台 Splash 配置和资源生成。

不要要求开发人员分别修改：

- Android XML
- iOS Storyboard
- macOS Runner
- Windows Runner
- Flutter StartupPage

所有这些配置必须由工具自动生成或维护。

------

# 2. 核心原则

## 2.1 一份配置

Splash 所有平台共用：

```text
config/splash.yaml
```

不要出现：

```text
windows_splash.yaml
macos_splash.yaml
ios_splash.yaml
android_splash.yaml
```

平台特殊参数允许存在，但必须放在同一个配置文件中。

------

## 2.2 一个跨平台 CLI

必须使用 Dart 编写 CLI。

不要依赖：

- bash
- PowerShell
- Makefile
- Python
- Node.js

确保下面的命令在 Windows 和 macOS 都能直接运行：

```bash
dart run tool/app.dart splash apply
```

------

# 3. 目录设计

Codex 首先检查现有项目结构，根据项目实际情况放置，不要为了本文档强制修改现有架构。

建议：

```text
config/
└── splash.yaml

assets/
└── branding/
    └── splash/
        ├── logo.png
        ├── logo_dark.png
        ├── logo_dev.png
        └── logo_test.png

tool/
├── app.dart
└── splash/
    ├── splash_command.dart
    ├── splash_config.dart
    ├── splash_validator.dart
    ├── splash_generator.dart
    ├── android_generator.dart
    ├── ios_generator.dart
    ├── macos_generator.dart
    ├── windows_generator.dart
    └── flutter_generator.dart

lib/
└── core/
    └── startup/
        ├── startup_page.dart
        ├── startup_controller.dart
        ├── startup_state.dart
        ├── startup_logger.dart
        └── generated/
            └── splash_config.g.dart

docs/
└── development/
    └── splash.md
```

其中：

```text
generated/
```

内容禁止人工维护。

------

# 4. splash.yaml

建议配置：

```yaml
version: 1

splash:
  enabled: true

  background:
    light: "#FFFFFF"
    dark: "#101010"

  image:
    light: "assets/branding/splash/logo.png"
    dark: "assets/branding/splash/logo_dark.png"

  layout:
    fit: contain
    alignment: center
    imageWidth: 160

  platforms:
    android: true
    ios: true
    macos: true
    windows: true
    web: false

  android:
    fullscreen: false

    android12:
      enabled: true
      background: "#FFFFFF"
      backgroundDark: "#101010"
      image: "assets/branding/splash/logo.png"
      imageDark: "assets/branding/splash/logo_dark.png"

  ios:
    contentMode: center
    fullscreen: false

  windows:
    width: 520
    height: 320
    frameless: true
    centerScreen: true

  macos:
    width: 520
    height: 320
    frameless: true
    centerScreen: true

startup:
  enabled: true

  showLoading: true
  showProgress: false

  minimumDisplayMilliseconds: 0
  timeoutMilliseconds: 10000

  transition:
    type: fade
    durationMilliseconds: 150

  error:
    showRetry: true
    allowEnterApp: false
```

字段名称可以根据项目已有配置规范调整。

不要直接把 YAML 字段到处读取。

执行生成命令以后，应生成：

```text
lib/core/startup/generated/splash_config.g.dart
```

Flutter Runtime 使用生成后的 Dart 常量。

------

# 5. Flavor 支持

需要支持：

```bash
dart run tool/app.dart splash apply --flavor dev

dart run tool/app.dart splash apply --flavor test

dart run tool/app.dart splash apply --flavor prod
```

配置：

```yaml
flavors:

  dev:
    image:
      light: "assets/branding/splash/logo_dev.png"

  test:
    image:
      light: "assets/branding/splash/logo_test.png"

  prod:
    image:
      light: "assets/branding/splash/logo.png"
```

Flavor 配置采用：

```text
default
    ↓
flavor override
    ↓
最终配置
```

不要复制整套配置。

------

# 6. CLI

实现：

```bash
dart run tool/app.dart splash init
```

作用：

- 初始化目录
- 创建 splash.yaml 模板
- 不覆盖已有配置
- 创建使用文档

------

检查：

```bash
dart run tool/app.dart splash check
```

检查：

- YAML 是否有效
- 图片是否存在
- PNG 是否有效
- 图片尺寸是否合理
- Dark 图片是否存在
- Android 12 配置是否合法
- Windows/macOS Runner 是否存在
- iOS/Android 工程是否存在
- pubspec 配置是否正确

只检查，不修改文件。

------

正式生成：

```bash
dart run tool/app.dart splash apply
```

执行顺序：

```text
读取 splash.yaml
        ↓
解析 flavor
        ↓
Schema 校验
        ↓
资源校验
        ↓
生成 Flutter 配置
        ↓
生成 Android Splash
        ↓
生成 iOS Splash
        ↓
生成 macOS Splash
        ↓
生成 Windows Splash
        ↓
验证生成结果
        ↓
输出总结
```

------

同时支持：

```bash
dart run tool/app.dart splash apply --dry-run
```

仅显示：

```text
将修改哪些文件
将新增哪些文件
当前配置
```

不要真正修改。

------

诊断：

```bash
dart run tool/app.dart splash doctor
```

例如：

```text
Splash Doctor

[OK] config/splash.yaml
[OK] logo.png
[OK] logo_dark.png

[OK] Android
[OK] Android 12
[OK] iOS
[OK] macOS
[OK] Windows

[OK] Flutter StartupPage

Splash configuration is healthy.
```

发生错误时必须明确指出：

```text
[ERROR] macOS splash image does not exist:
assets/branding/splash/logo_dark.png
```

不要只输出：

```text
Generate failed.
```

------

# 7. Android / iOS

Android/iOS 优先使用成熟方案：

```text
flutter_native_splash
```

但不要让业务开发人员直接维护：

```text
flutter_native_splash.yaml
```

我们的工具根据：

```text
config/splash.yaml
```

临时生成对应配置，然后调用生成命令。

例如内部执行：

```bash
dart run flutter_native_splash:create
```

版本不要在代码中写死。

使用项目当前兼容的稳定版本。

Android 12+ 必须单独处理 Splash Screen API 的限制。

Android 12 不允许按照普通 Splash 那样任意使用整屏背景图片，因此生成器必须正确转换配置，而不是假装四个平台行为完全一致。

------

# 8. Windows

`flutter_native_splash` 不负责 Windows。

Windows 必须实现真正的 Native Splash。

目标：

```text
用户双击 App
       ↓
立即出现 Native Splash
       ↓
Flutter Engine 初始化
       ↓
StartupPage 第一帧完成
       ↓
显示 Flutter 主窗口
       ↓
关闭 Native Splash
```

不能出现：

```text
点击
↓
白屏
↓
黑屏
↓
Flutter
↓
Splash
```

## Windows Native 实现

在：

```text
windows/runner/
```

实现 Splash Window。

建议使用 Flutter 项目已经使用的 Win32 Runner。

原则：

- 不增加重量级 UI 框架
- 不启动第二个进程
- Splash 属于当前进程
- 支持 PNG
- 支持背景色
- 支持 DPI
- 多显示器正确居中
- 支持 Light / Dark
- 无边框
- 默认不显示任务栏独立图标
- 主窗口 Ready 后自动关闭

图片加载优先考虑 Windows 原生能力，如 WIC。

不要为了显示一张启动图引入 Electron、Qt 等大型依赖。

------

# 9. macOS

macOS 同样不能依赖 `flutter_native_splash` 完成 Desktop Splash。

在：

```text
macos/Runner/
```

实现 Native Splash Window。

流程：

```text
App Launch
    ↓
NSWindow Splash
    ↓
Flutter Engine 初始化
    ↓
Flutter StartupPage Ready
    ↓
MainFlutterWindow 显示
    ↓
Splash NSWindow 关闭
```

使用：

```text
AppKit
NSWindow
NSImage
NSImageView
```

支持：

- Retina
- Light Mode
- Dark Mode
- 多显示器
- 居中
- 无边框
- 正确缩放图片

禁止启动第二个进程实现 Splash。

------

# 10. Native 与 Flutter 交接

这是本功能的重要部分。

Native Splash 和 Flutter StartupPage 必须视觉一致。

例如：

```text
Native
白色背景
160px Logo
居中

        ↓

Flutter StartupPage
白色背景
160px Logo
居中
Loading
```

Native → Flutter 不应该产生明显跳动。

------

# 11. Flutter StartupPage

Native Splash 只负责：

```text
Flutter 第一帧之前
```

Flutter StartupPage 负责：

```text
Flutter Ready
+
应用必要初始化
```

例如：

```text
StartupPage
     ↓
并行初始化
     ├── Environment
     ├── Theme
     ├── Token
     ├── Drift
     └── Local Settings
     ↓
确定入口
     ├── Home
     └── Login
```

不要在 Splash 阶段等待：

- SignalR 完整连接
- 统计上传
- 非必须缓存
- 非必须接口
- 非关键后台任务

这些进入主页面以后继续执行。

------

# 12. 初始化接口

不要让 StartupPage 自己塞大量初始化代码。

设计类似：

```dart
abstract interface class StartupTask {
  String get name;

  Future<void> execute();
}
```

例如：

```text
EnvironmentStartupTask
ThemeStartupTask
DatabaseStartupTask
AuthStartupTask
```

但不要为了架构而过度抽象。

如果现有项目已经有初始化服务，应接入现有体系，而不是重新造一套。

------

# 13. Native Splash Ready 通知

Windows/macOS Native Splash 不应该依靠固定：

```text
sleep 2 秒
```

然后关闭。

Flutter StartupPage 第一帧真正绘制完成后通知 Native。

例如 Platform Channel：

```text
app/startup
```

方法：

```text
flutterReady
```

流程：

```text
StartupPage build
      ↓
addPostFrameCallback
      ↓
flutterReady
      ↓
Native
      ↓
show Flutter Window
close Splash Window
```

Android/iOS 根据其原生 Splash 生命周期采用合适方式处理。

------

# 14. Fail-safe

防止 Bug 导致用户永远只能看到 Splash。

Windows/macOS 原生层应存在安全兜底机制。

例如：

```text
Native Splash
      ↓
Flutter 未发送 ready
      ↓
达到安全超时
      ↓
关闭 Splash
显示 Flutter Window
```

超时值应作为内部保护值，不作为正常启动控制方案。

正常启动禁止依赖定时器。

------

# 15. Light / Dark

支持：

```yaml
background:
  light: "#FFFFFF"
  dark: "#101010"

image:
  light: logo.png
  dark: logo_dark.png
```

Flutter、Windows、macOS、iOS、Android 尽量保持一致。

如果没有：

```text
logo_dark.png
```

则允许回退：

```text
logo.png
```

不要强制要求两张图。

------

# 16. 图片校验

`check/apply` 必须校验资源。

至少检查：

```text
存在
格式
可读取
宽高
透明通道
文件大小
```

Android 12 需要额外提示安全区域问题。

例如：

```text
[WARNING]
Android 12 splash logo may be clipped by the system mask.
```

不要静默生成错误资源。

------

# 17. 幂等性

这是验收重点。

连续执行：

```bash
dart run tool/app.dart splash apply
dart run tool/app.dart splash apply
dart run tool/app.dart splash apply
```

结果必须一致。

不能：

- 重复插入代码
- 重复修改 plist
- 重复添加 XML
- 重复写 C++
- 重复添加 Swift
- 每次产生不同结果

生成器必须是幂等的。

------

# 18. Generated File 标记

能够自动生成的文件增加：

```text
GENERATED FILE
DO NOT EDIT MANUALLY
```

如果必须修改已有 Runner 文件，则采用：

```text
// APP_SPLASH_BEGIN
...
// APP_SPLASH_END
```

再次生成时替换这一区块。

禁止通过不可靠的字符串随意 append。

------

# 19. 不破坏已有 Native 代码

生成器运行前必须识别：

```text
windows/runner
macos/Runner
ios/Runner
android
```

已经存在的自定义代码。

只能修改自己管理的区域。

不能：

```text
直接重写整个 AppDelegate.swift
直接重写 flutter_window.cpp
直接重写 Info.plist
```

除非该文件本身就是工具专门生成并拥有的文件。

------

# 20. Flutter 日志

Startup 初始化必须记录耗时。

例如：

```text
[Startup] Environment       3ms
[Startup] Theme             8ms
[Startup] Database         46ms
[Startup] Auth             12ms
[Startup] Required Total   59ms
[Startup] First Route      home
```

错误：

```text
[Startup][ERROR]
Task: Database
Duration: 10003ms
File: database_startup_task.dart
Error: ...
```

日志需要方便 AI/Codex 后续诊断。

------

# 21. 开发诊断中心

如果现有项目已经存在开发诊断中心，把 Splash 加进去。

页面：

```text
开发诊断中心
    ↓
Startup / Splash
```

展示：

```text
当前 Flavor
当前平台
Light/Dark
Logo
背景色

Native Splash: OK
Flutter Startup: OK

Startup Tasks
Environment       3ms
Theme             8ms
Database         46ms
Auth             12ms
```

提供：

```text
模拟 StartupPage
模拟 Light
模拟 Dark
模拟初始化失败
模拟初始化超时
```

用于人工验证。

------

# 22. 配置文档

最终必须创建：

```text
docs/development/splash.md
```

不是只写代码。

文档至少包含：

## 首次配置

```bash
dart run tool/app.dart splash init
```

修改：

```text
config/splash.yaml
```

放入：

```text
assets/branding/splash/logo.png
```

然后：

```bash
dart run tool/app.dart splash apply
```

------

## 修改 Logo

替换：

```text
assets/branding/splash/logo.png
```

然后：

```bash
dart run tool/app.dart splash apply
```

------

## 检查

```bash
dart run tool/app.dart splash check
```

------

## 诊断

```bash
dart run tool/app.dart splash doctor
```

------

## Flavor

```bash
dart run tool/app.dart splash apply --flavor dev
```

------

## 常见问题

至少记录：

- Android 12 Logo 被裁剪
- iOS Splash 没刷新
- Windows 启动闪白
- macOS 启动闪白
- Dark Mode 图片错误
- 配置修改没有生效
- Native 与 Flutter Logo 大小不一致

------

# 23. README 简化入口

项目 README 不需要写完整教程。

只增加：

```markdown
## Splash

配置文件：

config/splash.yaml

生成：

dart run tool/app.dart splash apply

详细说明：

docs/development/splash.md
```

------

# 24. 人工验收

Codex 完成以后必须实际执行验收。

## Windows

执行：

```bash
flutter run -d windows
```

验证：

1. 点击启动立即出现 Splash。
2. 不出现明显白屏/黑屏。
3. Splash 居中。
4. 图片比例正常。
5. Flutter StartupPage 与 Native Splash 基本无跳变。
6. Flutter Ready 后 Native Splash 自动消失。
7. 主窗口正常显示。
8. 重复启动正常。
9. Debug/Release 都正常。

------

## macOS

执行：

```bash
flutter run -d macos
```

验证相同项目。

同时测试：

```text
Light Mode
Dark Mode
Retina
```

------

## iOS

至少测试：

```text
iOS Simulator
```

有真机条件再测试真机。

验证：

```text
Native Launch Screen
↓
Flutter StartupPage
↓
Home/Login
```

不得明显闪白。

------

## Android

至少测试：

```text
Android < 12
Android >= 12
```

重点验证 Android 12 系统 Splash。

------

# 25. CLI 验收

以下全部成功：

```bash
dart run tool/app.dart splash check

dart run tool/app.dart splash apply

dart run tool/app.dart splash doctor

dart run tool/app.dart splash apply --dry-run
```

连续执行两次：

```bash
dart run tool/app.dart splash apply
dart run tool/app.dart splash apply
```

Git Diff 不应产生第二次无意义修改。

------

# 26. 错误验收

人工删除：

```text
logo.png
```

执行：

```bash
dart run tool/app.dart splash check
```

必须失败并告诉用户具体文件。

修改 YAML 为非法颜色：

```yaml
background:
  light: hello
```

必须明确报：

```text
Invalid splash background color:
hello
```

不能产生半生成状态。

------

# 27. 原子生成

`apply` 生成过程中如果任何关键步骤失败：

```text
Android OK
iOS OK
Windows FAILED
```

不能让项目处于不可编译的半生成状态。

建议：

```text
validate
↓
prepare temp files
↓
generate
↓
verify
↓
commit changes
```

必要时自动恢复修改前状态。

------

# 28. 不要做的事情

不要：

- Splash 固定延时 2 秒
- Splash 里面请求大量网络接口
- 使用 Flutter 页面代替真正 Native Splash
- Windows 启动后先显示白色 Flutter Window
- macOS 启动后先闪空白 Window
- 每个平台维护不同配置
- Windows 使用 PowerShell 专属生成脚本
- macOS 使用 Bash 专属生成脚本
- 把绝对路径写进代码
- 写死开发机器路径
- 为 Splash 引入大型 UI 框架
- 破坏已有 Runner 自定义代码

------

# 29. 最终使用体验

开发人员最终只需要：

```text
1. 替换图片

assets/branding/splash/logo.png

2. 修改

config/splash.yaml

3. 执行

dart run tool/app.dart splash apply
```

其它事情全部自动完成。

最终应该做到：

```text
                 splash.yaml
                      │
          dart run tool/app.dart
                 splash apply
                      │
     ┌────────────────┼────────────────┐
     │                │                │
     ▼                ▼                ▼
 Android/iOS     Windows/macOS      Flutter
 Native Splash   Native Splash     StartupPage
     │                │                │
     └────────────────┴────────────────┘
                      │
                 无缝启动体验
```

# 30. Codex 执行要求

Codex 开发前先扫描当前 Flutter 项目：

- pubspec.yaml
- lib/
- android/
- ios/
- macos/
- windows/
- linux/
- 当前启动流程
- 当前主题系统
- 当前日志系统
- 当前开发诊断中心
- 当前 CLI/tool 目录

优先复用现有能力。

不要机械按照本文重新建立重复架构。

完成代码以后：

1. 执行格式化。
2. 执行静态检查。
3. 执行相关测试。
4. 实际执行 Splash CLI。
5. 至少完成当前开发环境可运行平台的人工启动验证。
6. 输出修改文件清单。
7. 输出无法在当前环境验证的平台。
8. 创建 `docs/development/splash.md`。
9. 不留 TODO 示例代码。
10. 最终必须是项目可直接使用的功能，而不是 Demo。