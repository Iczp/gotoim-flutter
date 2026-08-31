# GotoIM Flutter

跨平台 GotoIM 客户端，当前已具备认证、统一 SQLite、本地优先的会话/聊天、媒体文件能力与开发诊断中心。Android、iOS、桌面和 Web 共用 Flutter 业务层；平台差异通过服务和条件实现隔离。

当前开发重点：

- SignalR 事件由全局同步协调器落库，并按缓存聊天身份执行会话增量同步；
- 会话、聊天和联系人均优先读取本地缓存，网络结果异步回写；
- 继续完成推送、跨端联调、工作台服务端契约和未接入的消息类型。

工作台仍是本地开发数据源：已保存的后端 API 契约尚未包含工作台应用列表接口，因此不能安全替换为猜测的 API 路径。

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

### 在当前 PowerShell 先执行：

```bash
$env:Path = 'E:\sdk\flutter-3.47.0-active\bin;' + $env:Path
flutter --version
flutter run
```

得出：

```bash
(base) PS F:\Dev\GotoIM\gotoim-flutter> $env:Path = 'E:\sdk\flutter-3.47.0-active\bin;' + $env:Path
(base) PS F:\Dev\GotoIM\gotoim-flutter> flutter --version
Flutter 3.47.0 • channel stable • https://github.com/flutter/flutter.git
Framework • revision 4cf2416426 (7 days ago) • 2026-08-11 11:53:49 -0700
Engine • hash 59d54a2b2896a6bbf356c94b7fac7b9e235bdacd (revision 5f77625673) (7 days ago) • 2026-08-11 16:38:36.000Z
Tools • Dart 3.13.0 • DevTools 2.60.0
```

