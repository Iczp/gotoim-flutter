# JS Bridge 测试方法

## 当前工程内测试

1. 以 Debug 启动 Flutter 应用，进入“开发诊断中心 → JS Bridge 测试”。
2. 点击“系统信息”“网络类型”“能力清单”等预设，确认响应具有相同的 `id` 与 `success:true`。
3. 发送以下订阅请求，记录响应中的 `subscriptionId`：

```json
{"id":"network-1","action":"onNetworkStatusChange","data":{"subscriptionId":"network-test"}}
```

4. 切换 Wi‑Fi/移动网络，确认“异步事件”收到 `network.statusChange`。随后必须发送：

```json
{"id":"network-off","action":"offNetworkStatusChange","data":{"subscriptionId":"network-test"}}
```

5. 在“媒体与文件测试”选择一张二维码图片，确认“图片识码”显示 `content`、`format` 和 `source`；再测试拍照、录像、录音、另存为。移动设备上必须接受相机、相册、麦克风授权。

自动化层已覆盖 JSON 请求/响应、未知 action、网络订阅事件和 `JsBridgeSession` transport 转发；实际相机/麦克风/系统文件对话框需在真机手工验证。

## 独立 Web 测试站

已创建独立、无业务鉴权的静态 H5 harness：`F:\Dev\GotoIM\gotoim-flutter-jsbridge`。原因是普通 Flutter Web 没有 WebView JavaScriptChannel，无法端到端验证“网页 → 宿主 → 网页”链路；必须将该站点装载在 Flutter 的原生 WebView 中。

站点包含：

- `index.html`：action 下拉、JSON 编辑器、请求/响应/事件面板；
- `bridge-client.js`：以 `id` 匹配 Promise、监听 `network.statusChange`、支持取消订阅；
- `fixtures/`：小于 10 MiB 的二维码图片和媒体样本；
- 无 Token、无私有 API、无真实用户数据。

启动方法：

```powershell
cd F:\Dev\GotoIM\gotoim-flutter-jsbridge
python -m http.server 4173
```

在 Flutter Debug 应用中进入“开发诊断中心 → JS Bridge Harness”。Android 模拟器默认使用 `http://10.0.2.2:4173`；真机需填电脑局域网 IP；iOS/macOS 本机模拟器通常可填 `http://127.0.0.1:4173`。Harness 路由仅在 Android、iOS、macOS 启用；Windows/Web 继续使用 JSON 模拟诊断页。

最小验证矩阵：Android 真机（相机、录像、录音、视频压缩）、iPhone/iPad（权限与相册）、Windows（文件路径/另存为/录音）、WebView 中的 H5（所有 JSON action、取消订阅和文件引用失效）。在生产接入实际 WebView 插件之前，先用该 harness 固化协议回归测试最合适。
