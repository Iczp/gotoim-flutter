# 登录页会话失效与 Tooltip 排查（2026-10-26）

## 已修正的认证链路

Rctea.IM 的 IM、Chat、Cms、Social、AppStatistic、AppDevice API 已使用独立 audience。客户端各环境的 AUTH_SCOPE 同步申请六个业务 scope，并保留各环境已有身份 scope。新配置只影响新授权，旧访问令牌和 refresh token 不会因此扩展授权，必须重新登录。

`/api/chat/device/register` 的机器令牌改为申请 Chat；匿名扫码连接仍申请 IM，因为它使用 IM 宿主上的扫码通道。机器令牌继续与用户令牌隔离。

统一 DioApiClient 仅在本次请求实际使用了非空的本地用户令牌时，才因 401 尝试刷新或使会话失效。无用户令牌的请求收到 401，按原始 API 错误返回，不创建用户会话，也不触发“登录已失效”提示。已有的全局并发刷新、刷新失败清理及显式 Authorization 行为保留。

涉及客户端 HTTP 基础设施、认证 Repository、环境配置与现有认证诊断页，不修改后端 API、数据库、Redis 或 Migration。

## 验证入口

开发诊断中心 → 认证与敏感凭据 → 登录参数：可以查看、复制“新登录申请的 scope”。该页已有登录、刷新和凭据核对入口。需使用测试账号重新登录，检查实际 JWT 的 aud 包含目标服务；不要在日志、截图或提交内容中记录完整令牌。

自动化验证：

```powershell
flutter test --no-pub test/dio_api_client_test.dart test/auth_session_restore_test.dart test/core/device/device_registration_api_test.dart
flutter test --no-pub test/app_environment_test.dart test/login_and_registration_test.dart
```

认证链路 21 项、环境配置 5 项、登录页 2 项，共 28 项通过。覆盖匿名 401 不刷新/不退出、预刷新、多个 401 共用刷新、缺失 refresh token、临时网络失败、旧刷新不能覆盖新登录、设备注册申请 Chat、全部环境申请六个业务 scope。7 个相关 Dart 文件的 flutter analyze 通过。

## Tooltip 限制

附件里的 `[Statistic] track: crash` 是异常记录；具体异常是 Flutter `RawTooltipState` 创建多个 ticker。它不等于统计上传 API 报错，也不能仅凭该堆栈判定它与令牌失效具有同一原因。

用户确认完整重启后、未操作登录页也会报错。已补触屏长按、反复切换密码可见性、鼠标悬停与切换主题的回归测试，并模拟 Windows 目标下鼠标预先位于窗口中、登录页首帧、标题栏悬停和页面移除；这些路径通过，尚未复现附件中的 SDK 异常。测试使用本机 Flutter 3.47.0 / Dart 3.13.0。未修改 Flutter SDK、未关闭 Tooltip、未屏蔽异常处理。

若真实应用仍有异常，需要从进程启动开始、包含第一次异常之前内容的日志，并记录实际启动使用的 Flutter SDK 路径与版本。后续重复的 multiple tickers 堆栈不足以确定第一次创建控制器失败的原因。
