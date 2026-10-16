# 设备注册

默认入口 `/api/chat/device/register`，发送旧 64 字段平铺资料。设备 DeviceId 继续使用客户端安装标识/硬件信息或浏览器指纹，服务端 Guid 不替代客户端标识。

独立接口可配置 `DEVICE_REGISTRATION_API_PATH=/api/app-device/public/device-public/register`。请求为 appId/deviceId/profile；profile 含 61 项强类型资料，不发送 isEnabled 等管理状态。OAuth ClientId 必须获准访问对应 APP_ID。

注册使用独立 client_credentials Token；不保存、发送 registrationProof，也不发送 AppDevice-Registration-Proof Header。登录和注册互不等待；并发注册合并为一次请求。原安全日志脱敏规则保留，兼容旧服务响应。诊断页展示配置入口、实际请求形状和真实返回。

旧 Chat 注册入口可由服务端 Device:UseAppDevice 开关转到独立设备库，无需客户端改变协议。实际数据源与历史迁移状态见服务端部署文档；2026-10-16 已完成服务端历史数据迁移，Chat/Auth/Worker 已开启新设备数据源；当前 `.env.development` 已配置上述独立 Public 入口，需重启客户端加载配置。生产环境文件和已安装客户端不会由此自动更新。

验证：设备注册测试、认证恢复测试、登录页面测试及受影响文件 analyze。Android/iOS 真机和安装包发布需单独验证。
